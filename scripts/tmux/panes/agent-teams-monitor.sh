#!/usr/bin/env bash
# ============================================================
# agent-teams-monitor.sh - Agent Teams 状態モニタリング
# ============================================================
# 更新間隔: 5秒
# ============================================================

REFRESH="${TMUX_PANE_REFRESH_AGENT:-5}"
TEAMS_DIR="$HOME/.claude/teams"
TASKS_DIR="$HOME/.claude/tasks"

get_color_code() {
    local color="$1"
    case "$color" in
        red) echo "31" ;;
        green) echo "32" ;;
        yellow) echo "33" ;;
        blue) echo "34" ;;
        magenta) echo "35" ;;
        cyan) echo "36" ;;
        white) echo "37" ;;
        *) echo "37" ;;
    esac
}

while true; do
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Agent Teams Monitor"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ ! -d "$TEAMS_DIR" ]; then
        echo "  No active teams"
        echo ""
        echo "  Teams dir: ${TEAMS_DIR}"
        echo "  (not found)"
        echo ""
        echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
        sleep "$REFRESH"
        continue
    fi

    TEAM_COUNT=0

    for team_dir in "$TEAMS_DIR"/*/; do
        [ -d "$team_dir" ] || continue
        TEAM_NAME=$(basename "$team_dir")
        CONFIG_FILE="${team_dir}config.json"

        if [ ! -f "$CONFIG_FILE" ]; then
            continue
        fi

        ((TEAM_COUNT++))

        echo -e "  \033[36m■ ${TEAM_NAME}\033[0m"

        # メンバー情報取得
        if command -v jq &>/dev/null; then
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                icon=$(echo "$line" | jq -r '.icon // "•"')
                name=$(echo "$line" | jq -r '.name')
                color=$(echo "$line" | jq -r '.color // "white"')
                color_code=$(get_color_code "$color")
                echo -e "    \033[${color_code}m${icon} ${name}\033[0m"
            done < <(jq -c '.members[]?' "$CONFIG_FILE" 2>/dev/null)
            _MEMBER_COUNT=$(jq '.members | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
            if [ "$_MEMBER_COUNT" = "0" ] || [ "$_MEMBER_COUNT" = "null" ]; then
                echo "    (no members)"
            fi
        else
            _MEMBER_COUNT="?"
            echo "    (jq required for details)"
        fi

        # タスク情報
        TEAM_TASKS_DIR="${TASKS_DIR}/${TEAM_NAME}"
        if [ -d "$TEAM_TASKS_DIR" ]; then
            TASK_FILES=$(find "$TEAM_TASKS_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
            echo "    Tasks: ${TASK_FILES}"
        fi

        echo ""
    done

    if [ "$TEAM_COUNT" -eq 0 ]; then
        echo "  No active teams"
        echo ""
        echo -e "  \033[90mAgent Teams は TeamCreate で\033[0m"
        echo -e "  \033[90m起動時に自動作成されます\033[0m"
    else
        echo -e "  \033[32mActive: ${TEAM_COUNT} team(s)\033[0m"
    fi

    echo ""
    echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
    sleep "$REFRESH"
done
