# ChromeDevTools MCP vs Playwright MCP 完全ガイド

## よくある誤解を解消

### ❌ 誤解: 「X サーバがないから Playwright を使う」

**これは誤りです。**

どちらのツールも **X サーバは不要**です。選択基準は X サーバの有無ではありません。

---

## 正しい理解

### ChromeDevTools MCP の仕組み

```
[Windows マシン]                    [Linux ホスト]
   │                                    │
   ├─ Edge/Chrome (ヘッドフル)          │
   │  └─ DevTools Protocol              │
   │     └─ localhost:9222 ←─────SSH───┤
   │                        ポート      │
   │                        フォワー    │
   │                        ディング    │
   │                                    ├─ Claude Code
   │                                    │  └─ ChromeDevTools MCP
   │                                    │     └─ 127.0.0.1:9222 に接続
```

**重要ポイント**:
- ブラウザは **Windows 側**で動作（ヘッドフル、GUI あり）
- Linux 側からは **SSH ポートフォワーディング**経由で接続
- **Linux 側に X サーバは一切不要**（ブラウザが Windows で動いているため）
- ブラウザの GUI は Windows で表示される

---

### Playwright MCP の仕組み

```
[Windows マシン]                    [Linux ホスト]
   │                                    │
   │                                    ├─ Claude Code
   │                                    │  └─ Playwright MCP
   │                                    │     └─ Chromium (ヘッドレス)
   │                                    │        └─ Linux プロセスとして起動
```

**重要ポイント**:
- ブラウザは **Linux 側**で動作（ヘッドレス、GUI なし）
- Windows 側とは無関係
- **Linux 側に X サーバ不要**（ヘッドレスモードのため）
- GUI は存在しない（スクリーンショットは仮想フレームバッファ）

---

## 選択基準（正しい判断フロー）

### ユーザーが「ブラウザで〜してください」と依頼した場合

#### ステップ1: 既存のブラウザ状態を使うか？

**YES（ログイン済み、Cookie保持、手動操作との併用）**
→ **ChromeDevTools MCP を使用**

例:
- 「ログイン済みの管理画面でユーザー一覧を取得してください」
- 「このページのネットワークトラフィックを監視してください」
- 「コンソールエラーをリアルタイムで確認してください」

**NO（クリーンな環境、自動テスト、スクレイピング）**
→ **Playwright MCP を使用**

例:
- 「example.com のタイトルをスクレイピングしてください」
- 「ログインフォームの E2E テストを作成してください」
- 「このページを Chrome/Firefox/WebKit で互換性テストしてください」

---

#### ステップ2: ChromeDevTools MCP が利用可能か確認

```bash
# 環境変数確認
echo $MCP_CHROME_DEBUG_PORT
# → 9222-9229 のいずれかが表示されるべき

# DevTools 接続確認
curl -s http://127.0.0.1:${MCP_CHROME_DEBUG_PORT}/json/version
# → JSON が返るべき

# ツール確認
ToolSearch "chrome-devtools"
# → mcp__chrome-devtools__* ツールが表示されるべき
```

**すべて OK** → **ChromeDevTools MCP 使用**
**いずれか NG** → **原因調査**（下記トラブルシューティング参照）

---

## トラブルシューティング

### 問題: 「ChromeDevTools を使ってください」と指示したのに Playwright が使われた

#### 診断ステップ

**1. MCP サーバーの起動確認**
```bash
# on-startup.sh の出力を確認
# 📋 MCP サーバー:
#   ✅ ChromeDevTools  ← これが表示されるべき
```

表示されない場合:
```bash
# .mcp.json を確認
jq '.mcpServers.ChromeDevTools' .mcp.json

# 存在しない場合は MCP セットアップ実行
bash scripts/mcp/setup-mcp.sh "$(pwd)"
```

---

**2. 環境変数の確認**
```bash
echo "CLAUDE_CHROME_DEBUG_PORT: $CLAUDE_CHROME_DEBUG_PORT"
echo "MCP_CHROME_DEBUG_PORT: $MCP_CHROME_DEBUG_PORT"
```

未設定の場合:
```bash
# run-claude.sh の export 文を確認
grep "export.*CHROME_DEBUG_PORT" run-claude.sh

# 存在しない場合は run-claude.sh を再生成
# → start.bat から再実行
```

---

**3. DevTools 接続の確認**
```bash
# Windows 側でブラウザが起動しているか
# PowerShell で確認:
Get-Process msedge,chrome -ErrorAction SilentlyContinue |
    Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine -match "remote-debugging-port" }

# Linux 側から接続テスト
curl -v http://127.0.0.1:9222/json/version
```

