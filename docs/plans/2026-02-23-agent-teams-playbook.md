# Agent Teams + tmux 運用プレイブック

**作成日**: 2026-02-23
**対象バージョン**: tmux 3.4、Claude Code (Agent Teams対応)
**ベースコミット**: `949905a`（verify-tmux-features.sh 完成版）

---

## 1. 概要

このプレイブックは、Claude-EdgeChromeDevTools における **Agent Teams × tmux ダッシュボード** の起動・監視・修復・トラブルシューティング手順をまとめたものです。

全50カテゴリ（5プロジェクト × 10カテゴリ）のテストを経て確立した、実運用に即した手順を記載しています。

---

## 2. システム構成

```
Windows (Claude Code Orchestrator)
  │
  ├── D:\Claude-EdgeChromeDevTools\scripts\tmux\
  │   ├── tmux-dashboard.sh        # メインレイアウトエンジン
  │   ├── tmux-install.sh          # tmux自動インストール
  │   ├── panes/                   # モニタリングペイン (5スクリプト)
  │   └── layouts/                 # レイアウト設定 (5ファイル)
  │
  └── SSH → kensan@kensan1969 (192.168.0.185)
        │
        └── /mnt/LinuxHDD/{PROJECT_NAME}/scripts/tmux/
              ├── tmux-dashboard.sh
              ├── tmux-install.sh
              ├── panes/
              └── layouts/
```

---

## 3. 起動手順

### 3.1 事前確認

```bash
# Linux ホストへ接続確認
ssh -o BatchMode=yes kensan@kensan1969 "echo OK"

# tmux バージョン確認 (3.1+ 必須、3.4 推奨)
ssh kensan@kensan1969 "tmux -V"

# プロジェクト存在確認
ssh kensan@kensan1969 "ls /mnt/LinuxHDD/ | head -20"
```

### 3.2 tmux スクリプト展開（初回 or 更新時）

```bash
# Windows側から実行 (Git Bash / WSL)
cd D:/Claude-EdgeChromeDevTools

# 単一プロジェクト展開
bash scripts/test/deploy-tmux-scripts.sh <PROJECT_NAME>

# 複数プロジェクト並列展開
PROJECTS=(
  "Linux-Management-Systm"
  "ITSM-ITManagementSystem"
  "Enterprise-AI-HelpDesk-System"
  "Mirai-IT-Knowledge-System"
  "ITSM-System"
)
for p in "${PROJECTS[@]}"; do
  bash scripts/test/deploy-tmux-scripts.sh "$p" &
done
wait
echo "全プロジェクト展開完了"
```

### 3.3 tmux ダッシュボード起動

```bash
# Linux側で実行
ssh kensan@kensan1969

# プロジェクトディレクトリへ移動
cd /mnt/LinuxHDD/<PROJECT_NAME>

# ダッシュボード起動 (autoレイアウトで自動検出)
bash scripts/tmux/tmux-dashboard.sh <PROJECT_NAME> <PORT>

# 明示的レイアウト指定
bash scripts/tmux/tmux-dashboard.sh <PROJECT_NAME> <PORT> review-team
bash scripts/tmux/tmux-dashboard.sh <PROJECT_NAME> <PORT> fullstack-dev-team
bash scripts/tmux/tmux-dashboard.sh <PROJECT_NAME> <PORT> debug-team
```

### 3.4 Windows PowerShell からの自動起動

`config.json` の `tmux.enabled: true` を設定すると、`Claude-EdgeDevTools.ps1` / `Claude-ChromeDevTools-Final.ps1` 実行時に自動的に tmux ダッシュボードが起動します。

---

## 4. セッション管理

### 4.1 セッション命名規則

```
claude-{PROJECT_NAME}-{PORT}
```

例:
- `claude-Linux-Management-Systm-9222`
- `claude-ITSM-ITManagementSystem-9223`

### 4.2 セッション一覧確認

```bash
ssh kensan@kensan1969 "tmux list-sessions"
```

### 4.3 既存セッションへの再接続 (SSH切断後)

```bash
ssh kensan@kensan1969
tmux attach -t claude-<PROJECT_NAME>-<PORT>

# または run-claude.sh が自動で再接続
bash /mnt/LinuxHDD/<PROJECT_NAME>/run-claude.sh
```

