# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

このリポジトリは、WindowsマシンとリモートLinuxホスト間でClaude Codeとブラウザ開発者ツール(DevTools)を統合するためのセットアップ自動化スクリプト群です。SSH経由でのリモートポートフォワーディングを使用し、Windows上のEdge/ChromeブラウザとLinux上のClaude Codeを連携させます。

## 開発環境構成

### ネットワーク構成
- **Windowsマシン**: Edge/Chromeブラウザ + DevToolsポート (9222-9229)
- **Linuxホスト** (`<your-linux-host>`): Claude Code実行環境 ※ config.json の `linuxHost` 設定値 (例: `kensan1969`, `192.168.0.185`)
- **接続方式**: SSHリモートポートフォワーディング (`-R ${PORT}:127.0.0.1:${PORT}`)
- **プロジェクトマウント**: Xドライブ (`X:\`) ⟺ Linux (`/mnt/LinuxHDD`)

### 環境変数
Claude Code実行時に以下の環境変数が設定されます:
- `CLAUDE_CHROME_DEBUG_PORT`: DevToolsポート番号
- `MCP_CHROME_DEBUG_PORT`: MCPサーバー用DevToolsポート番号
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`: Agent Teams機能有効化 (`1`)
- `ENABLE_TOOL_SEARCH`: MCP Tool Search有効化 (`true`)
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`: 自動コンパクト閾値 (`50`)
- `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`: プロンプトサジェスション有効化 (`true`)

## コマンド

### メインスクリプト起動
```cmd
start.bat
```
対話型メニューからスクリプトを選択して実行。Windows Terminal推奨。

### 直接スクリプト実行
```powershell
# Edge版 (デフォルトブラウザ: Edge)
.\Claude-EdgeDevTools.ps1

# Chrome版 (デフォルトブラウザ: Chrome)
.\Claude-ChromeDevTools-Final.ps1
```

### テストスクリプト
```powershell
# Edge DevTools接続テスト (Windows側)
.\test-edge.ps1

# Chrome DevTools接続テスト (Windows側)
.\test-chrome.ps1
```

```bash
# DevTools接続テスト (Linux側、Xサーバ不要)
./scripts/test/test-devtools-connection.sh [ポート番号]
# 例: ./scripts/test/test-devtools-connection.sh 9222
# ポート番号省略時は環境変数 MCP_CHROME_DEBUG_PORT または CLAUDE_CHROME_DEBUG_PORT を使用（デフォルト: 9222）
```

### Windows Terminal設定
```powershell
# 自動設定スクリプト (Claude DevToolsプロファイル作成)
.\setup-windows-terminal.ps1
```

## アーキテクチャ

### ワークフロー
1. **プロジェクト選択**: Xドライブのディレクトリから対話的に選択
2. **ポート自動割り当て**: `config.json`の`ports`配列から利用可能なポートを検索
3. **ブラウザ起動**: 専用プロファイル + リモートデバッグモードでEdge/Chromeを起動
4. **run-claude.sh生成**: 選択されたプロジェクトルートにbashスクリプトを動的生成
5. **SSHリモート実行**: ポートフォワーディング付きSSH接続でLinux上のClaude Codeを起動

### 主要コンポーネント

#### Claude-EdgeDevTools.ps1 / Claude-ChromeDevTools-Final.ps1
- ブラウザプロファイル管理 (`C:\DevTools-{edge|chrome}-{PORT}`)
- DevTools Preferences事前設定 (Edge版のみ: キャッシュ無効化、ログ保持など)
- ポート衝突検出とプロセスクリーンアップ
- Statusline設定の自動展開 (`.claude/statusline.sh` + `settings.json`)
- **Claude Code グローバル設定の自動適用** (base64エンコーディング経由SSH転送)
- **Agent Teams環境変数の自動設定**
- `.mcp.json`の自動バックアップ

#### run-claude.sh (動的生成)
- DevTools接続確認 (最大10回リトライ)
- 環境変数設定 (`CLAUDE_CHROME_DEBUG_PORT`, `MCP_CHROME_DEBUG_PORT`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`)
- **詳細DevTools接続テスト** (バージョン情報、タブ一覧、WebSocketエンドポイント、Protocol version確認)
- 初期プロンプト自動入力 (heredoc方式: `INIT_PROMPT=$(cat << 'INITPROMPTEOF' ... INITPROMPTEOF)`)
  - **ブラウザ自動化ツール使い分けガイド** (ChromeDevTools MCP vs Playwright)を含む
