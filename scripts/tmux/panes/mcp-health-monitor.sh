#!/usr/bin/env bash
# ============================================================
# mcp-health-monitor.sh - MCP サーバーヘルスモニタリング
# ============================================================
# 更新間隔: 30秒
# ============================================================

REFRESH="${TMUX_PANE_REFRESH_MCP:-30}"

while true; do
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  MCP Health Monitor"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # .mcp.json を探す（カレントディレクトリ → ホーム）
    MCP_CONFIG=""
    if [ -f ".mcp.json" ]; then
        MCP_CONFIG=".mcp.json"
    elif [ -f "$HOME/.mcp.json" ]; then
        MCP_CONFIG="$HOME/.mcp.json"
    fi

    if [ -z "$MCP_CONFIG" ]; then
        echo "  ⚠️  .mcp.json が見つかりません"
        echo ""
        echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
        sleep "$REFRESH"
        continue
    fi

    if ! command -v jq &>/dev/null; then
        echo "  ⚠️  jq が必要です"
        echo ""
        echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
        sleep "$REFRESH"
        continue
    fi

    # MCP サーバー一覧取得
    MCP_SERVERS=$(jq -r '.mcpServers | keys[]' "$MCP_CONFIG" 2>/dev/null || echo "")

    if [ -z "$MCP_SERVERS" ]; then
        echo "  MCPサーバー未設定"
        echo ""
        echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
        sleep "$REFRESH"
        continue
    fi

    OK=0
    FAIL=0
    TOTAL=0

    while IFS= read -r mcp; do
        ((TOTAL++))
        COMMAND=$(jq -r ".mcpServers[\"$mcp\"].command" "$MCP_CONFIG" 2>/dev/null || echo "unknown")

        if [ "$COMMAND" = "npx" ]; then
            if command -v npx &>/dev/null; then
                echo -e "  \033[32m✓\033[0m $mcp"
                ((OK++))
            else
                echo -e "  \033[31m✗\033[0m $mcp (npx not found)"
                ((FAIL++))
            fi
        elif command -v "$COMMAND" &>/dev/null; then
            echo -e "  \033[32m✓\033[0m $mcp"
            ((OK++))
        else
            echo -e "  \033[31m✗\033[0m $mcp ($COMMAND)"
            ((FAIL++))
        fi
    done <<< "$MCP_SERVERS"

    echo ""
    if [ "$FAIL" -gt 0 ]; then
        echo -e "  \033[33m${OK}/${TOTAL} OK\033[0m | \033[31m${FAIL} FAIL\033[0m"
        # 異常検知（ペインボーダーを赤に）
        if [ -n "${TMUX_PANE:-}" ]; then
            tmux select-pane -t "$TMUX_PANE" -P 'bg=colour52' 2>/dev/null || true
        fi
    else
        echo -e "  \033[32m${OK}/${TOTAL} OK\033[0m"
        # 異常解除
        if [ -n "${TMUX_PANE:-}" ]; then
            tmux select-pane -t "$TMUX_PANE" -P 'bg=default' 2>/dev/null || true
        fi
    fi

    echo ""
    echo -e "\033[90m更新: $(date '+%H:%M:%S') | 間隔: ${REFRESH}s\033[0m"
    sleep "$REFRESH"
done
