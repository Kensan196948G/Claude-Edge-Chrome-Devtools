#!/usr/bin/env bash
# ============================================================
# on-startup.sh - Claude Code 起動時の自動ヘルスチェック
# ============================================================

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 起動時ヘルスチェック"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. 環境変数確認
echo "📋 環境変数:"
echo "  CLAUDE_CHROME_DEBUG_PORT: ${CLAUDE_CHROME_DEBUG_PORT:-未設定}"
echo "  MCP_CHROME_DEBUG_PORT: ${MCP_CHROME_DEBUG_PORT:-未設定}"
echo "  CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: ${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-未設定}"
echo ""

# 2. DevTools 接続確認
echo "📋 DevTools 接続:"
PORT="${MCP_CHROME_DEBUG_PORT:-${CLAUDE_CHROME_DEBUG_PORT:-9222}}"
if curl -sf --connect-timeout 2 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
    echo "  ✅ DevTools 接続成功 (ポート: ${PORT})"
else
    echo "  ❌ DevTools 接続失敗 (ポート: ${PORT})"
fi
echo ""

# 3. MCP サーバー接続確認（8個）
echo "📋 MCP サーバー:"
MCP_SERVERS=("brave-search" "context7" "github" "memory" "playwright" "plugin:claude-mem:mem-search" "puppeteer" "sequential-thinking")

for mcp in "${MCP_SERVERS[@]}"; do
    # .mcp.json に設定されているか確認
    if [ -f ".mcp.json" ] && command -v jq &>/dev/null; then
        if jq -e ".mcpServers[\"$mcp\"]" .mcp.json >/dev/null 2>&1; then
            echo "  ✅ $mcp"
        else
            echo "  ⚠️  $mcp (未設定)"
        fi
    else
        echo "  ？ $mcp (確認不可: .mcp.json or jq なし)"
    fi
done
echo ""

# 4. Memory MCP からプロジェクトコンテキスト読み込み
# context-loader.sh を呼び出し（存在する場合）
if [ -f ".claude/hooks/lib/context-loader.sh" ]; then
    bash .claude/hooks/lib/context-loader.sh "${PWD##*/}" 2>&1 | head -5
else
    echo "📋 Memory MCP コンテキスト復元:"
    echo "  ℹ️  context-loader.sh が見つかりません"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ ヘルスチェック完了"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