- Claude Code自動再起動ループ

#### config.json
中央集約設定ファイル:
- `ports`: 使用可能なDevToolsポート配列（推奨範囲: 9222-9229）
- `zDrive`: Windowsプロジェクトルート
- `linuxHost`: SSHホスト名
- `linuxBase`: Linuxプロジェクトベースパス
- `edgeExe` / `chromeExe`: ブラウザ実行ファイルパス
- `defaultBrowser`: デフォルトブラウザ (`edge` / `chrome`)
- `autoCleanup`: 自動クリーンアップ有効化
- `statusline`: Statusline機能設定 (表示項目の個別ON/OFF)
- `claudeCode`: Claude Code設定の中央管理 (以下を含む)
  - `env`: 環境変数 (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, `ENABLE_TOOL_SEARCH`等)
  - `settings`: UI/動作設定 (`language`, `outputStyle`, `alwaysThinkingEnabled`等)

#### statusline.sh
Claude Code Statusline表示スクリプト。以下を表示:
- 📁 カレントディレクトリ
- 🌿 Gitブランチ
- 🤖 モデル名
- 📟 Claudeバージョン
- 🎨 出力スタイル
- 🧠 コンテキスト使用率 (プログレスバー付き)

**依存**: `jq` (自動インストール試行)

## 重要な規約

### SSH経由のスクリプト転送 (base64方式)
- グローバル設定スクリプト、statusline.sh、settings.json等はbase64エンコーディングでSSH転送
- PowerShell側: `[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))`
- Linux側: `echo '$encoded' | base64 -d > /tmp/script.sh && chmod +x /tmp/script.sh && /tmp/script.sh`
- 日本語文字、JSON特殊文字、バッククォート等の破損を防止

### INIT_PROMPT (heredoc方式)
- bash double-quoted stringではなく、heredocを使用
- `INIT_PROMPT=$(cat << 'INITPROMPTEOF' ... INITPROMPTEOF)` 形式
- シングルクォート付きデリミタにより変数展開・コマンド置換を完全に無効化

### Claude Code グローバル設定の自動適用
- スクリプト実行時にLinux側 `~/.claude/settings.json` を自動更新
- jqマージパターン: `. + {...} | .env = ((.env // {}) + {...})`
- 既存のpermissions, plugins, hooksを保持しつつ設定を追加/上書き

### ブラウザプロファイル隔離
- 各DevToolsポートごとに専用プロファイルディレクトリを作成
- 同一ポートの既存プロセスを自動終了してから起動
- プロファイルパス: `C:\DevTools-{browser}-{port}`

### ファイルエンコーディング
- `.sh`ファイル: UTF-8 (BOM無し) + LF改行
- `config.json`: UTF-8 (BOM無し)
- PowerShellスクリプト内で明示的に変換処理を実行

### SSH接続オプション
```powershell
ssh -tt -o ControlMaster=no -o ControlPath=none -R "${PORT}:127.0.0.1:${PORT}" $LinuxHost
```
- `-tt`: pseudo-tty強制割り当て (対話的セッション用)
- `ControlMaster=no`: 接続多重化無効
- `-R`: リモートポートフォワーディング

### エラーハンドリング
- `$ErrorActionPreference = "Stop"`: 即座に終了
- DevTools接続確認: 15秒タイムアウト + HTTPレスポンステスト
- Linuxポートクリーンアップ: `fuser -k ${PORT}/tcp`

