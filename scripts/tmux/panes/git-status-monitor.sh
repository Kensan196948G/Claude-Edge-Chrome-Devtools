#!/usr/bin/env bash
# ============================================================
# git-status-monitor.sh - Git 状態モニタリング
# ============================================================
# 引数: $1 - プロジェクト名（表示用）
# 更新間隔: 10秒
# ============================================================

PROJECT_NAME="${1:-$(basename "$(pwd)")}"
REFRESH="${TMUX_PANE_REFRESH_GIT:-10}"

while true; do
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Git Status: ${PROJECT_NAME}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if ! git rev-parse --git-dir &>/dev/null; then
        echo "  ⚠️  Git リポジトリではありません"
        echo ""
        echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
        sleep "$REFRESH"
        continue
    fi

    # ブランチ名
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    if [ -z "$BRANCH" ]; then
        BRANCH="HEAD:$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
    fi
    echo -e "  🌿 \033[36m${BRANCH}\033[0m"
    echo ""

    # ファイル状態カウント
    MODIFIED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    [ "$STAGED" -gt 0 ] && echo -e "  \033[32m+${STAGED} staged\033[0m"
    [ "$MODIFIED" -gt 0 ] && echo -e "  \033[33m~${MODIFIED} modified\033[0m"
    [ "$UNTRACKED" -gt 0 ] && echo -e "  \033[31m?${UNTRACKED} untracked\033[0m"

    if [ "$STAGED" -eq 0 ] && [ "$MODIFIED" -eq 0 ] && [ "$UNTRACKED" -eq 0 ]; then
        echo -e "  \033[32m✓ clean\033[0m"
    fi

    echo ""

    # 直近3コミット
    echo "  Recent commits:"
    git log --oneline -3 --format="  %C(yellow)%h%C(reset) %s" 2>/dev/null || echo "  (no commits)"

    echo ""
    echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
    sleep "$REFRESH"
done
