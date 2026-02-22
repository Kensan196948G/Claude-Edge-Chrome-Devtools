# session-restore スキル

SSH 切断後の tmux セッション復元手順を提供します。孤立プロセスのクリーンアップと DevTools 接続確認を含む完全な復元フローを実行します。

## 使用シーン

- SSH 接続が突然切断された後
- ネットワーク障害から回復した後
- Windows 側から再接続する際に tmux セッションを復元したい場合
- 孤立した Claude Code プロセスをクリーンアップしたい場合

## Step 1: セッション一覧確認

```bash
tmux list-sessions
```

**期待出力例**:
```
claude-myproject-9222: 1 windows (created ...)
claude-myproject-9223: 1 windows (created ...)
```

セッションが存在する場合は Step 2 へ。存在しない場合は Step 4（新規起動）へ。

## Step 2: セッション再接続

```bash
tmux attach-session -t claude-{project}-{port}
```

**セッション名の規則**: `claude-{プロジェクト名}-{ポート番号}`

例:
```bash
tmux attach-session -t claude-myproject-9222
```

接続できた場合は復元完了。接続できない場合は Step 3 へ。

## Step 3: 孤立プロセスの確認とクリーンアップ

### 孤立プロセスを確認

```bash
pgrep -a -f "claude"
```

### Claude Code プロセスの強制終了（必要な場合）

```bash
pkill -f "claude --dangerously-skip-permissions"
```

### 孤立した tmux セッションの強制終了

```bash
tmux kill-session -t claude-{project}-{port}
```

### ポートを占有しているプロセスのクリーンアップ

```bash
fuser -k {port}/tcp
```

## Step 4: DevTools 接続確認

セッション復元後、DevTools の接続状態を確認します。

```bash
# バージョン情報確認
curl -s http://127.0.0.1:${MCP_CHROME_DEBUG_PORT:-9222}/json/version | python3 -m json.tool 2>/dev/null || echo "DevTools 未接続"

# タブ一覧確認
curl -s http://127.0.0.1:${MCP_CHROME_DEBUG_PORT:-9222}/json/list | python3 -m json.tool 2>/dev/null | head -30
```

DevTools が未接続の場合は、Windows 側で start.bat から再起動が必要です。

## Step 5: 新規セッション起動（必要な場合）

既存セッションが見つからない場合、新規起動します。

```bash
# プロジェクトディレクトリへ移動
cd /mnt/LinuxHDD/{project}

# run-claude.sh で起動（tmux セッションを含む）
./run-claude.sh
```

または tmux ダッシュボードを直接起動:

```bash
bash scripts/tmux/tmux-dashboard.sh {project} {port} auto "cd $(pwd) && ./run-claude.sh"
```

## Step 6: 再接続確認

```bash
# セッション確認
tmux list-sessions

# ペイン状態確認
tmux list-panes -t claude-{project}-{port}

# 環境変数確認（Claude Code 内から）
echo $MCP_CHROME_DEBUG_PORT
echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
```

## トラブルシューティング

| 症状 | 原因 | 対処 |
|------|------|------|
| `tmux: no server running` | tmux サーバーが停止 | Step 5 で新規起動 |
| `can't find session` | セッション名の誤り | `tmux list-sessions` で正確な名前を確認 |
| DevTools 接続失敗 | SSH トンネル切断 | Windows 側から start.bat で再起動 |
| ポート競合 | 旧プロセスが残存 | `fuser -k {port}/tcp` でクリーンアップ |
| Agent Teams が消えた | tmux kill で Teams も終了 | TeamCreate から再起動 |