### 4.4 セッション強制終了

```bash
ssh kensan@kensan1969 "tmux kill-session -t claude-<PROJECT_NAME>-<PORT>"
# または全セッション終了
ssh kensan@kensan1969 "tmux kill-server"
```

---

## 5. 検証（テスト）手順

### 5.1 単一プロジェクト検証

```bash
# 使用方法: bash verify-tmux-features.sh <PROJECT_NAME> <PORT>
bash scripts/test/verify-tmux-features.sh Linux-Management-Systm 9222
```

出力形式:
```json
{"project":"Linux-Management-Systm","pass":10,"fail":0,"results":{"C1":"PASS","C2":"PASS",...}}
```

### 5.2 全プロジェクト並列検証 (推奨方式)

> **重要**: Agent Teams Bash サブエージェントによる並列実行は通信問題（アイドルのみ返送）が確認されているため、シェルレベルのバックグラウンドジョブを推奨します。

```bash
#!/usr/bin/env bash
# 全5プロジェクト並列テスト実行スクリプト

PROJECTS=(
  "Linux-Management-Systm:9222"
  "ITSM-ITManagementSystem:9223"
  "Enterprise-AI-HelpDesk-System:9224"
  "Mirai-IT-Knowledge-System:9225"
  "ITSM-System:9226"
)

RESULTS_FILE="/tmp/tmux-test-results-$(date +%Y%m%d-%H%M%S).jsonl"

for entry in "${PROJECTS[@]}"; do
  PROJECT="${entry%%:*}"
  PORT="${entry##*:}"
  bash scripts/test/verify-tmux-features.sh "$PROJECT" "$PORT" >> "$RESULTS_FILE" &
done
wait

echo "=== テスト結果 ==="
cat "$RESULTS_FILE"
echo ""
echo "PASS 数: $(grep -o '"pass":[0-9]*' "$RESULTS_FILE" | awk -F: '{sum+=$2} END{print sum}')"
echo "FAIL 数: $(grep -o '"fail":[0-9]*' "$RESULTS_FILE" | awk -F: '{sum+=$2} END{print sum}')"
```

### 5.3 検証カテゴリ一覧

| Cat | 検証項目 | コマンド | 合否基準 |
|-----|---------|---------|---------|
| C1 | tmux セッション作成 | `tmux list-sessions` | セッション名が存在 |
| C2 | ペインボーダーラベル | `tmux show-options pane-border-status` | 値が `top` |
| C3 | マウスリサイズ | `tmux show-options mouse` | 値が `on` |
| C4 | pane 0 識別ラベル | `tmux display-message -p '#{pane_title}'` | `Claude Code` を含む |
| C5 | tmux-dashboard.sh 存在 | `test -f .../tmux-dashboard.sh` | ファイルが存在 |
| C6 | panes/ スクリプト数 | `find .../panes/ -name '*.sh' \| wc -l` | 1件以上 |
| C7 | pane-border-format | `tmux show-options pane-border-format` | `pane_title` を含む |
| C8 | SSH切断耐性 | `detach-client` → `has-session` | `ALIVE` を返す |
| C9 | 環境変数伝播 | tmux env または settings.json | `ENVVAR_OK` or `SETTINGS_OK` |
| C10 | run-claude.sh 連携 | `grep -c 'select-pane.*-T.*Claude Code'` | マッチ 1件以上 |

---

## 6. Agent Teams 運用

### 6.1 環境変数設定確認

```bash
# Linux側 settings.json を確認
ssh kensan@kensan1969 "cat ~/.claude/settings.json | grep AGENT_TEAMS"
# 期待値: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"

# tmux セッション内環境変数確認
ssh kensan@kensan1969 "tmux show-environment -t <SESSION_NAME> CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
# 期待値: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

### 6.2 Agent Teams × tmux 起動フロー

```
1. Windows: Claude-EdgeDevTools.ps1 / Claude-ChromeDevTools-Final.ps1 実行
   └── tmux.enabled: true → tmux-dashboard.sh を SSH 経由で起動
       └── pane 0: Claude Code (Agent Teams有効)
       └── pane 1+: モニタリングペイン各種

2. Linux tmux セッション内:
   pane 0: claude --dangerously-skip-permissions
           → INIT_PROMPT で Agent Teams 設定を説明
           → Orchestrator として他の Agent を Spawn

