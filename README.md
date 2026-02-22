# Claude-EdgeChromeDevTools

WindowsマシンとリモートLinuxホスト間でClaude Codeとブラウザ開発者ツール(DevTools)を統合するためのセットアップ自動化スクリプト群です。

## 主な機能

- 🚀 **ワンクリック起動**: 対話型メニューからClaude Code開発環境を瞬時にセットアップ
- 🌐 **ブラウザ統合**: Edge/ChromeのDevToolsとClaude Codeをシームレスに連携
- 🔄 **プロジェクト切り替え**: 複数プロジェクト間の簡単な切り替えと同時実行
- 🎨 **Statusline表示**: カレントディレクトリ、Gitブランチ、モデル名、コンテキスト使用率を可視化
- ⚙️ **中央管理設定**: config.jsonでClaude Code環境変数・UI設定を一元管理
- 🤝 **Agent Teams対応**: 複数Claude Codeインスタンスによる並列作業オーケストレーション

## クイックスタート

### 前提条件

**Windows側:**
- Windows 10/11
- PowerShell 5.1以降
- Microsoft Edge または Google Chrome
- SSH クライアント (OpenSSH)
- Windows Terminal (推奨)

**Linux側:**
- `claude` CLI
- `curl`, `jq`, `fuser`, `git`
- SSHキーベース認証設定済み

### インストール

1. リポジトリをクローン:
   ```cmd
   git clone <repository-url> D:\Claude-EdgeChromeDevTools
   cd D:\Claude-EdgeChromeDevTools
   ```

2. `config/config.json` を環境に合わせて編集:
   ```json
   {
     "zDrive": "Z:\\",
     "linuxHost": "your-linux-host",
     "linuxBase": "/mnt/LinuxHDD",
     "ports": [9222, 9223, 9224, 9225]
   }
   ```

3. SSH接続を設定 (`~/.ssh/config`):
   ```
   Host your-linux-host
     HostName 192.168.1.100
     User your-username
     IdentityFile ~/.ssh/id_rsa
   ```

### 使用方法

#### 方法1: 対話型ランチャー (推奨)

```cmd
start.bat
```

メニューから機能を選択:
- `[1]` Edge版セットアップ
- `[2]` Chrome版セットアップ
- `[3]` Edge接続テスト
- `[4]` Chrome接続テスト

#### 方法2: PowerShellスクリプト直接実行

```powershell
# Edge版
.\scripts\main\Claude-EdgeDevTools.ps1

# Chrome版
.\scripts\main\Claude-ChromeDevTools-Final.ps1
```

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Windows マシン                                   │
│                                                                          │
│  Edge/Chrome (DevTools) ─→ localhost:9222                               │
│           ↓                      │                                       │
│    DevTools Protocol             │ SSH リモートポートフォワーディング      │
│                                  │ ssh -R 9222:127.0.0.1:9222           │
└──────────────────────────────────┼──────────────────────────────────────┘
                                   │
                                   ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                        Linux ホスト                                      │
