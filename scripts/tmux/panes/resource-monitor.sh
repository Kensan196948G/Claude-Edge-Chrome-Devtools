#!/usr/bin/env bash
# ============================================================
# resource-monitor.sh - リソース使用状況モニタリング
# ============================================================
# 更新間隔: 15秒
# ============================================================

REFRESH="${TMUX_PANE_REFRESH_RESOURCE:-15}"

while true; do
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Resource Monitor"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # CPU ロードアベレージ
    if [ -f /proc/loadavg ]; then
        LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
        echo "  CPU Load: ${LOAD}"
    elif command -v uptime &>/dev/null; then
        LOAD=$(uptime | sed 's/.*load average: //')
        echo "  CPU Load: ${LOAD}"
    fi

    echo ""

    # メモリ使用量
    if command -v free &>/dev/null; then
        MEM_INFO=$(free -h 2>/dev/null | awk '/^Mem:/ {printf "  Memory: %s / %s (%s free)", $3, $2, $4}')
        echo "$MEM_INFO"
    fi

    echo ""

    # ディスク使用量
    echo "  Disk:"
    if df -h / &>/dev/null; then
        ROOT_USAGE=$(df -h / 2>/dev/null | awk 'NR==2 {printf "    / : %s / %s (%s)", $3, $2, $5}')
        echo "$ROOT_USAGE"
    fi
    if df -h /mnt/LinuxHDD &>/dev/null 2>&1; then
        HDD_USAGE=$(df -h /mnt/LinuxHDD 2>/dev/null | awk 'NR==2 {printf "    HDD: %s / %s (%s)", $3, $2, $5}')
        echo "$HDD_USAGE"
    fi

    echo ""

    # Claude / Node プロセス数
    CLAUDE_PROCS=$(pgrep -c -f "claude" 2>/dev/null || echo "0")
    NODE_PROCS=$(pgrep -c -f "node" 2>/dev/null || echo "0")
    echo "  Procs: claude=${CLAUDE_PROCS} node=${NODE_PROCS}"

    echo ""
    echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
    sleep "$REFRESH"
done
