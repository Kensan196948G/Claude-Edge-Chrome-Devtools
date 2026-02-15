#!/usr/bin/env bash
# ============================================================
# mcp-health.sh - MCP サーバー接続確認
# ============================================================

set -euo pipefail

MCP_CONFIG=".mcp.json"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔌 MCP ヘルスチェック"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# .mcp.json 存在確認
if [ ! -f "$MCP_CONFIG" ]; then
    echo "❌ .mcp.json が見つかりません"
    echo ""
    echo "💡 MCP セットアップを実行してください:"
    echo "   bash scripts/mcp/setup-mcp.sh"
    echo ""
    exit 1
fi

# jq 存在確認
if ! command -v jq &>/dev/null; then
    echo "❌ jq がインストールされていません"
    echo ""
    echo "💡 jq をインストールしてください:"
    echo "   sudo apt-get install jq   # Debian/Ubuntu"
    echo "   sudo yum install jq       # RHEL/CentOS"
    echo ""
    exit 1
fi

# 設定されている MCP サーバー一覧
MCP_SERVERS=$(jq -r '.mcpServers | keys[]' "$MCP_CONFIG" 2>/dev/null || echo "")

if [ -z "$MCP_SERVERS" ]; then
    echo "⚠️  .mcp.json に MCP サーバーが設定されていません"
    echo ""
    exit 0
fi

TOTAL=0
OK=0
WARN=0
FAILED=0

for mcp in $MCP_SERVERS; do
    ((TOTAL++))

    # コマンド取得
    COMMAND=$(jq -r ".mcpServers[\"$mcp\"].command" "$MCP_CONFIG" 2>/dev/null || echo "unknown")
    ARGS=$(jq -r ".mcpServers[\"$mcp\"].args[]?" "$MCP_CONFIG" 2>/dev/null | tr '\n' ' ' || echo "")

    # ヘルスチェック
    if [ "$COMMAND" = "npx" ]; then
        # npx コマンドの場合は、npx 自体が利用可能か確認
        if command -v npx &>/dev/null; then
            echo "  ✅ $mcp (command: npx $ARGS)"
            ((OK++))
        else
            echo "  ❌ $mcp (npx not found)"
            ((FAILED++))
        fi
    elif command -v "$COMMAND" &>/dev/null; then
        echo "  ✅ $mcp (command: $COMMAND)"
        ((OK++))
    else
        echo "  ❌ $mcp (command not found: $COMMAND)"
        ((FAILED++))
    fi

    # 環境変数チェック（オプション）
    ENV_VARS=$(jq -r ".mcpServers[\"$mcp\"].env // {} | keys[]" "$MCP_CONFIG" 2>/dev/null || echo "")
    if [ -n "$ENV_VARS" ]; then
        for env_var in $ENV_VARS; do
            ENV_VALUE=$(jq -r ".mcpServers[\"$mcp\"].env[\"$env_var\"]" "$MCP_CONFIG" 2>/dev/null || echo "")
            if [ -z "$ENV_VALUE" ] || [ "$ENV_VALUE" = "null" ]; then
                echo "     ⚠️  環境変数 $env_var が未設定または空"
                ((WARN++))
            fi
        done
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 結果: 合計 ${TOTAL}個 | 成功 ${OK}個 | 警告 ${WARN}個 | 失敗 ${FAILED}個"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $FAILED -gt 0 ]; then
    echo "⚠️  一部の MCP サーバーが利用できません"
    echo ""
    echo "💡 npx をインストールしてください:"
    echo "   npm install -g npx"
    echo ""
    exit 1
fi

if [ $WARN -gt 0 ]; then
    echo "⚠️  一部の MCP サーバーで環境変数が未設定です"
    echo "   .mcp.json の env セクションを確認してください"
    echo ""
fi

echo "✅ すべての MCP サーバーが利用可能です"
exit 0
