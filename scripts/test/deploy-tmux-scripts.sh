#!/usr/bin/env bash
# scripts/test/deploy-tmux-scripts.sh
# tmux スクリプト群を指定プロジェクトに SSH 経由で展開する
# 使用: bash deploy-tmux-scripts.sh <PROJECT_NAME>
set -euo pipefail

LINUX_HOST="kensan@kensan1969"
LINUX_BASE="/mnt/LinuxHDD"
PROJECT_NAME="${1:?ERROR: PROJECT_NAME が指定されていません}"
REMOTE_BASE="${LINUX_BASE}/${PROJECT_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_SRC="${SCRIPT_DIR}/../tmux"

SUCCESS_COUNT=0
FAIL_COUNT=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  tmux スクリプト展開"
echo "  PROJECT: ${PROJECT_NAME}"
echo "  REMOTE : ${LINUX_HOST}:${REMOTE_BASE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# -----------------------------------------------------------------
# リモートディレクトリ作成
# -----------------------------------------------------------------
echo ">> リモートディレクトリを作成しています..."
ssh "${LINUX_HOST}" "mkdir -p \
    '${REMOTE_BASE}/scripts/tmux' \
    '${REMOTE_BASE}/scripts/tmux/panes' \
    '${REMOTE_BASE}/scripts/tmux/layouts'"
echo "   OK"
echo ""

# -----------------------------------------------------------------
# transfer_file <local_path> <remote_path>
#   base64 stdin パイプ方式でファイルを転送する
# -----------------------------------------------------------------
transfer_file() {
    local local_path="$1"
    local remote_path="$2"
    local filename
    filename="$(basename "${local_path}")"

    if base64 < "${local_path}" | ssh "${LINUX_HOST}" "base64 -d > '${remote_path}'" 2>/dev/null; then
        echo "  OK ${filename}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        echo "  FAIL ${filename}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# -----------------------------------------------------------------
# tmux-dashboard.sh / tmux-install.sh
# -----------------------------------------------------------------
echo ">> メインスクリプトを転送しています..."
for f in tmux-dashboard.sh tmux-install.sh; do
    transfer_file "${TMUX_SRC}/${f}" "${REMOTE_BASE}/scripts/tmux/${f}" || true
done
echo ""

# -----------------------------------------------------------------
# panes/*.sh
# -----------------------------------------------------------------
echo ">> panes/ スクリプトを転送しています..."
for f in "${TMUX_SRC}/panes/"*.sh; do
    [ -f "${f}" ] || continue
    transfer_file "${f}" "${REMOTE_BASE}/scripts/tmux/panes/$(basename "${f}")" || true
done
echo ""

# -----------------------------------------------------------------
# layouts/*.conf / layouts/*.template
# -----------------------------------------------------------------
echo ">> layouts/ ファイルを転送しています..."
for f in "${TMUX_SRC}/layouts/"*.conf "${TMUX_SRC}/layouts/"*.template; do
    [ -f "${f}" ] || continue
    transfer_file "${f}" "${REMOTE_BASE}/scripts/tmux/layouts/$(basename "${f}")" || true
done
echo ""

# -----------------------------------------------------------------
# 実行権限付与 (.sh のみ)
# -----------------------------------------------------------------
echo ">> 実行権限を付与しています (.sh のみ)..."
ssh "${LINUX_HOST}" "
    find '${REMOTE_BASE}/scripts/tmux' -name '*.sh' -exec chmod +x {} \;
" && echo "   OK" || echo "   WARN: chmod に失敗しました"
echo ""

# -----------------------------------------------------------------
# 結果サマリー
# -----------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  完了: 成功 ${SUCCESS_COUNT} / 失敗 ${FAIL_COUNT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "${FAIL_COUNT}" -gt 0 ]; then
    echo "  WARNING: ${FAIL_COUNT} 個のファイルが転送に失敗しました。"
    exit 1
fi
echo ""