## トラブルシューティング

### DevTools接続失敗時
1. すべてのブラウザウィンドウを閉じる
2. 手動起動コマンドで検証:
   ```powershell
   "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --remote-debugging-port=9222 --user-data-dir="C:\DevTools-edge-9222" http://localhost:9222
   ```
3. エンドポイント確認:
   ```
   http://localhost:9222/json/version
   ```

### Statusline未反映時
- Claude Code内で `/statusline` コマンド実行
- または Claude Code を再起動

### SSH接続エラー
- `windows-dev` ホストへのSSHキーベース認証を確認
- `~/.ssh/config` でホスト設定を確認

## ファイル構造

```
Claude-EdgeChromeDevTools/
├── config/
│   └── config.json                  # 中央集約設定 (claudeCodeセクション含む)
├── scripts/
│   ├── main/
│   │   ├── Claude-EdgeDevTools.ps1          # Edge版メインスクリプト
│   │   └── Claude-ChromeDevTools-Final.ps1  # Chrome版メインスクリプト
│   ├── setup/
│   │   ├── setup-windows-terminal.ps1       # Windows Terminal自動設定
│   │   └── setup-windows-terminal.bat       # Windows Terminal設定ガイド
│   ├── test/
│   │   ├── test-edge.ps1                    # Edge接続テスト (Windows側)
│   │   ├── test-chrome.ps1                  # Chrome接続テスト (Windows側)
│   │   └── test-devtools-connection.sh      # DevTools接続テスト (Linux側、Xサーバ不要)
│   └── statusline.sh                        # Claude Code Statuslineスクリプト
├── docs/
│   ├── SystemAdministrator/         # システム管理者向けドキュメント (12ファイル)
│   └── non-SystemAdministrator/     # 一般ユーザー向けドキュメント (6ファイル)
├── start.bat                        # 対話型ランチャー
├── CLAUDE.md                        # Claude Code向けプロジェクト指示書
└── GEMINI.md                        # プロジェクトドキュメント(日本語)
```

### 動的生成ファイル
- `{プロジェクトルート}/run-claude.sh`: Claude Code起動スクリプト (heredoc INIT_PROMPT + Agent Teams env)
- `{プロジェクトルート}/.claude/statusline.sh`: プロジェクト固有Statusline (base64転送)
- `{プロジェクトルート}/.claude/settings.json`: Claude Code設定 (base64転送)
- `{プロジェクトルート}/.mcp.json.bak.*`: MCPバックアップ
- `~/.claude/settings.json` (Linux): グローバル設定 (jqマージ自動更新)

## 依存関係

### Windows側
- PowerShell 5.1以降
- Microsoft Edge または Google Chrome
- SSH クライアント (OpenSSH)
- Windows Terminal (推奨)

### Linux側
- `claude` CLI
- `curl`
- `jq` (Statusline用 + グローバル設定マージ用、自動インストール試行)
- `fuser` (ポートクリーンアップ用)
- `git` (Statusline Gitブランチ表示用)
- `base64` (SSH経由スクリプト転送用、通常プリインストール済み)

## ブラウザ自動化ツール使い分けガイド

このプロジェクトでは、Claude Code実行時にブラウザ自動化に関する2つのMCPツールが利用可能です：

### Puppeteer MCP

**用途**: Windows側のブラウザインスタンスに接続してデバッグ・検証

**特徴**:
- Windows側で起動済みのEdge/Chromeブラウザに接続（SSHポートフォワーディング経由）
- DevTools Protocol経由のリアルタイムアクセス
- 既存のユーザーセッション・Cookie・ログイン状態を利用可能
- 手動操作との併用が容易
- Node.js Puppeteer APIの全機能利用可能（待機、リトライ、複雑な操作シーケンス）