3. Agent Spawn時: 新規tmuxペインは作成されない
   (Agent TeamsはClaude Codeプロセス内で管理)
```

### 6.3 Agent Teams 推奨ユースケース

| ユースケース | 推奨方式 | 理由 |
|-------------|---------|------|
| 複数プロジェクトへの並列コマンド実行 | Bash バックグラウンドジョブ | 確実・高速・シンプル |
| コードレビュー Agent | Agent Teams | コンテキスト共有・対話型 |
| 並列実装 Agent | Agent Teams | 独立タスクの同時進行 |
| 結果報告が必要な並列処理 | Agent Teams + SendMessage | 通信プロトコルが確立している場合 |

---

## 7. トラブルシューティング FAQ

### Q1: tmux が起動しない

**症状**: `bash tmux-dashboard.sh` が即座に終了する

**確認手順**:
```bash
# tmux インストール確認
ssh kensan@kensan1969 "which tmux && tmux -V"

# tmux がない場合
ssh kensan@kensan1969 "bash /mnt/LinuxHDD/<PROJECT>/scripts/tmux/tmux-install.sh"
```

---

### Q2: ペインボーダーラベルが表示されない (C2 FAIL)

**原因**: tmux バージョンが 2.6 未満 (pane-border-status は 2.6+ で追加)

**確認**:
```bash
ssh kensan@kensan1969 "tmux -V"
# tmux 3.4 なら問題なし
```

**tmux-dashboard.sh での対応**:
```bash
# エラー無視でオプション設定 (2>/dev/null || true)
tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
```

---

### Q3: マウスリサイズが効かない (C3 FAIL)

**確認**:
```bash
ssh kensan@kensan1969 "tmux show-options -g mouse"
```

**手動設定**:
```bash
ssh kensan@kensan1969 "tmux set-option -g mouse on"
```

---

### Q4: pane 0 タイトルが設定されない (C4 FAIL)

**原因**: `select-pane -T` が tmux 3.0 未満では動作しない

**確認**:
```bash
ssh kensan@kensan1969 "tmux -V"
# 3.0+ であること
```

---

### Q5: tmux-dashboard.sh が見つからない (C5 FAIL)

**原因**: スクリプト展開が実行されていない

**修正**:
```bash
# Windows側で再展開
bash scripts/test/deploy-tmux-scripts.sh <PROJECT_NAME>

# 展開後確認
ssh kensan@kensan1969 "ls -la /mnt/LinuxHDD/<PROJECT>/scripts/tmux/"
```

---

### Q6: panes/ スクリプトが 0 件 (C6 FAIL)

**確認**:
```bash
ssh kensan@kensan1969 "ls /mnt/LinuxHDD/<PROJECT>/scripts/tmux/panes/"
```

**修正**: `deploy-tmux-scripts.sh` を再実行

---

### Q7: SSH 切断後にセッションが消える (C8 FAIL)

**原因**: tmux がインストールされていない、またはセッションが作成されていない

**確認**:
```bash
ssh kensan@kensan1969 "tmux list-sessions"
```

**注意**: tmux セッション内で起動した Claude Code は SSH切断後も継続する。
tmux がない場合はセッションが消える。

---

### Q8: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS が設定されていない (C9 FAIL)

**確認**:
```bash
ssh kensan@kensan1969 "cat ~/.claude/settings.json"
```

**修正** (jq が必要):
```bash
ssh kensan@kensan1969 "
  jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = \"1\"' \
    ~/.claude/settings.json > /tmp/settings_new.json \
  && mv /tmp/settings_new.json ~/.claude/settings.json
"
```

---

### Q9: Agent Teams Bash サブエージェントが結果を返さない

**症状**: `TeamCreate` → Bash サブエージェントを Spawn → アイドル通知のみ、`SendMessage` でも結果が返ってこない

**根本原因**: Bash サブエージェントは「コマンド実行して終了」する用途では `SendMessage` で結果を返さない場合がある

**対処法**: シェルレベルのバックグラウンドジョブに切り替える
```bash
# Agent Teams の代わりに直接並列実行
for entry in "Project1:9222" "Project2:9223"; do
  PROJECT="${entry%%:*}"
  PORT="${entry##*:}"
  bash scripts/test/verify-tmux-features.sh "$PROJECT" "$PORT" &
