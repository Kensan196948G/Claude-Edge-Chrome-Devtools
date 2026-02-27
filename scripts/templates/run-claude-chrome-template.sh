#!/bin/bash
# ============================================================
# run-claude.sh - Claude Code 起動スクリプト (Chrome版)
# 生成元: Claude-EdgeChromeDevTools
# テンプレート: scripts/templates/run-claude-chrome-template.sh
# ============================================================
set -euo pipefail

PORT=__DEVTOOLS_PORT__
RESTART_DELAY=3
__ENV_EXPORTS__

trap 'echo "🛑 Ctrl+C で終了"; exit 0' INT

echo "🔍 DevTools 応答確認..."
echo "PORT=${PORT}"
MAX_RETRY=10
for i in $(seq 1 $MAX_RETRY); do
  if curl -sf --connect-timeout 2 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
    echo "✅ DevTools 接続成功!"
    break
  fi
  if [ "$i" -eq "$MAX_RETRY" ]; then
    echo "❌ DevTools 応答なし (port=${PORT})"
    exit 1
  fi
  echo "   リトライ中... ($i/$MAX_RETRY)"
  sleep 2
done

# 環境変数を設定
export CLAUDE_CHROME_DEBUG_PORT="${PORT}"
export MCP_CHROME_DEBUG_PORT="${PORT}"

# on-startup hook 実行（環境変数設定後）
if [ -f ".claude/hooks/on-startup.sh" ]; then
    bash .claude/hooks/on-startup.sh
fi

# DevTools詳細接続テスト関数
test_devtools_connection() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 DevTools 詳細接続テスト"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 1. バージョン情報
    echo "📋 1. バージョン情報:"
    if command -v jq &> /dev/null; then
        curl -s "http://127.0.0.1:${PORT}/json/version" | jq '.' || echo "❌ バージョン取得失敗"
    else
        curl -s "http://127.0.0.1:${PORT}/json/version" || echo "❌ バージョン取得失敗"
    fi
    echo ""

    # 2. タブ数確認
    echo "📋 2. 開いているタブ数:"
    if command -v jq &> /dev/null; then
        TAB_COUNT=$(curl -s "http://127.0.0.1:${PORT}/json/list" | jq 'length')
        echo "   タブ数: ${TAB_COUNT}"
    else
        echo "   (jqがインストールされていないため詳細表示不可)"
        curl -s "http://127.0.0.1:${PORT}/json/list" | head -n 3
    fi
    echo ""

    # 3. WebSocketエンドポイント確認
    echo "📋 3. WebSocket接続エンドポイント:"
    if command -v jq &> /dev/null; then
        WS_URL=$(curl -s "http://127.0.0.1:${PORT}/json/list" | jq -r '.[0].webSocketDebuggerUrl // "N/A"')
        echo "   ${WS_URL}"
    else
        echo "   (jqがインストールされていないため表示不可)"
    fi
    echo ""

    # 4. Protocol version確認
    echo "📋 4. DevTools Protocol Version:"
    if command -v jq &> /dev/null; then
        PROTO_VER=$(curl -s "http://127.0.0.1:${PORT}/json/version" | jq -r '."Protocol-Version" // "N/A"')
        echo "   ${PROTO_VER}"
    else
        echo "   (jqがインストールされていないため表示不可)"
    fi
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ DevTools接続テスト完了"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 詳細テスト実行
test_devtools_connection

# --- 初期プロンプト設定 ---
INIT_PROMPT=$(cat << 'INITPROMPTEOF'
__INIT_PROMPT__
INITPROMPTEOF
)

echo ""
echo "🚀 Claude 起動 (port=${PORT})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 初期プロンプトを自動入力します..."
echo ""

while true; do
  # 初期プロンプトをパイプで自動入力
  echo "$INIT_PROMPT" | claude --dangerously-skip-permissions
  EXIT_CODE=$?

  [ "$EXIT_CODE" -eq 0 ] && break

  echo ""
  echo "🔄 Claude 再起動 (${RESTART_DELAY}秒後)..."
  sleep $RESTART_DELAY
done

echo "👋 終了しました"
