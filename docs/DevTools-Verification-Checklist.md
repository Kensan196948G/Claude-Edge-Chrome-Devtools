# Chrome/Edge DevTools 機能検証チェックリスト

## 検証日: 2026-02-15
## 対象バージョン: v1.2.0

---

## 1. 基本機能検証

### 1.1 ブラウザ起動

| # | 検証項目 | Edge | Chrome | 検証方法 |
|---|---------|------|--------|---------|
| 1.1.1 | リモートデバッグモードで起動 | ☐ | ☐ | `--remote-debugging-port={PORT}` が有効 |
| 1.1.2 | 専用プロファイル作成 | ☐ | ☐ | `C:\DevTools-{browser}-{port}` ディレクトリ存在 |
| 1.1.3 | localhost URL 自動表示 | ☐ | ☐ | `http://localhost:{PORT}` がブラウザで開く |
| 1.1.4 | 複数ポート同時起動 | ☐ | ☐ | 9222と9223で2つ起動可能 |

**検証コマンド**:
```powershell
# Edge テスト
.\scripts\test\test-edge.ps1

# Chrome テスト
.\scripts\test\test-chrome.ps1
```

---

### 1.2 DevTools Protocol 接続

| # | 検証項目 | Edge | Chrome | 検証方法 |
|---|---------|------|--------|---------|
| 1.2.1 | `/json/version` エンドポイント | ☐ | ☐ | `curl http://localhost:{PORT}/json/version` |
| 1.2.2 | `/json/list` タブ一覧取得 | ☐ | ☐ | `curl http://localhost:{PORT}/json/list` |
| 1.2.3 | WebSocket エンドポイント取得 | ☐ | ☐ | `webSocketDebuggerUrl` フィールド存在 |
| 1.2.4 | Protocol Version 1.3 対応 | ☐ | ☐ | `Protocol-Version: "1.3"` |

**検証コマンド**:
```bash
# Linux 側で実行
PORT=9222
curl -s http://127.0.0.1:${PORT}/json/version | jq '.'
curl -s http://127.0.0.1:${PORT}/json/list | jq 'length'
```

---

### 1.3 SSH ポートフォワーディング

| # | 検証項目 | 検証結果 | 検証方法 |
|---|---------|---------|---------|
| 1.3.1 | リモートポートフォワーディング成立 | ☐ | `ssh -R 9222:127.0.0.1:9222` が成功 |
| 1.3.2 | Linux側から localhost:9222 にアクセス可能 | ☐ | `curl http://127.0.0.1:9222/json/version` |
| 1.3.3 | ポートクリーンアップ動作 | ☐ | `fuser -k 9222/tcp` が実行される |

**検証コマンド**:
```bash
# Linux 側で実行
netstat -tln | grep 9222
# LISTEN 状態であること

curl -s http://127.0.0.1:9222/json/version
# JSON が返ること
```

---

## 2. MCP ChromeDevTools 機能検証

### 2.1 MCP サーバー起動

| # | 検証項目 | 検証結果 | 検証方法 |
|---|---------|---------|---------|
| 2.1.1 | ChromeDevTools MCP が `.mcp.json` に設定 | ☐ | `jq '.mcpServers.ChromeDevTools' .mcp.json` |
| 2.1.2 | MCP サーバープロセスが起動 | ☐ | Claude Code内で `ToolSearch "chrome-devtools"` |
| 2.1.3 | 環境変数 `MCP_CHROME_DEBUG_PORT` 設定 | ☐ | `echo $MCP_CHROME_DEBUG_PORT` |

**検証コマンド**:
```bash
# Claude Code 起動後に実行
ToolSearch "chrome-devtools"
# mcp__chrome-devtools__* ツールが表示されること
```

---

### 2.2 MCP ChromeDevTools ツール

以下のツールが利用可能か検証：

| # | ツール名 | 機能 | 検証結果 | テストケース |
|---|---------|------|---------|-------------|
| 2.2.1 | `navigate_page` | ページ遷移 | ☐ | `mcp__chrome-devtools__navigate_page --url "https://example.com"` |
| 2.2.2 | `click` | 要素クリック | ☐ | セレクタ指定でクリック |
| 2.2.3 | `fill` | フォーム入力 | ☐ | input要素に値入力 |
| 2.2.4 | `evaluate_script` | JavaScript実行 | ☐ | `document.title` 取得 |
| 2.2.5 | `take_screenshot` | スクリーンショット | ☐ | PNG画像取得 |
| 2.2.6 | `get_console_messages` | コンソールログ取得 | ☐ | console.log 出力取得 |
| 2.2.7 | `list_network_requests` | ネットワークリクエスト一覧 | ☐ | XHR/Fetch リクエスト取得 |
| 2.2.8 | `get_cookies` | Cookie取得 | ☐ | ドメイン指定でCookie一覧 |
| 2.2.9 | `set_cookie` | Cookie設定 | ☐ | name/value/domain指定 |
| 2.2.10 | `clear_cache` | キャッシュクリア | ☐ | ブラウザキャッシュ削除 |