**適用シーン**:
- ログイン済みのWebアプリをデバッグ
- ブラウザコンソールのエラーログをリアルタイム監視
- ネットワークトラフィック（XHR/Fetch）の詳細解析
- DOM要素の動的変更を追跡・検証
- パフォーマンス計測（Navigation Timing、Resource Timing等）
- 複雑な操作フロー（ドラッグ&ドロップ、複数タブ操作等）

**接続テスト**:
```bash
# 環境変数確認
echo $MCP_CHROME_DEBUG_PORT

# バージョン情報取得
curl -s http://127.0.0.1:${MCP_CHROME_DEBUG_PORT}/json/version | jq '.'

# タブ一覧取得
curl -s http://127.0.0.1:${MCP_CHROME_DEBUG_PORT}/json/list | jq '.'
```

**主要MCPツール**:
- `mcp__plugin_puppeteer_puppeteer__navigate`: ページ遷移
- `mcp__plugin_puppeteer_puppeteer__click`: 要素クリック
- `mcp__plugin_puppeteer_puppeteer__evaluate`: JavaScriptコード実行
- `mcp__plugin_puppeteer_puppeteer__screenshot`: スクリーンショット取得
- （その他、`ToolSearch "puppeteer"` で検索）

### Playwright MCP

**用途**: 自動テスト・スクレイピング・クリーンな環境での検証

**特徴**:
- ヘッドレスブラウザを新規起動（Linux側で完結、Xサーバ不要）
- 完全に独立した環境（クリーンなプロファイル、Cookie無し）
- クロスブラウザ対応（Chromium/Firefox/WebKit）
- 自動待機・リトライ・タイムアウト処理が組み込み済み

**適用シーン**:
- E2Eテストの自動実行（CI/CDパイプライン組み込み）
- スクレイピング・データ収集（ログイン不要の公開ページ）
- 複数ブラウザでの互換性テスト
- 並列実行が必要な大規模テスト
- ログイン認証を含む自動テストフロー（認証情報をコードで管理）

**主要MCPツール**:
- `mcp__plugin_playwright_playwright__browser_navigate`: ページ遷移
- `mcp__plugin_playwright_playwright__browser_click`: 要素クリック
- `mcp__plugin_playwright_playwright__browser_run_code`: JavaScriptコード実行
- `mcp__plugin_playwright_playwright__browser_take_screenshot`: スクリーンショット取得

### 使い分けの判断基準

| 状況 | 推奨ツール |
|------|----------|
| 既存ブラウザの状態（ログイン・Cookie等）を利用 | Puppeteer MCP |
| クリーンな環境でのテスト | Playwright MCP |
| 手動操作との併用が必要 | Puppeteer MCP |
| 自動テスト・CI/CD統合 | Playwright MCP |
| クロスブラウザ検証 | Playwright MCP |
| リアルタイムデバッグ | Puppeteer MCP |

### 重要な注意点

- **Xサーバ不要**: LinuxホストにXサーバがインストールされていなくても、両ツールともヘッドレスモードで動作
- **ポート範囲**: Puppeteer MCPは9222～9229の範囲で動作（config.jsonで設定）
- **並行利用**: 両ツールは同時に使用可能（異なるユースケースで併用可）
- **ツール検索**: `ToolSearch "puppeteer"` または `ToolSearch "playwright"` で利用可能なツールを検索

### 推奨ワークフロー

1. **開発・デバッグフェーズ**: Puppeteer MCPで手動操作と併用しながら検証
2. **テスト自動化フェーズ**: Playwrightで自動テストスクリプト作成
3. **CI/CD統合フェーズ**: PlaywrightテストをGitHub Actionsに組み込み

## 注意事項

- このスクリプトは `--dangerously-skip-permissions` フラグを使用します
- プロジェクトは必ずXドライブにマウントされている必要があります
- Linux側パスは `/mnt/LinuxHDD/{プロジェクト名}` に固定されています
- ポート範囲はデフォルトで 9222-9229（config.jsonで設定可能）
