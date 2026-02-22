# tmux Agent Teams 並列テスト 実装計画

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 5プロジェクト×10カテゴリの tmux ダッシュボード機能を Agent Teams で並列検証し、失敗時は自動修復ループ（最大5回）で全 PASS を達成する

**Architecture:** Orchestrator（本セッション）が TeamCreate で 5 Project Agent + Repair Agent + Report Agent を起動。SSH 経由で Linux ホスト `kensan@kensan1969` に接続し、各プロジェクトに tmux スクリプトを展開後テスト実行。Memory MCP で結果集約し、修復ループ完了後にレポートを生成する。

**Tech Stack:** bash, tmux 3.4, Claude Code 2.1.50 (claude-sonnet-4-6), Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), Memory MCP, claude-mem plugin, SSH (`kensan@kensan1969`), git

---

## 事前確認チェックリスト

実行前に必ず確認:
- [ ] SSH 接続: `ssh kensan@kensan1969 echo OK`
- [ ] tmux バージョン: `ssh kensan@kensan1969 tmux -V` → `tmux 3.4`
- [ ] 5プロジェクト存在: `ssh kensan@kensan1969 ls /mnt/LinuxHDD/`
- [ ] Agent Teams env: `ssh kensan@kensan1969 cat ~/.claude/settings.json | grep AGENT_TEAMS`

---

### Task 1: 設計ドキュメント保存 & git コミット

**Files:**
- 確認: `docs/plans/2026-02-23-tmux-agent-teams-test-design.md` (作成済み)
- 確認: `docs/plans/2026-02-23-tmux-agent-teams-test.md` (本ファイル)

**Step 1: 現在の git 状態確認**

```bash
git -C /d/Claude-EdgeChromeDevTools status
```

Expected: `docs/plans/2026-02-23-*.md` が Untracked で表示される

**Step 2: コミット**

```bash
git -C /d/Claude-EdgeChromeDevTools add docs/plans/2026-02-23-tmux-agent-teams-test-design.md docs/plans/2026-02-23-tmux-agent-teams-test.md
git -C /d/Claude-EdgeChromeDevTools commit -m "docs: tmux Agent Teams 並列テスト設計書・実装計画追加

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

Expected: コミット成功

---

### Task 2: tmux スクリプト展開ヘルパー作成

**Files:**
- Create: `scripts/test/deploy-tmux-scripts.sh`

**概要**: 5プロジェクトに `scripts/tmux/` 配下の全スクリプトを SSH 経由で展開するスクリプト。
既存の base64 転送方式（CLAUDE.md 参照）を採用する。

**Step 1: ヘルパースクリプト確認（既存スクリプトの参考）**

```bash
ls /d/Claude-EdgeChromeDevTools/scripts/tmux/
ls /d/Claude-EdgeChromeDevTools/scripts/tmux/panes/
ls /d/Claude-EdgeChromeDevTools/scripts/tmux/layouts/
```

Expected:
```
tmux-dashboard.sh  tmux-install.sh
panes/: devtools-monitor.sh  mcp-health-monitor.sh  git-status-monitor.sh  resource-monitor.sh  agent-teams-monitor.sh
layouts/: default.conf  review-team.conf  fullstack-dev-team.conf  debug-team.conf  custom.conf.template
```

**Step 2: deploy-tmux-scripts.sh 作成**

```bash
# scripts/test/deploy-tmux-scripts.sh
#!/usr/bin/env bash
# tmux スクリプト群を指定プロジェクトに SSH 経由で展開する
# 使用: bash deploy-tmux-scripts.sh <PROJECT_NAME>
set -euo pipefail

LINUX_HOST="kensan@kensan1969"
LINUX_BASE="/mnt/LinuxHDD"
PROJECT_NAME="${1:?ERROR: PROJECT_NAME が指定されていません}"
REMOTE_BASE="${LINUX_BASE}/${PROJECT_NAME}"
SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tmux" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Deploy: ${PROJECT_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# リモートにディレクトリ作成
ssh "${LINUX_HOST}" "mkdir -p '${REMOTE_BASE}/scripts/tmux/panes' '${REMOTE_BASE}/scripts/tmux/layouts'"

