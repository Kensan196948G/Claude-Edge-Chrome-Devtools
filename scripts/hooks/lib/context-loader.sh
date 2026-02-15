#!/usr/bin/env bash
# ============================================================
# context-loader.sh - Memory MCP からコンテキスト復元
# ============================================================

PROJECT_NAME="${1:-unknown}"
CONTEXT_FILE="$HOME/.claude/memory/project-context.json"

echo "📋 Memory MCP コンテキスト復元..."

# Memory MCP ディレクトリ作成
mkdir -p "$HOME/.claude/memory"

# コンテキストファイルが存在しない場合は初期化
if [ ! -f "$CONTEXT_FILE" ]; then
    cat > "$CONTEXT_FILE" <<'EOF'
{
  "projects": {},
  "globalNotes": [],
  "createdAt": ""
}
EOF
    echo "  ℹ️  コンテキストファイル初期化（初回起動）"
    exit 0
fi

# jq が利用可能か確認
if ! command -v jq &>/dev/null; then
    echo "  ⚠️  jq がインストールされていないため、コンテキスト復元をスキップします"
    exit 0
fi

# プロジェクト固有のコンテキスト読み込み
LAST_TASK=$(jq -r ".projects[\"$PROJECT_NAME\"].lastTask // \"なし\"" "$CONTEXT_FILE" 2>/dev/null || echo "読み込み失敗")
OPEN_ISSUES=$(jq -r ".projects[\"$PROJECT_NAME\"].openIssues // [] | length" "$CONTEXT_FILE" 2>/dev/null || echo "0")
PROJECT_NOTES=$(jq -r ".projects[\"$PROJECT_NAME\"].notes // \"\"" "$CONTEXT_FILE" 2>/dev/null || echo "")

echo "  前回の作業: $LAST_TASK"
echo "  未解決課題: ${OPEN_ISSUES}件"

if [ -n "$PROJECT_NOTES" ]; then
    echo "  プロジェクトメモ: $PROJECT_NOTES"
fi

# INIT_PROMPT に自動追加するためのコンテキストを stdout に出力
cat <<EOF


【前回セッションのコンテキスト（Memory MCP より復元）】
- 最終タスク: $LAST_TASK
- 未解決課題: ${OPEN_ISSUES}件
- プロジェクト: $PROJECT_NAME
EOF
