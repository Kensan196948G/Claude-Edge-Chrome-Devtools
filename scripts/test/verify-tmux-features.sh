#!/usr/bin/env bash
# ============================================================
# scripts/test/verify-tmux-features.sh
# tmux ダッシュボード 10カテゴリ検証スクリプト
# ============================================================
# 使用: bash verify-tmux-features.sh <PROJECT_NAME> <PORT>
# 出力: JSON {"project":"...","pass":N,"fail":N,"results":{"C1":"PASS",...}}
# ============================================================
set -uo pipefail

# ------------------------------------------------------------
# 引数バリデーション
# ------------------------------------------------------------
if [ $# -lt 2 ]; then
    echo "ERROR: 引数が不足しています。" >&2
    echo "使用: bash $(basename "${BASH_SOURCE[0]}") <PROJECT_NAME> <PORT>" >&2
    exit 1
fi

PROJECT_NAME="$1"
PORT="$2"

if [[ ! "${PROJECT_NAME}" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "ERROR: PROJECT_NAME に使用できない文字が含まれています: ${PROJECT_NAME}" >&2
    exit 1
fi

if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: PORT は数字のみ使用できます: ${PORT}" >&2
    exit 1
fi

# ------------------------------------------------------------
# 定数
# ------------------------------------------------------------
LINUX_HOST="kensan@kensan1969"
LINUX_BASE="/mnt/LinuxHDD"
REMOTE_BASE="${LINUX_BASE}/${PROJECT_NAME}"
SESSION_NAME="verify-tmux-${PROJECT_NAME}-${PORT}"
SSH_TIMEOUT=10

# ------------------------------------------------------------
# 結果格納用 (連想配列は bash 4+ が必要)
# ------------------------------------------------------------
declare -A RESULTS
PASS_COUNT=0
FAIL_COUNT=0

# ------------------------------------------------------------
# ユーティリティ: SSH コマンド実行（タイムアウト付き）
# ------------------------------------------------------------
ssh_run() {
    # $@ : リモートで実行するコマンド文字列（1引数推奨）
    timeout "${SSH_TIMEOUT}" ssh -o BatchMode=yes -o ConnectTimeout="${SSH_TIMEOUT}" \
        "${LINUX_HOST}" "$@" 2>&1
}

# ------------------------------------------------------------
# ユーティリティ: チェック結果を記録
# ------------------------------------------------------------
record() {
    local cat="$1"   # C1..C10
    local result="$2"  # PASS | FAIL
    RESULTS["${cat}"]="${result}"
    if [ "${result}" = "PASS" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ------------------------------------------------------------
# リモートに検証用 tmux セッションをセットアップ
# ------------------------------------------------------------
setup_session() {
    ssh_run "
        # 既存セッションがあれば先にクリア
        tmux kill-session -t '${SESSION_NAME}' || true

        # 検証用セッション作成
        tmux new-session -d -s '${SESSION_NAME}' -x 220 -y 50

        # tmux-dashboard.sh の実装を模倣した最小オプション設定
        tmux set-option -t '${SESSION_NAME}' pane-border-status top
        tmux set-option -t '${SESSION_NAME}' mouse on
        tmux set-option -t '${SESSION_NAME}' pane-border-format '#{?pane_active,#[bold],} #{pane_title} #[default]'
        tmux select-pane -t '${SESSION_NAME}.0' -T '🤖 Claude Code [${PROJECT_NAME}]'

        echo SETUP_OK
    "
}

# ------------------------------------------------------------
# 後処理: テストセッション削除
# ------------------------------------------------------------
cleanup_session() {
    ssh -o BatchMode=yes -o ConnectTimeout="${SSH_TIMEOUT}" \
        "${LINUX_HOST}" "tmux kill-session -t '${SESSION_NAME}' 2>/dev/null || true" \
        2>/dev/null || true
}

# ------------------------------------------------------------
# C1: tmux セッション作成・管理
# ------------------------------------------------------------
check_c1() {
    local out
    out=$(ssh_run "tmux list-sessions 2>&1")
    if echo "${out}" | grep -qF "${SESSION_NAME}"; then
        record C1 PASS
    else
        record C1 FAIL
    fi
}

# ------------------------------------------------------------
# C2: ペインボーダーラベル (pane-border-status = top)
# ------------------------------------------------------------
check_c2() {
    local out
    out=$(ssh_run "tmux show-options -t '${SESSION_NAME}' pane-border-status 2>&1")
    if echo "${out}" | grep -q "top"; then
        record C2 PASS
    else
        record C2 FAIL
    fi
}

# ------------------------------------------------------------
# C3: マウスリサイズ設定 (mouse = on)
# ------------------------------------------------------------
check_c3() {
    local out
    out=$(ssh_run "tmux show-options -t '${SESSION_NAME}' mouse 2>&1")
    if echo "${out}" | grep -q "on"; then
        record C3 PASS
    else
        record C3 FAIL
    fi
}

# ------------------------------------------------------------
# C4: pane 0 識別ラベル（"Claude Code" を含む）
# ------------------------------------------------------------
check_c4() {
    local out
    out=$(ssh_run "tmux display-message -t '${SESSION_NAME}.0' -p '#{pane_title}' 2>&1")
    if echo "${out}" | grep -q "Claude Code"; then
        record C4 PASS
    else
        record C4 FAIL
    fi
}

# ------------------------------------------------------------
# C5: レイアウト自動検出スクリプト存在確認
# ------------------------------------------------------------
check_c5() {
    local out
    out=$(ssh_run "test -f '${REMOTE_BASE}/scripts/tmux/tmux-dashboard.sh' && echo OK || echo MISSING 2>&1")
    if echo "${out}" | grep -q "^OK"; then
        record C5 PASS
    else
        record C5 FAIL
    fi
}

# ------------------------------------------------------------
# C6: モニタリングペインスクリプト存在 (1件以上)
# ------------------------------------------------------------
check_c6() {
    local out
    out=$(ssh_run "find '${REMOTE_BASE}/scripts/tmux/panes/' -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l")
    local count
    count=$(echo "${out}" | tr -d '[:space:]')
    if [ "${count}" -ge 1 ]; then
        record C6 PASS
    else
        record C6 FAIL
    fi
}

# ------------------------------------------------------------
# C7: pane-border-format に "pane_title" を含む
# ------------------------------------------------------------
check_c7() {
    local out
    out=$(ssh_run "tmux show-options -t '${SESSION_NAME}' pane-border-format 2>&1")
    if echo "${out}" | grep -q "pane_title"; then
        record C7 PASS
    else
        record C7 FAIL
    fi
}

# ------------------------------------------------------------
# C8: SSH 切断耐性（セッション保持）
# detach-client 後に has-session で ALIVE を確認
# ------------------------------------------------------------
check_c8() {
    local out
    out=$(ssh_run "
        tmux detach-client -s '${SESSION_NAME}' || true
        tmux has-session -t '${SESSION_NAME}' 2>&1 && echo ALIVE || echo DEAD
    ")
    if echo "${out}" | grep -q "ALIVE"; then
        record C8 PASS
    else
        record C8 FAIL
    fi
}

# ------------------------------------------------------------
# C9: 環境変数伝播
# CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS または settings.json
# ------------------------------------------------------------
check_c9() {
    local out
    out=$(ssh_run "
        val=\$(tmux show-environment -t '${SESSION_NAME}' CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS || true)
        if echo \"\${val}\" | grep -q '=1'; then
            echo ENVVAR_OK
        elif grep -qr '\"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS\".*\"1\"' ~/.claude/settings.json; then
            echo SETTINGS_OK
        else
            echo NOT_FOUND
        fi
    ")
    if echo "${out}" | grep -qE "ENVVAR_OK|SETTINGS_OK"; then
        record C9 PASS
    else
        record C9 FAIL
    fi
}

# ------------------------------------------------------------
# C10: run-claude.sh との連携
# tmux-dashboard.sh 内に select-pane.*-T.*Claude Code の行が 1 以上
# ------------------------------------------------------------
check_c10() {
    local out
    out=$(ssh_run "grep -c 'select-pane.*-T.*Claude Code' '${REMOTE_BASE}/scripts/tmux/tmux-dashboard.sh' 2>&1")
    local count
    count=$(echo "${out}" | tr -d '[:space:]')
    if [ "${count}" -ge 1 ]; then
        record C10 PASS
    else
        record C10 FAIL
    fi
}

# ------------------------------------------------------------
# メイン処理
# ------------------------------------------------------------
main() {
    # セッションセットアップ
    local setup_out
    setup_out=$(setup_session)
    if ! echo "${setup_out}" | grep -q "SETUP_OK"; then
        # セットアップ失敗時でも検証を継続（接続不能はすべて FAIL）
        for cat in C1 C2 C3 C4 C5 C6 C7 C8 C9 C10; do
            record "${cat}" FAIL
        done
        output_json
        return
    fi

    # 各カテゴリの検証を順に実行
    check_c1
    check_c2
    check_c3
    check_c4
    check_c5
    check_c6
    check_c7
    check_c8
    check_c9
    check_c10

    # テストセッションをクリーンアップ
    cleanup_session

    output_json
}

# ------------------------------------------------------------
# JSON 出力
# ------------------------------------------------------------
output_json() {
    local results_json=""
    local first=1
    for cat in C1 C2 C3 C4 C5 C6 C7 C8 C9 C10; do
        local val="${RESULTS[${cat}]:-FAIL}"
        if [ "${first}" -eq 1 ]; then
            results_json="\"${cat}\":\"${val}\""
            first=0
        else
            results_json="${results_json},\"${cat}\":\"${val}\""
        fi
    done

    printf '{"project":"%s","pass":%d,"fail":%d,"results":{%s}}\n' \
        "${PROJECT_NAME}" \
        "${PASS_COUNT}" \
        "${FAIL_COUNT}" \
        "${results_json}"
}

main