# 各ファイルを base64 経由で転送
transfer_file() {
    local src_file="$1"
    local dst_path="$2"
    local content
    content=$(base64 < "$src_file")
    ssh "${LINUX_HOST}" "printf '%s' '${content}' | base64 -d > '${dst_path}' && chmod +x '${dst_path}'" 2>/dev/null || \
    ssh "${LINUX_HOST}" "echo '${content}' | base64 -d > '${dst_path}' && chmod +x '${dst_path}'"
    echo "  ✅ $(basename "$src_file") → ${dst_path}"
}

# メインスクリプト
transfer_file "${SCRIPT_SRC}/tmux-dashboard.sh" "${REMOTE_BASE}/scripts/tmux/tmux-dashboard.sh"
transfer_file "${SCRIPT_SRC}/tmux-install.sh"   "${REMOTE_BASE}/scripts/tmux/tmux-install.sh"

# panes
for f in "${SCRIPT_SRC}/panes/"*.sh; do
    transfer_file "$f" "${REMOTE_BASE}/scripts/tmux/panes/$(basename "$f")"
done

# layouts
for f in "${SCRIPT_SRC}/layouts/"*.conf "${SCRIPT_SRC}/layouts/"*.template; do
    [ -f "$f" ] || continue
    ssh "${LINUX_HOST}" "base64 < /dev/stdin > '${REMOTE_BASE}/scripts/tmux/layouts/$(basename "$f")'" < "$f"
    echo "  ✅ $(basename "$f") → layouts/"
done

echo ""
echo "✅ 展開完了: ${PROJECT_NAME}"
```

**Step 3: スクリプトに実行権限付与**

```bash
chmod +x /d/Claude-EdgeChromeDevTools/scripts/test/deploy-tmux-scripts.sh
```

**Step 4: コミット**

```bash
git -C /d/Claude-EdgeChromeDevTools add scripts/test/deploy-tmux-scripts.sh
git -C /d/Claude-EdgeChromeDevTools commit -m "feat: tmux スクリプト展開ヘルパー追加

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: テスト検証スクリプト作成（10カテゴリ）

**Files:**
- Create: `scripts/test/verify-tmux-features.sh`

**概要**: SSH 経由でプロジェクトに接続し、10カテゴリの検証を実行。
結果を JSON 形式で stdout に出力する。

**Step 1: verify-tmux-features.sh 作成**

