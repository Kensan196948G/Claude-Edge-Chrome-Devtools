---
name: tmux-ops
description: tmux ダッシュボードのレイアウト切替、セッション管理、ペイン操作を行います。レイアウトの切替、ペインの追加・削除・リサイズ、セッション一覧・情報表示に対応。
allowed-tools: Bash, Read
---

# tmux Dashboard Operations

## 概要

tmux ダッシュボードの操作と管理を行うスキルです。

## 利用可能なレイアウト

| レイアウト名 | ペイン数 | 用途 |
|-------------|---------|------|
| `default` | 2 (DevTools + Git/Resource) | チームなし・個人作業 |
| `review-team` | 4 (2x2: DevTools, Agent, MCP, Git/Resource) | レビューチーム3名 |
| `fullstack-dev-team` | 6 (3x2: DevTools, Agent, MCP, Git, Resource, Log) | 開発チーム4名 |
| `debug-team` | 3 (DevTools+MCP, Agent, Log) | デバッグチーム3名 |

## レイアウト設定ファイル

- パス: `scripts/tmux/layouts/{layout-name}.conf`
- フォーマット: `PANE_NAME SPLIT_DIR SPLIT_PCT SCRIPT_NAME ARGS`

## コマンド例

### レイアウト切替

```bash
# 現在のセッションを確認
tmux list-sessions

# レイアウト切替（セッションを再作成）
bash scripts/tmux/tmux-dashboard.sh PROJECT_NAME PORT LAYOUT_NAME "cd $(pwd) && ./run-claude.sh"
```

### ペイン操作

```bash
# ペイン一覧
tmux list-panes -t claude-{project}-{port}

# 特定のペインにフォーカス
tmux select-pane -t claude-{project}-{port}:{window}.{pane}

# ペインをフルスクリーンにズーム (toggle)
# tmux prefix + z (デフォルト: Ctrl-b z)

# ペインを手動で分割
tmux split-window -h -t claude-{project}-{port} 'bash scripts/tmux/panes/devtools-monitor.sh PORT'
```

### セッション管理

```bash
# 既存セッションにアタッチ（SSH切断後の復帰）
tmux attach-session -t claude-{project}-{port}

# セッション切替（マルチプロジェクト時）
tmux switch-client -t claude-{other-project}-{port}

# セッション終了
tmux kill-session -t claude-{project}-{port}
```

## キーバインド一覧 (tmux デフォルト)

| キー | 動作 |
|------|------|
| `Ctrl-b z` | ペインのズーム (toggle) |
| `Ctrl-b ←↑↓→` | ペイン間の移動 |
| `Ctrl-b d` | セッションからデタッチ |
| `Ctrl-b s` | セッション一覧 |
| `Ctrl-b w` | ウィンドウ一覧 |
| `Ctrl-b [` | コピーモード（スクロール） |
| `Ctrl-b :` | コマンドモード |

## トラブルシューティング

- **ペインが黒い / スクリプトが停止**: ペインを選択して `Ctrl-c` → スクリプトを手動実行
- **レイアウトが崩れた**: `tmux kill-session -t SESSION` で再作成
- **tmux が起動しない**: `tmux -V` でバージョン確認、`scripts/tmux/tmux-install.sh` で再インストール