**包括的テストスクリプト**:
```javascript
// Claude Code 内で実行
// 1. ページ遷移
mcp__chrome-devtools__navigate_page --url "https://example.com"

// 2. JavaScript 実行
mcp__chrome-devtools__evaluate_script --script "document.title"

// 3. スクリーンショット
mcp__chrome-devtools__take_screenshot --path "/tmp/screenshot.png"

// 4. コンソールログ
mcp__chrome-devtools__evaluate_script --script "console.log('Test from Claude'); 'OK'"
mcp__chrome-devtools__get_console_messages

// 5. ネットワークリクエスト
mcp__chrome-devtools__list_network_requests

// 6. Cookie 操作
mcp__chrome-devtools__get_cookies --domain "example.com"
mcp__chrome-devtools__set_cookie --name "test" --value "claude" --domain "example.com"
```

---

## 3. 自動化機能検証

### 3.1 Hooks

| # | Hook | 検証結果 | テスト方法 |
|---|------|---------|-----------|
| 3.1.1 | on-startup.sh 自動実行 | ☐ | Claude起動時にヘルスチェック表示 |
| 3.1.2 | pre-commit.sh 機密情報検出 | ☐ | Token含むファイルをコミット→中断されること |
| 3.1.3 | context-loader.sh コンテキスト復元 | ☐ | 2回目起動時に前回タスクが表示 |

**テストケース**:
```bash
# pre-commit テスト
cd /mnt/LinuxHDD/your-project
echo "ghp_test123456789012345678901234567890" > test.txt
git add test.txt
git commit -m "test"
# → ❌ 機密情報が検出されました、と表示されるべき
```

---

### 3.2 MCP 自動セットアップ

| # | MCP Server | 検証結果 | 自動追加 | 手動確認 |
|---|-----------|---------|---------|---------|
| 3.2.1 | brave-search | ☐ | ☐ | `jq '.mcpServers."brave-search"' .mcp.json` |
| 3.2.2 | ChromeDevTools | ☐ | ☐ | 同上 |
| 3.2.3 | context7 | ☐ | ☐ | 同上 |
| 3.2.4 | github | ☐ | ☐ | 同上 |
| 3.2.5 | memory | ☐ | ☐ | 同上 |
| 3.2.6 | playwright | ☐ | ☐ | 同上 |
| 3.2.7 | sequential-thinking | ☐ | ☐ | 同上 |
| 3.2.8 | plugin:claude-mem:mem-search | ☐ | ☐ | 同上 |

**検証コマンド**:
```bash
# すべての MCP サーバーを確認
bash scripts/health-check/mcp-health.sh
```

---

### 3.3 Agent Teams

| # | テンプレート | 検証結果 | テスト方法 |
|---|-------------|---------|-----------|
| 3.3.1 | review-team.json 存在 | ☐ | `.claude/teams/review-team.json` ファイル確認 |
| 3.3.2 | 3名のレビュアー並列起動 | ☐ | Claude内で TeamCreate 実行 |
| 3.3.3 | Memory MCP でナレッジ共有 | ☐ | チームメイト間でメッセージ送受信 |

**テストケース**:
```
// Claude Code 内で実行
「このプロジェクトをセキュリティ・パフォーマンス・テスト観点でレビューしてください」

// 期待される動作:
// 1. Claude が review-team.json を読み込み
// 2. TeamCreate で "review-team" を作成
// 3. 3名のレビュアーを並列起動
// 4. 各レビュアーが独立して分析
// 5. 統合レポートが返される
```

---

## 4. エラーハンドリング検証

### 4.1 異常系テスト

| # | 異常ケース | 期待される動作 | 検証結果 |
|---|-----------|---------------|---------|
| 4.1.1 | X:\ ドライブ未接続 | UNC パスフォールバック成功 | ☐ |
| 4.1.2 | SSH接続失敗 | 詳細エラーメッセージ + 対処法表示 | ☐ |
| 4.1.3 | ポート競合 | 次の空きポート自動選択 | ☐ |
| 4.1.4 | DevTools 応答なし | 15秒リトライ後エラー | ☐ |
| 4.1.5 | MCP接続失敗 | 警告表示だが継続 | ☐ |

**テスト方法**:
```powershell
# 4.1.1: X:\ を手動でアンマウント → スクリプト実行
Remove-PSDrive -Name X -ErrorAction SilentlyContinue

# 4.1.3: ポート9222を手動占有 → スクリプト実行
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 9222)
$listener.Start()
```

---

## 5. パフォーマンス検証

### 5.1 起動時間計測

| # | フェーズ | 目標時間 | 実測時間 | 検証結果 |
|---|---------|---------|---------|---------|
| 5.1.1 | プロジェクト選択 → ブラウザ起動 | < 3秒 | __ 秒 | ☐ |
| 5.1.2 | ブラウザ起動 → DevTools応答 | < 5秒 | __ 秒 | ☐ |
| 5.1.3 | SSH接続確立 | < 3秒 | __ 秒 | ☐ |
| 5.1.4 | run-claude.sh 生成・転送 | < 2秒 | __ 秒 | ☐ |
| 5.1.5 | Claude Code 起動 | < 5秒 | __ 秒 | ☐ |
| 5.1.6 | **合計** | **< 18秒** | **__ 秒** | ☐ |

