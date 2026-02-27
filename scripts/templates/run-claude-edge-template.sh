#!/bin/bash
# ============================================================
# run-claude.sh - Claude Code 起動スクリプト (Edge版)
# 生成元: Claude-EdgeChromeDevTools
# テンプレート: scripts/templates/run-claude-edge-template.sh
# ============================================================
set -euo pipefail

PROJECT_ROOT="__PROJECT_ROOT__"
DEVTOOLS_PORT=__DEVTOOLS_PORT__

# --- 環境変数設定 ---
export CLAUDE_CHROME_DEBUG_PORT="$DEVTOOLS_PORT"
export MCP_CHROME_DEBUG_PORT="$DEVTOOLS_PORT"
__ENV_EXPORTS__

cd "$PROJECT_ROOT" || { echo "❌ プロジェクトディレクトリに移動できません: $PROJECT_ROOT"; exit 1; }

echo "📁 プロジェクト: $PROJECT_ROOT"
echo "🔌 DevToolsポート: $DEVTOOLS_PORT"

# --- DevTools接続確認 ---
echo "🌐 DevTools接続確認中..."
DEVTOOLS_READY=false
for i in $(seq 1 10); do
    if curl -sf "http://127.0.0.1:$DEVTOOLS_PORT/json/version" > /dev/null 2>&1; then
        DEVTOOLS_READY=true
        echo "✅ DevTools接続OK (試行: $i)"
        curl -s "http://127.0.0.1:$DEVTOOLS_PORT/json/version" | grep -o '"Browser":"[^"]*"' || true
        break
    fi
    echo "  ... DevTools待機中 ($i/10)"
    sleep 2
done

if [ "$DEVTOOLS_READY" = "false" ]; then
    echo "⚠️  DevToolsへの接続を確認できませんでした (ポート: $DEVTOOLS_PORT)"
    echo "   ブラウザが起動しているか確認してください"
fi

# --- 初期プロンプト設定 ---
INIT_PROMPT=$(cat << 'INITPROMPTEOF'
__INIT_PROMPT__
INITPROMPTEOF
)

# --- Claude Code 起動ループ ---
echo "🤖 Claude Code を起動します..."
while true; do
    claude --dangerously-skip-permissions -p "$INIT_PROMPT" || true
    echo ""
    echo "🔄 Claude Code が終了しました。再起動しますか？ [Y/n]"
    read -r RESTART_ANSWER
    if [[ "$RESTART_ANSWER" =~ ^[Nn] ]]; then
        echo "👋 終了します"
        break
    fi
    INIT_PROMPT=""
done
