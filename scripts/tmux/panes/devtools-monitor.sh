#!/usr/bin/env bash
# ============================================================
# devtools-monitor.sh - DevTools 接続状態モニタリング
# ============================================================
# 引数: $1 - DevTools ポート番号 (デフォルト: 9222)
# 更新間隔: 5秒
# ============================================================

PORT="${1:-${MCP_CHROME_DEBUG_PORT:-${CLAUDE_CHROME_DEBUG_PORT:-9222}}}"
REFRESH="${TMUX_PANE_REFRESH_DEVTOOLS:-5}"

while true; do
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  DevTools Monitor [:${PORT}]"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # バージョン情報取得
    VERSION_JSON=$(curl -sf --connect-timeout 3 "http://127.0.0.1:${PORT}/json/version" 2>/dev/null || echo "")

    if [ -n "$VERSION_JSON" ]; then
        # 接続成功
        BROWSER=$(echo "$VERSION_JSON" | jq -r '.Browser // "Unknown"' 2>/dev/null || echo "Unknown")
        PROTOCOL=$(echo "$VERSION_JSON" | jq -r '."Protocol-Version" // "?"' 2>/dev/null || echo "?")
        _USER_AGENT=$(echo "$VERSION_JSON" | jq -r '."User-Agent" // ""' 2>/dev/null || echo "")

        echo -e "  \033[32m● CONNECTED\033[0m"
        echo ""
        echo "  Browser:  ${BROWSER}"
        echo "  Protocol: ${PROTOCOL}"

        # タブ数取得
        TABS_JSON=$(curl -sf --connect-timeout 3 "http://127.0.0.1:${PORT}/json/list" 2>/dev/null || echo "[]")
        TAB_COUNT=$(echo "$TABS_JSON" | jq 'length' 2>/dev/null || echo "0")
        echo "  Tabs:     ${TAB_COUNT}"

        # WebSocket エンドポイント
        WS_URL=$(echo "$VERSION_JSON" | jq -r '.webSocketDebuggerUrl // "N/A"' 2>/dev/null || echo "N/A")
        if [ "$WS_URL" != "N/A" ] && [ "$WS_URL" != "null" ]; then
            echo "  WS:       OK"
        fi

        # 異常検知解除（ペインボーダーを通常色に）
        if [ -n "${TMUX_PANE:-}" ]; then
            tmux select-pane -t "$TMUX_PANE" -P 'bg=default' 2>/dev/null || true
        fi
    else
        # 接続失敗
        echo -e "  \033[31m● DISCONNECTED\033[0m"
        echo ""
        echo "  Port ${PORT} に接続できません"
        echo ""
        echo "  確認事項:"
        echo "  - ブラウザが起動しているか"
        echo "  - SSHポートフォワードが有効か"
        echo "  - ポート番号が正しいか"

        # 異常検知（ペインボーダーを赤に）
        if [ -n "${TMUX_PANE:-}" ]; then
            tmux select-pane -t "$TMUX_PANE" -P 'bg=colour52' 2>/dev/null || true
        fi
    fi

    echo ""
    echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
    sleep "$REFRESH"
done
