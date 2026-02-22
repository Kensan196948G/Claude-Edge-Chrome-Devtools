---
name: agent-teams-ops
description: Agent Teams の作成・監視・シャットダウンを行います。review-team / fullstack-dev-team / debug-team テンプレートの選択・スポーン、メンバー状態監視、チームクリーンアップに対応。
allowed-tools: Bash, Read, TeamCreate, SendMessage, TodoWrite
---

# Agent Teams Operations

## 概要
Agent Teams のライフサイクル管理スキルです。チーム作成からシャットダウンまでをガイドします。

## チームテンプレート

### review-team (レビューチーム)
- **メンバー**: 3名 (architecture-reviewer, implementation-reviewer, test-reviewer)
- **用途**: コードレビュー、設計レビュー、テスト設計レビュー
- **tmux レイアウト**: `review-team` (4ペイン)
- **設定ファイル**: `.claude/teams/review-team.json`

### fullstack-dev-team (開発チーム)
- **メンバー**: 4名 (frontend-dev, backend-dev, test-engineer, devops)
- **用途**: フルスタック機能開発
- **tmux レイアウト**: `fullstack-dev-team` (6ペイン)
- **設定ファイル**: `.claude/teams/fullstack-dev-team.json`

### debug-team (デバッグチーム)
- **メンバー**: 3名 (investigator, fixer, tester)
- **用途**: バグ調査・修正・検証
- **tmux レイアウト**: `debug-team` (3ペイン)
- **設定ファイル**: `.claude/teams/debug-team.json`

## チーム操作手順

### 1. チーム作成
```
TeamCreate で新しいチームを作成:
  team_name: "review-team" | "fullstack-dev-team" | "debug-team"
  description: タスクの概要説明
```

### 2. メンバースポーン
Task ツールで各メンバーを name + team_name 付きで起動。

### 3. タスク割り当て
TaskCreate でタスクを作成し、TaskUpdate で owner を設定。

### 4. 状態監視
```bash
# チーム設定確認
cat ~/.claude/teams/{team-name}/config.json | jq '.'

# メンバー一覧
cat ~/.claude/teams/{team-name}/config.json | jq '.members[] | {name, agentType}'

# タスク一覧
ls ~/.claude/tasks/{team-name}/
```

### 5. チームシャットダウン
```
SendMessage で各メンバーに shutdown_request を送信:
  type: "shutdown_request"
  recipient: "{member-name}"
  content: "タスク完了、シャットダウンします"
```
全メンバー終了後、TeamDelete でクリーンアップ。

## CLAUDE.md レビューフローとの連携

CLAUDE.md の「標準レビュー〜修復フロー」に従い:
1. Agent Teams でレビューを実施
2. 各 Agent が問題点・修復オプション・影響範囲・リスクを提示
3. Orchestrator が統合
4. **人間が修復オプションを選択**
5. 選択されたオプションのみ実行

## 注意事項
- チーム作成後は tmux の agent-teams-monitor.sh が自動検出
- `~/.claude/teams/` と `~/.claude/tasks/` がチーム状態ストア
- メンバーの idle 通知は正常動作（メッセージ送信後の待機状態）
