---
name: devops-monitor
description: DevTools 接続診断、MCP ヘルスチェック、リソース使用状況確認、ネットワーク診断を行います。SSHトンネル状態確認やポートフォワーディング診断にも対応。
allowed-tools: Bash, Read, Grep
---

# DevOps Monitor

## 概要
開発環境のヘルスチェックと診断を行うスキルです。

## 診断コマンド

### DevTools 接続診断
```bash
# ポート番号（環境変数または引数から取得）
PORT=${MCP_CHROME_DEBUG_PORT:-${CLAUDE_CHROME_DEBUG_PORT:-9222}}

# バージョン情報
curl -sf http://127.0.0.1:${PORT}/json/version | jq '.'

# タブ一覧
curl -sf http://127.0.0.1:${PORT}/json/list | jq '.[].title'

# WebSocket エンドポイント
curl -sf http://127.0.0.1:${PORT}/json/version | jq -r '.webSocketDebuggerUrl'

# Protocol バージョン
curl -sf http://127.0.0.1:${PORT}/json/protocol | head -c 200
```

### MCP ヘルスチェック
```bash
# .mcp.json から設定確認
cat .mcp.json | jq '.mcpServers | keys[]'

# 各MCPサーバーのコマンド存在確認
for cmd in npx node uvx; do
    echo "$cmd: $(command -v $cmd 2>/dev/null || echo 'NOT FOUND')"
done
```

### リソース使用状況
```bash
# CPU ロードアベレージ
uptime

# メモリ
free -h

# ディスク
df -h / /mnt/LinuxHDD

# Claude/Node プロセス
pgrep -a -f "claude" 2>/dev/null
pgrep -a -f "node" 2>/dev/null
```

### ネットワーク診断
```bash
# SSHトンネル（ポートフォワーディング）確認
ss -tlnp | grep ${PORT}

# ポート使用状況
fuser ${PORT}/tcp 2>/dev/null

# リモートポートフォワーディングテスト
curl -sf --connect-timeout 5 http://127.0.0.1:${PORT}/json/version > /dev/null && \
    echo "OK: Port ${PORT} forwarding active" || \
    echo "FAIL: Port ${PORT} not accessible"
```

### tmux セッション診断
```bash
# tmux バージョン
tmux -V

# アクティブセッション
tmux list-sessions 2>/dev/null || echo "No sessions"

# 特定セッションのペイン一覧
tmux list-panes -t claude-{project}-{port} -F '#{pane_index}: #{pane_current_command} (#{pane_width}x#{pane_height})'
```

## 診断スクリプト
- `scripts/test/test-devtools-connection.sh [PORT]` — DevTools接続テスト
- `scripts/tmux/panes/devtools-monitor.sh PORT` — DevTools継続監視
- `scripts/tmux/panes/mcp-health-monitor.sh` — MCP健全性監視
- `scripts/tmux/panes/resource-monitor.sh` — リソース監視

## ステータスコード

| 状態 | 意味 |
|------|------|
| `CONNECTED` (緑) | DevTools接続正常 |
| `DISCONNECTED` (赤) | DevTools接続不可 |
| `✓` | MCPサーバー正常 |
| `✗` | MCPサーバー異常 |

## よくある問題

| 症状 | 原因 | 対処 |
|------|------|------|
| DevTools DISCONNECTED | SSHトンネル切断 | SSH再接続（`-R PORT:127.0.0.1:PORT`） |
| DevTools DISCONNECTED | ブラウザ未起動 | Windows側でブラウザ起動確認 |
| MCP ✗ | npm パッケージ未インストール | `npx` で自動インストールされるか確認 |
| メモリ不足 | Node.js プロセス過多 | 不要なセッションを終了 |