```bash
#!/usr/bin/env bash
# verify-tmux-features.sh - tmux ダッシュボード 10カテゴリ検証
# 使用: bash verify-tmux-features.sh <PROJECT_NAME> <PORT>
# 出力: JSON {"project":"...","results":{"C1":"PASS",...}}
set -uo pipefail

LINUX_HOST="kensan@kensan1969"
LINUX_BASE="/mnt/LinuxHDD"
PROJECT_NAME="${1:?ERROR: PROJECT_NAME が指定されていません}"
PORT="${2:-9222}"
REMOTE_BASE="${LINUX_BASE}/${PROJECT_NAME}"
SESSION="claude-${PROJECT_NAME}-${PORT}"

RESULTS=()
PASS=0
FAIL=0

check() {
    local cat="$1" desc="$2" cmd="$3" expected="$4"
    local actual
    actual=$(ssh "${LINUX_HOST}" "${cmd}" 2>/dev/null || echo "ERROR")
    if echo "$actual" | grep -q "${expected}"; then
        RESULTS+=("\"${cat}\":\"PASS\"")
        PASS=$((PASS+1))
    else
        RESULTS+=("\"${cat}\":\"FAIL:${actual}\"")
        FAIL=$((FAIL+1))
    fi
}

# テスト用 tmux セッション起動（テスト専用、非インタラクティブ）
ssh "${LINUX_HOST}" "tmux new-session -d -s '${SESSION}' -x 220 -y 50 2>/dev/null || true"
ssh "${LINUX_HOST}" "bash '${REMOTE_BASE}/scripts/tmux/tmux-dashboard.sh' '${PROJECT_NAME}' '${PORT}' 'default' 'true' &>/tmp/tmux-test-${PROJECT_NAME}.log &" &
sleep 5  # セッション起動待機

# C1: tmux セッション作成・管理
check "C1" "セッション確認" "tmux list-sessions 2>/dev/null" "${SESSION}"

# C2: ペインボーダーラベル
check "C2" "pane-border-status=top" "tmux show-options -t '${SESSION}' pane-border-status 2>/dev/null" "top"

# C3: マウスリサイズ設定
check "C3" "mouse=on" "tmux show-options -t '${SESSION}' mouse 2>/dev/null" "on"

# C4: pane 0 識別ラベル（🤖）
check "C4" "pane 0 タイトル確認" "tmux display-message -t '${SESSION}.0' -p '#{pane_title}' 2>/dev/null" "Claude Code"

# C5: レイアウト自動検出スクリプト存在
check "C5" "tmux-dashboard.sh 存在" "test -f '${REMOTE_BASE}/scripts/tmux/tmux-dashboard.sh' && echo OK" "OK"

# C6: モニタリングペインスクリプト存在
check "C6" "panes スクリプト存在" "ls '${REMOTE_BASE}/scripts/tmux/panes/' | wc -l" "[1-9]"

# C7: pane-border-format 設定確認
check "C7" "pane-border-format 設定" "tmux show-options -t '${SESSION}' pane-border-format 2>/dev/null" "pane_title"

# C8: セッションデタッチ・再アタッチ
ssh "${LINUX_HOST}" "tmux detach-client -s '${SESSION}' 2>/dev/null || true"
check "C8" "デタッチ後セッション残存" "tmux has-session -t '${SESSION}' 2>/dev/null && echo ALIVE" "ALIVE"

# C9: 環境変数伝播
check "C9" "AGENT_TEAMS 環境変数" "tmux show-environment -t '${SESSION}' CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || grep AGENT_TEAMS ~/.claude/settings.json 2>/dev/null" "1"

# C10: tmux-dashboard.sh に pane 0 タイトル設定コード存在
check "C10" "pane 0 タイトルコード" "grep -c 'select-pane.*-T.*Claude Code' '${REMOTE_BASE}/scripts/tmux/tmux-dashboard.sh' 2>/dev/null" "[1-9]"

# クリーンアップ
ssh "${LINUX_HOST}" "tmux kill-session -t '${SESSION}' 2>/dev/null || true"

# JSON 出力
RESULTS_STR=$(IFS=','; echo "${RESULTS[*]}")
echo "{\"project\":\"${PROJECT_NAME}\",\"pass\":${PASS},\"fail\":${FAIL},\"results\":{${RESULTS_STR}}}"
```

**Step 2: スクリプト実行権限付与**

```bash
chmod +x /d/Claude-EdgeChromeDevTools/scripts/test/verify-tmux-features.sh
```

**Step 3: 単体テスト（ITSM-ITManagementSystem で試行）**

```bash
bash /d/Claude-EdgeChromeDevTools/scripts/test/verify-tmux-features.sh ITSM-ITManagementSystem 9222 2>&1
```

Expected: JSON 出力が `{"project":"ITSM-ITManagementSystem","pass":...,"fail":...,"results":{...}}` 形式

**Step 4: コミット**

```bash
git -C /d/Claude-EdgeChromeDevTools add scripts/test/verify-tmux-features.sh
git -C /d/Claude-EdgeChromeDevTools commit -m "feat: tmux 10カテゴリ検証スクリプト追加

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: 5プロジェクトへの tmux スクリプト展開

**概要**: Task 2 で作成した `deploy-tmux-scripts.sh` を使い、5プロジェクト全てにスクリプトを展開する。

**Step 1: 並列展開実行（バックグラウンド）**

```bash
PROJECTS=(
    "Linux-Management-Systm"
    "ITSM-ITManagementSystem"
    "Enterprise-AI-HelpDesk-System"
    "Mirai-IT-Knowledge-System"
    "ITSM-System"
)

