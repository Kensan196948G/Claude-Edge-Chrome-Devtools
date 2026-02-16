#!/usr/bin/env bash
# ============================================================
# MCP Auto-Setup Script
# Claude Code 起動前に必要な MCP サーバーを自動設定
# ============================================================

set -euo pipefail

# 引数: プロジェクトディレクトリ、GitHub Token (base64)、Brave API Key
PROJECT_DIR="${1:-$PWD}"
GITHUB_TOKEN_B64="${2:-}"
BRAVE_API_KEY="${3:-}"

MCP_CONFIG="${PROJECT_DIR}/.mcp.json"
MCP_BACKUP="${PROJECT_DIR}/.mcp.json.backup.$(date +%Y%m%d-%H%M%S)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔌 MCP Auto-Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# jq インストール確認
if ! command -v jq &>/dev/null; then
    echo "⚠️  jq がインストールされていません。MCP設定をスキップします。"
    exit 0
fi

# .mcp.json バックアップ
if [ -f "$MCP_CONFIG" ]; then
    cp "$MCP_CONFIG" "$MCP_BACKUP"
    echo "✅ 既存の .mcp.json をバックアップ: $(basename $MCP_BACKUP)"
else
    echo "ℹ️  .mcp.json が存在しません。新規作成します。"
    echo '{"mcpServers":{}}' > "$MCP_CONFIG"
fi

# GitHub Token デコード
GITHUB_TOKEN=""
if [ -n "$GITHUB_TOKEN_B64" ]; then
    GITHUB_TOKEN=$(echo "$GITHUB_TOKEN_B64" | base64 -d 2>/dev/null || echo "")
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "✅ GitHub Token を取得しました"
    fi
fi

# 現在の設定を読み込み
CURRENT_CONFIG=$(cat "$MCP_CONFIG")

# 必要な MCP サーバー定義
declare -A MCP_SERVERS

# 1. brave-search
if [ -n "$BRAVE_API_KEY" ]; then
    MCP_SERVERS["brave-search"]=$(cat <<EOF
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-brave-search"],
  "env": {
    "BRAVE_API_KEY": "$BRAVE_API_KEY"
  }
}
EOF
)
else
    echo "⚠️  Brave API Key が設定されていません。brave-search MCP はスキップします。"
fi

# 2. puppeteer
MCP_SERVERS["puppeteer"]=$(cat <<'EOF'
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-puppeteer"],
  "env": {
    "PUPPETEER_LAUNCH_OPTIONS": "{\"headless\": false, \"timeout\": 30000}",
    "ALLOW_DANGEROUS": "false"
  }
}
EOF
)

# 3. context7
MCP_SERVERS["context7"]=$(cat <<'EOF'
{
  "command": "npx",
  "args": ["-y", "@context7/mcp"]
}
EOF
)

# 4. github (Token付き)
if [ -n "$GITHUB_TOKEN" ]; then
    MCP_SERVERS["github"]=$(cat <<EOF
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-github"],
  "env": {
    "GITHUB_PERSONAL_ACCESS_TOKEN": "$GITHUB_TOKEN"
  }
}
EOF
)
else
    echo "⚠️  GitHub Token が設定されていません。github MCP はスキップします。"
fi

# 5. memory
MCP_SERVERS["memory"]=$(cat <<'EOF'
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-memory"]
}
EOF
)

# 6. playwright
MCP_SERVERS["playwright"]=$(cat <<'EOF'
{
  "command": "npx",
  "args": ["-y", "@playwright/mcp@latest"]
}
EOF
)

# 7. plugin:claude-mem:mem-search
MCP_SERVERS["plugin:claude-mem:mem-search"]=$(cat <<'EOF'
{
  "command": "npx",
  "args": ["-y", "@anthropic/claude-mem"]
}
EOF
)

# 8. sequential-thinking
MCP_SERVERS["sequential-thinking"]=$(cat <<'EOF'
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
}
EOF
)

# 各 MCP サーバーをチェック・追加
ADDED_COUNT=0
SKIPPED_COUNT=0

for server_name in "${!MCP_SERVERS[@]}"; do
    # 既存チェック
    if echo "$CURRENT_CONFIG" | jq -e ".mcpServers[\"$server_name\"]" >/dev/null 2>&1; then
        echo "⏭️  $server_name (既に設定済み)"
        ((SKIPPED_COUNT++))
    else
        echo "➕ $server_name を追加中..."
        SERVER_CONFIG="${MCP_SERVERS[$server_name]}"
        CURRENT_CONFIG=$(echo "$CURRENT_CONFIG" | jq ".mcpServers[\"$server_name\"] = $SERVER_CONFIG")
        ((ADDED_COUNT++))
    fi
done

# 更新された設定を保存
echo "$CURRENT_CONFIG" | jq '.' > "$MCP_CONFIG"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ MCP セットアップ完了"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  追加: ${ADDED_COUNT}個"
echo "  スキップ: ${SKIPPED_COUNT}個"
echo ""

# 設定されている MCP サーバー一覧
echo "📋 設定済み MCP サーバー:"
echo "$CURRENT_CONFIG" | jq -r '.mcpServers | keys[]' | while read -r server; do
    echo "   • $server"
done
echo ""
