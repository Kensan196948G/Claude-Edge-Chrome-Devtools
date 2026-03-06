#!/usr/bin/env bash
# tests/test-statusline-v2.sh — statusline.sh v2 フォーマット検証テスト
set -uo pipefail

PASS=0
FAIL=0
SCRIPT="scripts/statusline.sh"

assert_contains() {
    local name="$1" output="$2" expected="$3"
    if echo "$output" | grep -qF "$expected"; then
        echo "✓ $name"
        ((PASS++)) || true
    else
        echo "✗ $name"
        echo "  期待: $expected"
        echo "  実際: $output"
        ((FAIL++)) || true
    fi
}

assert_not_contains() {
    local name="$1" output="$2" unexpected="$3"
    if ! echo "$output" | grep -qF "$unexpected"; then
        echo "✓ $name"
        ((PASS++)) || true
    else
        echo "✗ $name (含まれてはいけない: $unexpected)"
        ((FAIL++)) || true
    fi
}

assert_equals() {
    local name="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        echo "✓ $name"
        ((PASS++)) || true
    else
        echo "✗ $name"
        echo "  期待: $expected"
        echo "  実際: $actual"
        ((FAIL++)) || true
    fi
}

MOCK_JSON='{"model":{"display_name":"Claude Opus 4.6"},"context_window":{"used_percentage":25},"session":{"lines_added":5,"lines_removed":1},"workspace":{"current_dir":"."}}'

echo "=== Test Suite: statusline.sh v2 ==="
echo ""

# --- テスト1: Line 1 モデル名表示 ---
echo "--- Line 1 Tests ---"
LINE1=$(echo "$MOCK_JSON" | ANTHROPIC_API_KEY="" bash "$SCRIPT" | head -1)
assert_contains "Line1: 🤖 が含まれる" "$LINE1" "🤖"
assert_contains "Line1: Opus 4.6 (Claude省略)" "$LINE1" "Opus 4.6"
assert_not_contains "Line1: 'Claude Opus' が省略される" "$LINE1" "Claude Opus"
assert_contains "Line1: 📊 が含まれる" "$LINE1" "📊"
assert_contains "Line1: 25% が含まれる" "$LINE1" "25%"
assert_contains "Line1: ✏️ が含まれる" "$LINE1" "✏️"
assert_contains "Line1: +5/-1 が含まれる" "$LINE1" "+5/-1"
assert_contains "Line1: │ 区切り文字" "$LINE1" "│"

# --- テスト2: Line 1 Git ブランチ（gitリポジトリ内） ---
echo ""
echo "--- Git Branch Tests ---"
GIT_DIR_JSON=$(jq -n --arg dir "$(pwd)" \
    '{"model":{"display_name":"Claude Sonnet 4.6"},"context_window":{"used_percentage":0},"session":{},"workspace":{"current_dir":$dir}}')
LINE1_GIT=$(echo "$GIT_DIR_JSON" | ANTHROPIC_API_KEY="" bash "$SCRIPT" | head -1)
assert_contains "Line1: 🔀 Gitブランチ表示" "$LINE1_GIT" "🔀"

# --- テスト3: APIキーなしの場合1行のみ出力 ---
echo ""
echo "--- No API Key Tests ---"
OUTPUT_NO_API=$(echo "$MOCK_JSON" | ANTHROPIC_API_KEY="" bash "$SCRIPT" 2>/dev/null)
LINE_COUNT=$(echo "$OUTPUT_NO_API" | grep -c .)
assert_equals "APIキーなし: 出力行数=1" "$LINE_COUNT" "1"

# --- テスト4: 空入力でもエラーにならない ---
echo ""
echo "--- Empty Input Tests ---"
OUTPUT_EMPTY=$(echo "" | ANTHROPIC_API_KEY="" bash "$SCRIPT" 2>/dev/null || true)
assert_contains "空入力: エラーなし(🤖含む)" "$OUTPUT_EMPTY" "🤖"

# --- テスト5: コンテキスト100%でも動作 ---
echo ""
echo "--- Edge Case Tests ---"
EDGE_JSON='{"model":{"display_name":"Unknown"},"context_window":{"used_percentage":100},"session":{},"workspace":{"current_dir":"."}}'
LINE1_EDGE=$(echo "$EDGE_JSON" | ANTHROPIC_API_KEY="" bash "$SCRIPT" | head -1)
assert_contains "100%コンテキスト: 正常出力" "$LINE1_EDGE" "100%"

# --- テスト6: プログレスバー文字列（API利用時） ---
echo ""
echo "--- Progress Bar Format (requires API) ---"
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    OUTPUT_WITH_API=$(echo "$MOCK_JSON" | bash "$SCRIPT" 2>/dev/null)
    LINES=$(echo "$OUTPUT_WITH_API" | grep -c .)
    assert_equals "APIキーあり: 3行出力" "$LINES" "3"
    LINE2=$(echo "$OUTPUT_WITH_API" | sed -n '2p')
    LINE3=$(echo "$OUTPUT_WITH_API" | sed -n '3p')
    assert_contains "Line2: ⏱ が含まれる" "$LINE2" "⏱"
    assert_contains "Line2: 5h が含まれる" "$LINE2" "5h"
    assert_contains "Line2: プログレスバー文字▰か▱" "$LINE2" "▰"
    assert_contains "Line2: Resets が含まれる" "$LINE2" "Resets"
    assert_contains "Line3: 📅 が含まれる" "$LINE3" "📅"
    assert_contains "Line3: 7d が含まれる" "$LINE3" "7d"
    assert_contains "Line3: Asia/Tokyo が含まれる" "$LINE3" "Asia/Tokyo"
else
    echo "ℹ ANTHROPIC_API_KEY 未設定 — APIテストをスキップ"
fi

echo ""
echo "================================="
echo "Results: $PASS passed, $FAIL failed"
echo "================================="
[ "$FAIL" -eq 0 ]