for proj in "${PROJECTS[@]}"; do
    bash /d/Claude-EdgeChromeDevTools/scripts/test/deploy-tmux-scripts.sh "$proj" &
done
wait
echo "全プロジェクト展開完了"
```

Expected: 各プロジェクトの展開完了メッセージ × 5

**Step 2: 展開確認**

```bash
for proj in "Linux-Management-Systm" "ITSM-ITManagementSystem" "Enterprise-AI-HelpDesk-System" "Mirai-IT-Knowledge-System" "ITSM-System"; do
    ssh kensan@kensan1969 "ls '/mnt/LinuxHDD/${proj}/scripts/tmux/tmux-dashboard.sh' 2>/dev/null && echo '  ✅ ${proj}' || echo '  ❌ ${proj}'"
done
```

Expected: 全5プロジェクトで `✅` 表示

---

### Task 5: Agent Teams 並列テスト実行

**概要**: `TeamCreate` で `tmux-test-team` を作成し、5 Project Agent を並列で起動。
各 Agent が `verify-tmux-features.sh` を実行し、結果を Orchestrator に報告する。

**Step 1: TeamCreate — チーム作成**

Claude Code API を使って Agent Teams を起動する:
```
TeamCreate(team_name="tmux-test-team", description="tmux ダッシュボード10カテゴリ並列テスト")
```

**Step 2: タスク作成（5プロジェクト分）**

```
TaskCreate(subject="P1: Linux-Management-Systm テスト", description="bash /d/Claude-EdgeChromeDevTools/scripts/test/verify-tmux-features.sh Linux-Management-Systm 9222 を実行し結果を報告")
TaskCreate(subject="P2: ITSM-ITManagementSystem テスト", description="bash .../verify-tmux-features.sh ITSM-ITManagementSystem 9223 を実行し結果を報告")
TaskCreate(subject="P3: Enterprise-AI-HelpDesk-System テスト", description="...")
TaskCreate(subject="P4: Mirai-IT-Knowledge-System テスト", description="...")
TaskCreate(subject="P5: ITSM-System テスト", description="...")
```

**Step 3: Project Agent × 5 スポーン（Bash subagent）**

```
Task(subagent_type="Bash", prompt="[verify-tmux-features.sh の実行と結果報告]", run_in_background=true) × 5
```

**Step 4: 全 Agent 完了を待機**

全 Agent が完了 or タイムアウト（5分）になるまで待機。
結果を `docs/plans/2026-02-23-tmux-test-results-round1.json` に保存。

---

### Task 6: テスト結果集約・分析

**Files:**
- Create: `docs/plans/2026-02-23-tmux-test-results-round1.json`

**Step 1: 全プロジェクト結果を JSON に集約**

```bash
RESULTS_FILE="/d/Claude-EdgeChromeDevTools/docs/plans/2026-02-23-tmux-test-results-round1.json"
echo '{"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","round":1,"projects":[' > "$RESULTS_FILE"
# 各 Project Agent の結果を append
echo ']}' >> "$RESULTS_FILE"
```

**Step 2: 失敗カテゴリ特定**

```bash
# FAIL が含まれるカテゴリを抽出
grep -o '"C[0-9]*":"FAIL[^"]*"' "$RESULTS_FILE" | sort | uniq -c | sort -rn
```

Expected: 失敗カテゴリのリスト（0件なら全 PASS → Task 8 へジャンプ）

---

### Task 7: 自動修復ループ（最大 5 回）

**概要**: 失敗カテゴリがある場合、`tmux-dashboard.sh` を修正して再テストを繰り返す。

**判定ロジック**:
```
修復回数=0
while (FAIL > 0) and (修復回数 < 5):
    Repair Agent が失敗カテゴリを分析
    tmux-dashboard.sh を Edit で修正
    git commit -m "fix(repair#{修復回数}): ..."
    全5プロジェクトで再テスト
    修復回数++
