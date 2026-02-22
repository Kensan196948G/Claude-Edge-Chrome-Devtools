# tmux-layout-sync スキル

`TeamCreate` / `TeamDelete` 実行後に tmux レイアウトを再構成します。新しい Agent Teams に対応したペイン数へ自動調整し、`~/.claude/teams/` の変化をレイアウトに反映します。

## 使用シーン

- `TeamCreate` で新しい Agent Team を作成した後
- `TeamDelete` でチームを削除した後
- tmux ペイン数と Agent Teams 数がズレている場合
- `auto` レイアウトを手動でトリガーしたい場合

## 背景

`defaultLayout: "auto"` が有効な場合、`~/.claude/teams/` ディレクトリを5秒ごとにスキャンしてレイアウトを動的調整します。ただし即座に反映させたい場合や、大幅なレイアウト変更が必要な場合はこのスキルで手動同期します。

## Step 1: 現在の状態確認

```bash
# アクティブなセッション確認
tmux list-sessions

# Agent Teams の状態確認
ls ~/.claude/teams/ 2>/dev/null && echo "Teams: $(ls ~/.claude/teams/ | wc -l)" || echo "Teams: 0"

# 現在のペイン構成確認
tmux list-panes -t claude-{project}-{port} -F "#{pane_index}: #{pane_title} (#{pane_width}x#{pane_height})"
```

## Step 2: セッションを停止して再起動

### セッション名を確認

```bash
tmux list-sessions
# 出力例: claude-myproject-9222: 1 windows
```

### セッションを安全に停止

Claude Code が実行中の場合、まず Claude Code を終了します（`/exit` コマンド）。その後:

```bash
tmux kill-session -t claude-{project}-{port}
```

## Step 3: 新しいレイアウトでダッシュボードを再起動

```bash
# プロジェクトディレクトリへ移動
cd /mnt/LinuxHDD/{project}

# auto レイアウトで tmux ダッシュボードを再起動
bash scripts/tmux/tmux-dashboard.sh {project} {port} auto "cd $(pwd) && ./run-claude.sh"
```

### レイアウト選択基準（auto モードの動作）

| `~/.claude/teams/` のチーム数 | 選択されるレイアウト |
|-------------------------------|---------------------|
| 0 チーム | `default` (2ペイン) |
| 1-2 チーム | `review-team` (4ペイン) |
| 3-4 チーム | `fullstack-dev-team` (6ペイン) |
| 5+ チーム | `debug-team` (3ペイン) |

## Step 4: 新レイアウト確認

```bash
# セッションが起動しているか確認
tmux list-sessions

# ペイン構成を確認
tmux list-panes -t claude-{project}-{port}

# 各ペインのタイトルを確認
tmux list-panes -t claude-{project}-{port} -F "#{pane_index}: #{pane_title}"
```

## Step 5: 既存セッションへ再接続

```bash
tmux attach-session -t claude-{project}-{port}
```

## 手動レイアウト切替（auto を使わない場合）

特定のレイアウトを指定したい場合:

```bash
# default レイアウト（2ペイン）
bash scripts/tmux/tmux-dashboard.sh {project} {port} default "cd $(pwd) && ./run-claude.sh"

# review-team レイアウト（4ペイン）
bash scripts/tmux/tmux-dashboard.sh {project} {port} review-team "cd $(pwd) && ./run-claude.sh"

# fullstack-dev-team レイアウト（6ペイン）
bash scripts/tmux/tmux-dashboard.sh {project} {port} fullstack-dev-team "cd $(pwd) && ./run-claude.sh"

# debug-team レイアウト（3ペイン）
bash scripts/tmux/tmux-dashboard.sh {project} {port} debug-team "cd $(pwd) && ./run-claude.sh"
```

## トラブルシューティング

| 症状 | 原因 | 対処 |
|------|------|------|
| レイアウトが変わらない | auto スキャン間隔待ち | Step 2-3 で手動再起動 |
| ペイン数が多すぎる | 古い Teams ディレクトリが残存 | `ls ~/.claude/teams/` で確認・削除 |
| `tmux-dashboard.sh not found` | スクリプトパスの誤り | `pwd` でカレントディレクトリを確認 |
| セッション名が不明 | `tmux list-sessions` で確認 | セッション名は `claude-{project}-{port}` |

## 参考: tmux-ops スキルとの違い

| スキル | 用途 |
|--------|------|
| `tmux-ops` | 既存セッションのペイン操作・レイアウト切替（セッション継続） |
| `tmux-layout-sync` | Agent Teams 変更後のセッション再起動によるレイアウト全体再構成 |
