#!/usr/bin/env bash
# ============================================================
# test-devtools-connection.sh
# Linux側でXサーバ不要のDevTools接続テストスクリプト
# ============================================================

set -euo pipefail

# ===== 設定 =====
DEFAULT_PORT="${MCP_CHROME_DEBUG_PORT:-${CLAUDE_CHROME_DEBUG_PORT:-9222}}"
PORT="${1:-$DEFAULT_PORT}"

# ===== カラー出力 =====
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===== ヘルパー関数 =====
print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}📋 $1${NC}"
}

# ===== メイン処理 =====
print_header "🔍 DevTools 接続テスト (ポート: ${PORT})"

# ===== 1. 基本接続確認 =====
print_info "1. 基本接続確認"
echo "   エンドポイント: http://127.0.0.1:${PORT}/json/version"
echo ""

if ! curl -sf --connect-timeout 3 http://127.0.0.1:${PORT}/json/version > /dev/null 2>&1; then
    print_error "接続失敗 - DevToolsポート ${PORT} が応答していません"
    echo ""
    echo "以下を確認してください："
    echo "  1. SSHポートフォワーディングが有効か: ssh -R ${PORT}:127.0.0.1:${PORT}"
    echo "  2. Windows側でブラウザが起動しているか"
    echo "  3. 環境変数が設定されているか: MCP_CHROME_DEBUG_PORT=${PORT}"
    echo ""
    exit 1
fi

print_success "基本接続成功"
echo ""

# ===== 2. バージョン情報取得 =====
print_info "2. バージョン情報"
VERSION_JSON=$(curl -s http://127.0.0.1:${PORT}/json/version)

if command -v jq &> /dev/null; then
    echo "$VERSION_JSON" | jq '.'

    BROWSER=$(echo "$VERSION_JSON" | jq -r '.Browser // "N/A"')
    PROTOCOL=$(echo "$VERSION_JSON" | jq -r '."Protocol-Version" // "N/A"')
    USER_AGENT=$(echo "$VERSION_JSON" | jq -r '."User-Agent" // "N/A"')
    WS_DEBUG_URL=$(echo "$VERSION_JSON" | jq -r '.webSocketDebuggerUrl // "N/A"')

    echo ""
    print_success "ブラウザ: ${BROWSER}"
    print_success "Protocol: ${PROTOCOL}"
    echo "   User-Agent: ${USER_AGENT}"
else
    print_warning "jqがインストールされていません（詳細解析不可）"
    echo "$VERSION_JSON"
    echo ""
    echo "jqをインストールすると詳細情報が表示されます："
    echo "  sudo apt-get install jq  # Debian/Ubuntu"
    echo "  sudo yum install jq      # CentOS/RHEL"
fi
echo ""

# ===== 3. タブ一覧取得 =====
print_info "3. 開いているタブ一覧"
TABS_JSON=$(curl -s http://127.0.0.1:${PORT}/json/list)

if command -v jq &> /dev/null; then
    TAB_COUNT=$(echo "$TABS_JSON" | jq 'length')
    print_success "タブ数: ${TAB_COUNT}"
    echo ""

    if [ "$TAB_COUNT" -gt 0 ]; then
        echo "$TABS_JSON" | jq -r '.[] | "  - [\(.type)] \(.title // "Untitled") (\(.url))"'
    else
        print_warning "タブが開いていません"
    fi
else
    print_warning "jqがインストールされていません（タブ数カウント不可）"
    echo "$TABS_JSON" | head -n 5
fi
echo ""

# ===== 4. WebSocketエンドポイント確認 =====
print_info "4. WebSocket接続エンドポイント"

if command -v jq &> /dev/null && [ "$TAB_COUNT" -gt 0 ]; then
    WS_URL=$(echo "$TABS_JSON" | jq -r '.[0].webSocketDebuggerUrl // "N/A"')
    if [ "$WS_URL" != "N/A" ] && [ -n "$WS_URL" ]; then
        print_success "WebSocket URL: ${WS_URL}"
        echo ""
        echo "   このURLを使用してDevTools Protocolに接続できます"
    else
        print_warning "WebSocketエンドポイントが見つかりません"
    fi
else
    print_warning "jqがインストールされていないか、タブが開いていません"
fi
echo ""

# ===== 5. MCP環境変数確認 =====
print_info "5. MCP環境変数確認"

if [ -n "${MCP_CHROME_DEBUG_PORT:-}" ]; then
    print_success "MCP_CHROME_DEBUG_PORT=${MCP_CHROME_DEBUG_PORT}"
else
    print_warning "MCP_CHROME_DEBUG_PORT が設定されていません"
fi

if [ -n "${CLAUDE_CHROME_DEBUG_PORT:-}" ]; then
    print_success "CLAUDE_CHROME_DEBUG_PORT=${CLAUDE_CHROME_DEBUG_PORT}"
else
    print_warning "CLAUDE_CHROME_DEBUG_PORT が設定されていません"
fi
echo ""

# ===== 6. MCP Chrome DevTools利用可能性チェック =====
print_info "6. MCP Chrome DevTools 利用可能性"

if command -v claude &> /dev/null; then
    print_success "Claude Code CLIがインストールされています"

    # .mcp.json確認
    if [ -f ".mcp.json" ]; then
        print_success ".mcp.json が見つかりました"

        if command -v jq &> /dev/null; then
            if jq -e '.mcpServers."puppeteer"' .mcp.json > /dev/null 2>&1; then
                print_success "puppeteer MCPサーバーが設定されています"
            else
                print_warning "puppeteer MCPサーバーが .mcp.json に見つかりません"
            fi
        fi
    else
        print_warning ".mcp.json が見つかりません（カレントディレクトリ）"
    fi
else
    print_warning "Claude Code CLIがインストールされていません"
fi
echo ""

# ===== 7. ポート範囲チェック =====
print_info "7. 推奨ポート範囲確認 (9222-9229)"

EXPECTED_PORTS=(9222 9223 9224 9225 9226 9227 9228 9229)
if [[ " ${EXPECTED_PORTS[@]} " =~ " ${PORT} " ]]; then
    print_success "ポート ${PORT} は推奨範囲内です"
else
    print_warning "ポート ${PORT} は推奨範囲外です（推奨: 9222-9229）"
fi
echo ""

# ===== 総合判定 =====
print_header "📊 テスト結果サマリー"

echo "接続状態: ✅ 正常"
echo "ポート番号: ${PORT}"

if command -v jq &> /dev/null; then
    echo "ブラウザ: ${BROWSER}"
    echo "Protocol: ${PROTOCOL}"
    echo "タブ数: ${TAB_COUNT}"
fi

echo ""
print_success "DevTools接続テスト完了 - すべて正常です"
print_header "🎉 テスト成功"

# ===== 次のステップ案内 =====
echo "次のステップ："
echo "  1. Claude Codeを起動: ./run-claude.sh"
echo "  2. MCPツールで検索: ToolSearch \"chrome-devtools\""
echo "  3. 接続テスト実行: mcp__chrome-devtools__list_pages"
echo ""

exit 0