done
wait
```

---

### Q10: TeamDelete が失敗する (active members エラー)

**症状**: `"Cannot cleanup team with N active member(s)"` エラー

**原因**: Spawn したサブエージェントがまだアクティブ登録されている

**対処法**:
1. 全メンバーにシャットダウンリクエストを送信
2. 数秒待機
3. TeamDelete を再試行

```
# 各エージェントへ SendMessage type=shutdown_request
# recipient: "agent-proj1" 〜 "agent-proj5"
```

---

## 8. モニタリングペイン説明

| スクリプト | 更新間隔 | 監視内容 | 異常時挙動 |
|-----------|---------|---------|-----------|
| `devtools-monitor.sh` | 5秒 | DevTools (curl /json/version) | ペイン赤表示 + エラーカウント |
| `mcp-health-monitor.sh` | 30秒 | MCP プロセス状態 | ペイン赤表示 |
| `git-status-monitor.sh` | 10秒 | git status / branch | 変更ファイル数表示 |
| `resource-monitor.sh` | 15秒 | CPU/メモリ/ディスク | 使用率表示 |
| `agent-teams-monitor.sh` | 5秒 | Agent Teams 状態 | チーム数・タスク数表示 |

---

## 9. レイアウト設定リファレンス

### layout ファイル形式

```
# 形式: PANE_NAME SPLIT_DIRECTION SPLIT_PERCENTAGE SCRIPT_NAME [ARGS...]
# SPLIT_DIRECTION: h (水平分割) | v (垂直分割)
# SPLIT_PERCENTAGE: 分割後の新ペインのサイズ%

Monitor  h  30  devtools-monitor.sh  __PORT__
Git      v  50  git-status-monitor.sh
```

### レイアウト一覧

| ファイル | ペイン数 | 用途 |
|---------|---------|------|
| `default.conf` | 2 | 個人作業・シンプル |
| `review-team.conf` | 4 | コードレビューチーム |
| `fullstack-dev-team.conf` | 6 | フルスタック開発チーム |
| `debug-team.conf` | 3 | デバッグ・調査 |
| `custom.conf.template` | カスタム | 自由設計 |

---

## 10. 実績・ベンチマーク

### 2026-02-23 テスト結果

| 指標 | 値 |
|------|-----|
| テスト実行時間 | 約2分（並列実行） |
| 成功率 | 100%（50/50 PASS） |
| 自動修復回数 | 0回（初回全PASS） |
| 対象プロジェクト数 | 5 |
| tmux バージョン | 3.4 |

### 並列実行ベンチマーク

| 方式 | 5プロジェクト所要時間 | 信頼性 |
|-----|---------------------|--------|
| Agent Teams Bash サブエージェント | タイムアウト（結果返送なし） | 低 |
| Bash バックグラウンドジョブ (`&` + `wait`) | 約2分 | 高 |
| 逐次実行（for ループ） | 約10分 | 高 |

---

## 11. 参考コミット

| コミット | 内容 |
|---------|------|
| `c853774` | feat: tmux ペインボーダーラベル・マウスリサイズ・pane 0 識別を実装 |
| `a125fdf` | feat: tmux スクリプト展開ヘルパー (deploy-tmux-scripts.sh) 追加 |
| `99c33bb` | fix: deploy-tmux-scripts.sh セキュリティ修正 |
| `f1c3250` | feat: tmux 10カテゴリ検証スクリプト追加 |
| `d6df1cd` | fix: verify-tmux-features.sh スペック修正 |
| `3e5f147` | fix: verify-tmux-features.sh スペック違反修正 |
| `c61087d` | fix: verify-tmux-features.sh C6 find から 2>/dev/null 除去 |
| `949905a` | fix: verify-tmux-features.sh セットアップ失敗パスとC10整数比較修正 |

---

## 12. 関連ドキュメント

- **テスト設計書**: `docs/plans/2026-02-23-tmux-agent-teams-test-design.md`
- **テストレポート**: `docs/plans/2026-02-23-tmux-agent-teams-test-report.md`
- **実装計画**: `docs/plans/2026-02-23-tmux-agent-teams-test.md`
- **プロジェクト概要**: `CLAUDE.md`