**計測方法**:
```powershell
Measure-Command { .\scripts\main\Claude-EdgeDevTools.ps1 }
```

---

## 6. セキュリティ検証

### 6.1 機密情報保護

| # | 検証項目 | 検証結果 | 詳細 |
|---|---------|---------|------|
| 6.1.1 | config.json が .gitignore に含まれる | ☐ | Token漏洩防止 |
| 6.1.2 | SSH鍵権限が正しく設定 (600) | ☐ | `icacls ~/.ssh/id_ed25519` |
| 6.1.3 | pre-commit が Token を検出 | ☐ | 上記3.1.2参照 |
| 6.1.4 | Escape-SSHArgument が使用される | ☐ | 全SSH引数がエスケープ済み |

---

## 7. ドキュメント整合性検証

| # | 検証項目 | 検証結果 |
|---|---------|---------|
| 7.1 | Z/X ドライブ矛盾がゼロ | ☐ |
| 7.2 | ホスト名がプレースホルダ化 | ☐ |
| 7.3 | ポート範囲が統一 (9222-9229) | ☐ |

**検証コマンド**:
```bash
# Z:\ 参照の有無
grep -rn "Z:\\\|Z:|Zドライブ" *.md docs/*.md

# <your-linux-host> (windows-dev 等) のハードコードの有無
grep -rn "windows-dev" *.md  # <your-linux-host> 等

# ポート範囲の統一
grep -rn "9222-922[0-5]" *.md  # 旧ポート範囲（9222-9225）検出
```

---

## 8. 統合テスト（エンドツーエンド）

### シナリオ1: 新規プロジェクトでのセットアップ

**手順**:
1. `start.bat` → オプション 2 (Chrome) 選択
2. 新しいプロジェクトを選択
3. Claude Code が起動するまで待機
4. ヘルスチェックが表示されることを確認
5. MCP ツールで DevTools 操作を実行

**期待される動作**:
- ✅ X:\ アクセス成功（UNC フォールバック）
- ✅ SSH接続成功（< 3秒）
- ✅ ブラウザ起動成功
- ✅ MCP 8個自動設定
- ✅ on-startup ヘルスチェック表示
- ✅ Claude Code 正常起動

---

### シナリオ2: Agent Teams によるレビュー

**手順**:
1. Claude Code 起動後、以下を入力:
   ```
   このプロジェクトのPowerShellスクリプトを、セキュリティ・パフォーマンス・テストの観点でレビューしてください
   ```
2. Claude が TeamCreate を実行
3. 3名のレビュアーが並列起動されることを確認
4. 各レビュアーからの報告を確認
5. 統合レポートが作成されることを確認

**期待される動作**:
- ✅ review-team.json が読み込まれる
- ✅ 3名のExploreエージェントが並列起動
- ✅ Memory MCP で発見事項が共有される
- ✅ リードが統合レポートを作成

---

### シナリオ3: Memory MCP コンテキスト復元

**手順**:
1. Claude Code で作業（例: 「README.md を更新してください」）
2. 作業を Memory MCP に保存:
   ```bash
   mcp__memory__save --key "lastTask" --value "README.md 更新完了"
   ```
3. Claude Code を終了
4. 再度同じプロジェクトで起動
5. INIT_PROMPT に前回タスクが表示されることを確認

**期待される動作**:
- ✅ context-loader.sh が実行される
- ✅ `$HOME/.claude/memory/project-context.json` から読み込み
- ✅ 「前回の作業: README.md 更新完了」と表示

---

## 9. 既知の制限事項

### 9.1 環境依存

- ⚠️ Windows 11 / PowerShell 7 必須
- ⚠️ Linux ホストに `jq`, `curl`, `fuser` 必要
- ⚠️ SSH 鍵認証必須（パスワード認証不可）

### 9.2 機能制限

- ⚠️ 同一ポートでの複数セッション不可
- ⚠️ ブラウザはヘッドフル（ヘッドレス未対応）
- ⚠️ Firefox は未対応（Edge/Chrome のみ）

### 9.3 既知のバグ

- 🐛 MCP Playwright セットアップでエラー発生（継続は可能）
- 🐛 環境変数が on-startup.sh 実行時に未設定（次回修正予定）

---

## 検証結果サマリー

**全体の機能カバー率**: ___%

**重大な問題**: __ 件
**軽微な問題**: __ 件
**改善提案**: __ 件

---

## 次のステップ

### 優先度 高
- [ ] MCP Playwright エラーの原因調査
- [ ] 環境変数設定タイミングの修正（on-startup前にexport）
- [ ] すべての MCP ツールの動作確認

### 優先度 中
- [ ] Firefox 対応の実装
- [ ] ヘッドレスモード対応
- [ ] 非対話型モード完全実装

### 優先度 低
- [ ] パフォーマンス最適化（起動時間 < 15秒）
- [ ] モジュール化リファクタリング（v1.3.0）