│                                                                          │
│  127.0.0.1:9222 ─→ MCP Chrome DevTools ─→ Claude Code                   │
│                                               ↓                          │
│                                      Agent Teams 機能                    │
│                                   (Team Lead, Teammates,                │
│                                    Task List, Mailbox)                  │
└─────────────────────────────────────────────────────────────────────────┘
```

### ワークフロー

1. **プロジェクト選択** - Xドライブのディレクトリから対話的に選択
2. **ポート自動割り当て** - `config.json`の`ports`配列から利用可能なポートを検索
3. **ブラウザ起動** - 専用プロファイル + リモートデバッグモードで起動
4. **run-claude.sh生成** - プロジェクトルートにbashスクリプトを動的生成 (heredoc INIT_PROMPT)
5. **設定自動適用** - Linux側 `~/.claude/settings.json` へjqマージ (base64転送)
6. **SSHリモート実行** - ポートフォワーディング付きSSH接続でClaude Codeを起動

## config.json 設定リファレンス

### 基本設定

| キー | 説明 | デフォルト |
|------|------|-----------|
| `ports` | 使用可能なDevToolsポート配列 | `[9222, 9223, 9224, 9225, 9226, 9227, 9228, 9229]` |
| `zDrive` | Windowsプロジェクトルート | `"X:\\"` |
| `linuxHost` | SSHホスト名 | `"<your-linux-host>"` |
| `linuxBase` | Linuxプロジェクトベースパス | `"/mnt/LinuxHDD"` |
| `defaultBrowser` | デフォルトブラウザ | `"edge"` |
| `autoCleanup` | 自動クリーンアップ | `true` |

### Claude Code設定 (`claudeCode` セクション)

**環境変数 (`env`):**
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`: Agent Teams有効化 (`"1"`)
- `ENABLE_TOOL_SEARCH`: MCP Tool Search有効化 (`"true"`)
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`: 自動コンパクト閾値 (`"50"`)
- `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`: プロンプトサジェスション (`"true"`)

**UI/動作設定 (`settings`):**
- `language`: 表示言語 (`"日本語"`)
- `outputStyle`: 出力スタイル (`"Explanatory"`)
- `alwaysThinkingEnabled`: 思考モード常時有効 (`true`)
- `spinnerTipsEnabled`: スピナーTips表示 (`true`)
- `promptSuggestionEnabled`: プロンプトサジェスション (`true`)
- `respectGitignore`: .gitignore尊重 (`true`)
- `autoUpdatesChannel`: 自動更新チャンネル (`"latest"`)
- `includeCoAuthoredBy`: Co-Authored-By追加 (`true`)

## 主要コンポーネント

### PowerShellスクリプト

- **`Claude-EdgeDevTools.ps1`** - Edge版メインスクリプト
  - DevTools Preferences事前設定 (キャッシュ無効化、ログ保持)
  - base64 SSH転送でグローバル設定を自動適用

- **`Claude-ChromeDevTools-Final.ps1`** - Chrome版メインスクリプト
  - Chrome専用最適化
  - Edge版と同等の機能

### 動的生成ファイル

- **`run-claude.sh`** - Claude Code起動スクリプト
  - heredoc形式のINIT_PROMPT定義
  - Agent Teams環境変数 (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
  - DevTools接続確認 (最大10回リトライ)
  - 自動再起動ループ

- **`~/.claude/settings.json`** - グローバル設定
  - jqマージパターンで既存設定を保持しつつ更新
  - `. + {...} | .env = ((.env // {}) + {...})` パターン使用

## 重要な技術仕様

### SSH経由のスクリプト転送 (base64方式)

```powershell
# PowerShell側
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
ssh $LinuxHost "echo '$encoded' | base64 -d > /tmp/script.sh && chmod +x /tmp/script.sh && /tmp/script.sh"
```

- 日本語文字、JSON特殊文字、バッククォートの破損を防止
- CRLF/LF改行コードの問題を回避

### INIT_PROMPT (heredoc方式)

```bash
INIT_PROMPT=$(cat << 'INITPROMPTEOF'
プロンプト内容（バッククォート、二重引用符を含めてもOK）
INITPROMPTEOF
)
```

- シングルクォート付きデリミタにより変数展開・コマンド置換を完全に無効化
- bash double-quoted stringは使用禁止（重大バグのため）

### グローバル設定の自動適用 (jqマージ)

```bash
jq '. + {
  "language": "日本語",
  "outputStyle": "Explanatory",
  ...
} | .env = ((.env // {}) + {
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
  ...
})' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
```

- 既存のpermissions, plugins, hooksを保持
- statusLine以外の全設定も包括的に適用

## ドキュメント

### システム管理者向け

- [01_プロジェクト概要](docs/SystemAdministrator/01_プロジェクト概要(Project-Overview).txt)
- [02_セットアップガイド](docs/SystemAdministrator/02_セットアップガイド(Setup-Guide).txt)
- [04_設定ファイル詳細](docs/SystemAdministrator/04_設定ファイル詳細(Configuration-Details).txt)
- [07_アーキテクチャ](docs/SystemAdministrator/07_アーキテクチャ(Architecture).txt)
- [12_環境変数](docs/SystemAdministrator/12_環境変数(Environment-Variables).txt)
- その他7ファイル

### 一般ユーザー向け

- [01_はじめに](docs/non-SystemAdministrator/01_はじめに(Getting-Started).txt)
- [02_インストール方法](docs/non-SystemAdministrator/02_インストール方法(Installation).txt)
- [03_基本的な使い方](docs/non-SystemAdministrator/03_基本的な使い方(Basic-Usage).txt)
- [06_用語集](docs/non-SystemAdministrator/06_用語集(Glossary).txt)
- その他2ファイル

## トラブルシューティング

### DevTools接続失敗

1. すべてのブラウザウィンドウを閉じる
2. 接続テスト実行: `start.bat` → `[3]` または `[4]`
3. エンドポイント確認: `http://localhost:9222/json/version`

### Statusline未反映

1. Claude Code内で `/statusline` コマンド実行
2. または Claude Code を再起動

### SSH接続エラー

1. `~/.ssh/config` でホスト設定を確認
2. SSHキーベース認証が正しく設定されているか確認
3. `ssh -vvv <linux-host>` で詳細ログを確認

詳細は [05_トラブルシューティング](docs/SystemAdministrator/05_トラブルシューティング(Troubleshooting).txt) を参照してください。

## 変更履歴

### v1.1.0 (2026-02-06)

**新機能:**
- ✨ Agent Teams機能の統合
- ✨ Claude Code設定の中央管理 (`claudeCode`セクション)
- ✨ グローバル設定の包括的自動適用

**改善:**
- 🔧 INIT_PROMPT heredoc方式への移行
- 🔧 base64 SSH転送の統一
- 🔧 新環境変数の追加 (`ENABLE_TOOL_SEARCH`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`)

**バグ修正:**
- 🐛 INIT_PROMPT bash引用符バグの修正 (重大)
- 🐛 Edge版SSH実行方法の不整合修正

完全な変更履歴は [09_変更履歴](docs/SystemAdministrator/09_変更履歴(Changelog).txt) を参照してください。

## ライセンス

MIT License - 詳細は [10_ライセンス](docs/SystemAdministrator/10_ライセンス(License).txt) を参照してください。

## サポート

- **FAQ**: [一般ユーザー向けFAQ](docs/non-SystemAdministrator/04_よくある質問(FAQ).txt) | [システム管理者向けFAQ](docs/SystemAdministrator/08_FAQ.txt)
- **トラブルシューティング**: [一般向け](docs/non-SystemAdministrator/05_困ったときは(Troubleshooting).txt) | [管理者向け](docs/SystemAdministrator/05_トラブルシューティング(Troubleshooting).txt)
- **詳細ドキュメント**: [CLAUDE.md](CLAUDE.md) (Claude Code向けプロジェクト指示書) | [GEMINI.md](GEMINI.md) (プロジェクト詳細)

## プロジェクト構造

```
Claude-EdgeChromeDevTools/
├── config/
│   └── config.json                      # 中央集約設定
├── scripts/
│   ├── main/                            # メインスクリプト
│   ├── setup/                           # セットアップスクリプト
│   ├── test/                            # テストスクリプト
│   └── statusline.sh                    # Statusline表示スクリプト
├── docs/
│   ├── SystemAdministrator/             # システム管理者向けドキュメント (12ファイル)
│   └── non-SystemAdministrator/         # 一般ユーザー向けドキュメント (6ファイル)
├── start.bat                            # 対話型ランチャー
├── CLAUDE.md                            # Claude Code向けプロジェクト指示書
├── GEMINI.md                            # プロジェクトドキュメント (日本語)
└── README.md                            # このファイル
```

## 貢献

Pull RequestやIssue報告を歓迎します。詳細は [06_開発ガイド](docs/SystemAdministrator/06_開発ガイド(Development-Guide).txt) を参照してください。

---

**注意**: このスクリプトは `--dangerously-skip-permissions` フラグを使用します。開発環境専用です。