接続できない場合:
- SSH ポートフォワーディングが失敗している可能性
- `ssh -vvv` で詳細ログ確認
- Windows ファイアウォール設定確認

---

**4. Claude への明示的指示**

曖昧な指示:
```
「このページを開いてください」
→ Claude が Playwright を選ぶ可能性あり
```

明示的な指示（推奨）:
```
「Windows側のChromeブラウザ（ChromeDevTools MCP）でこのページを開いてください」

または

「mcp__chrome-devtools__navigate_page ツールを使ってこのページを開いてください」
```

---

## INIT_PROMPT の改善提案

### 現在の問題点

Line 677 の記述:
```
1. **Xサーバ不要**：LinuxホストにXサーバがインストールされていなくても、
   両ツールともヘッドレスモードで動作します
```

**誤解を招く点**:
- ChromeDevTools は「ヘッドレスモード」では動作しない
- X サーバの有無は選択基準ではない

### 推奨される記述（修正済み）

```
1. **Xサーバ不要（重要）**：LinuxホストにXサーバがインストールされていなくても、両ツールとも動作します
   - **ChromeDevTools MCP**: Windows側のブラウザに接続するため、Linux側にXサーバ不要（SSHポートフォワーディング経由）
   - **Playwright MCP**: Linux側でヘッドレスブラウザを起動するため、Xサーバ不要
   - ⚠️ **選択基準はXサーバの有無ではありません**。既存ブラウザ（ログイン状態等）を使うか、クリーンな環境かで判断してください
```

### 追加: ChromeDevTools 優先原則（新規追加）

```
5. **ChromeDevTools 優先原則**：ユーザーがブラウザ操作を依頼した場合、
   **既存のWindows側ブラウザ（ChromeDevTools MCP）を優先使用**してください。
   Playwrightは自動テスト・スクレイピング・クリーンな環境が必要な場合のみ使用
```

---

## 実用的なガイドライン（Claude 向け）

### ✅ ChromeDevTools MCP を使うべき状況

- ユーザーが「このページを開いて」「要素をクリックして」等の**対話的な操作**を依頼
- ログイン済みの状態を利用したい
- 手動操作（ユーザーが Windows 側でクリック）との併用
- リアルタイムのコンソールログ・ネットワーク監視
- DevTools の Sources/Network/Console タブの機能を使いたい

### ✅ Playwright MCP を使うべき状況

- 「E2Eテストを作成して」等の**自動テスト**を依頼
- 「このサイトをスクレイピングして」等の**データ収集**
- クリーンな環境（Cookie なし、ログインなし）での検証
- CI/CD パイプラインでの実行
- クロスブラウザ（Chrome/Firefox/WebKit）テスト

---

## 検証: ChromeDevTools MCP が正しく動作しているか

### クイックテスト

Claude Code 内で以下を実行：

```bash
# 1. 環境変数確認
echo $MCP_CHROME_DEBUG_PORT

# 2. DevTools 接続確認
curl http://127.0.0.1:${MCP_CHROME_DEBUG_PORT}/json/version | jq '.Browser'

# 3. ツール検索
ToolSearch "chrome-devtools navigate"

# 4. 実際に使用
mcp__chrome-devtools__navigate_page --url "https://example.com"

# 5. スクリーンショット取得
mcp__chrome-devtools__take_screenshot --path "/tmp/test.png"
```

**すべて成功する場合**: ChromeDevTools MCP は **100% 動作** ✅

**いずれか失敗する場合**: 上記トラブルシューティング参照

---

## まとめ

### 質問への回答

> ChromeDevTools利用を依頼した際にXサーバ利用不可ということで代替としてplaywright利用となってしまったことがある。そこは問題ない？

**回答**: **問題あります。誤った判断です。**

**正しい動作**:
1. ChromeDevTools MCP は X サーバ不要（Windows ブラウザに接続）
2. ユーザーが ChromeDevTools 使用を依頼した場合、X サーバの有無に関わらず ChromeDevTools を使用すべき
3. Playwright への切り替えは、X サーバではなく**ユースケース**（自動テスト vs 対話的デバッグ）で判断

**対策**:
- ✅ INIT_PROMPT を修正済み（注意事項セクション + 優先原則追加）
- ✅ 次回 start.bat 実行時に新しい INIT_PROMPT が適用される
- ✅ Claude が正しい判断をするようになります

---

**現在の状態**: ChromeDevTools MCP は **100% 利用可能** です。X サーバは全く関係ありません。