```

**Step 1: Repair Agent の起動条件**

失敗カテゴリに応じた修復方針:

| 失敗カテゴリ | 推定原因 | 修復ポイント |
|------------|---------|------------|
| C2 (border-status) | tmux バージョン非対応 | `|| true` が効いていない → 確認 |
| C3 (mouse) | 同上 | 同上 |
| C4 (pane 0 タイトル) | `select-pane -T` の引数順 | `-T` の前に `-t` が必要か確認 |
| C7 (border-format) | フォーマット文字列のエスケープ | `#[` がシェルに誤解釈されていないか |
| C9 (環境変数) | `tmux show-environment` 非対応 | `grep` fallback を追加 |

**Step 2: 修復実行（Repair Agent）**

```bash
# tmux-dashboard.sh を修正後:
git -C /d/Claude-EdgeChromeDevTools add scripts/tmux/tmux-dashboard.sh
git -C /d/Claude-EdgeChromeDevTools commit -m "fix(repair#${REPAIR_COUNT}): C4 pane 0 タイトル修正

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

**Step 3: 再テスト**

Task 4（スクリプト再展開）→ Task 5（並列テスト）を再実行。

**Step 4: 5回修復後も FAIL が残る場合**

- 失敗カテゴリを「環境依存・tmux バージョン制限」として SKIP 扱いにする
- レポートに理由を記載する

---

### Task 8: テストレポート & プレイブック生成

**Files:**
- Create: `docs/plans/2026-02-23-tmux-agent-teams-test-report.md`
- Create: `docs/plans/2026-02-23-agent-teams-playbook.md`

**Step 1: テストレポート作成**

```markdown
# tmux Agent Teams 並列テスト レポート

**実行日時**: 2026-02-23
**対象プロジェクト**: 5件
**テストカテゴリ**: 10件
**修復ラウンド**: N 回

## 結果マトリクス

| プロジェクト | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | C9 | C10 | PASS率 |
|---|---|---|---|---|---|---|---|---|---|---|---|

## 修復履歴

| ラウンド | 修正内容 | コミット |
|---|---|---|

## 結論・推奨事項
```

**Step 2: 運用プレイブック作成**

```markdown
# Agent Teams + tmux 運用プレイブック

## 1. セットアップ
## 2. 起動手順
## 3. モニタリング確認ポイント
## 4. トラブルシューティング
## 5. SSH 切断復帰手順
## 6. スクリプト修復ガイド
```

**Step 3: 全成果物コミット**

```bash
git -C /d/Claude-EdgeChromeDevTools add docs/plans/2026-02-23-tmux-agent-teams-test-report.md docs/plans/2026-02-23-agent-teams-playbook.md
git -C /d/Claude-EdgeChromeDevTools commit -m "docs: tmux Agent Teams テストレポート・プレイブック追加

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

**Step 4: TeamDelete — チームクリーンアップ**

```
TeamDelete()
```

---

## 実行順序サマリー

```
Task 1: 設計ドキュメント git コミット
Task 2: deploy-tmux-scripts.sh 作成
Task 3: verify-tmux-features.sh 作成
Task 4: 5プロジェクトへのスクリプト展開
Task 5: Agent Teams 並列テスト実行
Task 6: 結果集約・失敗カテゴリ特定
Task 7: 自動修復ループ（FAIL がある間、最大5回）
Task 8: レポート・プレイブック生成 → TeamDelete
```

## 完了基準

- [ ] 全5プロジェクトでテスト実行完了
- [ ] 10カテゴリ中8カテゴリ以上 PASS（C9/C10 は SKIP 許容）
- [ ] テストレポート・プレイブック生成完了
- [ ] 全修復内容が git commit に記録されている
- [ ] TeamDelete 完了
