#!/usr/bin/env bash
# Claude Code Statusline v2
# Format:
#   🤖 Opus 4.6 │ 📊 25% │ ✏️  +5/-1 │ 🔀 main
#   ⏱ 5h  ▰▰▰▱▱▱▱▱▱▱  28%  Resets 9pm (Asia/Tokyo)
#   📅 7d  ▰▰▰▰▰▰▱▱▱▱  59%  Resets Mar 6 at 1pm (Asia/Tokyo)
set -euo pipefail

# === 入力受付 ===
input="$(cat)"
if [ -z "$input" ]; then
    input="{\"model\":{\"display_name\":\"Unknown\"},\"workspace\":{\"current_dir\":\"$(pwd)\"},\"context_window\":{\"used_percentage\":0},\"session\":{}}"
fi

# === Line 1 パース ===
MODEL_FULL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
MODEL_SHORT="${MODEL_FULL#Claude }"  # "Claude Opus 4.6" → "Opus 4.6"

USED_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
USED_PCT=$(printf '%.0f' "${USED_PCT:-0}" 2>/dev/null || echo 0)

LINES_ADDED=$(echo "$input" | jq -r '.session.lines_added // 0')
LINES_REMOVED=$(echo "$input" | jq -r '.session.lines_removed // 0')

DIR=$(echo "$input" | jq -r '.workspace.current_dir // "."')
DIR="${DIR:-.}"

# Git ブランチ
GIT_BRANCH=""
if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null || true)
    if [ -z "$GIT_BRANCH" ]; then
        GIT_BRANCH=$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null || true)
    fi
fi
BRANCH_SEG=""
[ -n "$GIT_BRANCH" ] && BRANCH_SEG=" │ 🔀 $GIT_BRANCH"

# === Line 1 出力 ===
echo "🤖 ${MODEL_SHORT} │ 📊 ${USED_PCT}% │ ✏️  +${LINES_ADDED}/-${LINES_REMOVED}${BRANCH_SEG}"

# === ユーティリティ関数 ===

# 10段階プログレスバー (▰=使用済み ▱=残り)
make_bar() {
    local pct="${1:-0}"
    local filled=$(( pct * 10 / 100 ))
    local bar="" i=0
    while [ $i -lt $filled ]; do bar="${bar}▰"; ((i++)) || true; done
    while [ $i -lt 10 ];     do bar="${bar}▱"; ((i++)) || true; done
    echo "$bar"
}

# リセット時刻フォーマット: ISO8601 → "Resets 9pm (Asia/Tokyo)" / "Resets Mar 6 at 1pm (Asia/Tokyo)"
format_reset() {
    local reset_utc="$1"
    [ -z "$reset_utc" ] && { echo "Resets ? (Asia/Tokyo)"; return; }

    local now_day reset_day
    now_day=$(TZ=Asia/Tokyo date +"%Y-%m-%d" 2>/dev/null) || { echo "Resets ? (Asia/Tokyo)"; return; }
    reset_day=$(TZ=Asia/Tokyo date -d "$reset_utc" +"%Y-%m-%d" 2>/dev/null) || { echo "Resets ? (Asia/Tokyo)"; return; }

    local hour_str
    if [ "$now_day" = "$reset_day" ]; then
        hour_str=$(TZ=Asia/Tokyo date -d "$reset_utc" +"%-I%p" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        echo "Resets ${hour_str} (Asia/Tokyo)"
    else
        local month_day
        month_day=$(TZ=Asia/Tokyo date -d "$reset_utc" +"%b %-d at %-I%p" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        # 先頭文字だけ大文字: "mar 6 at 1pm" → "Mar 6 at 1pm"
        echo "Resets $(echo "${month_day:0:1}" | tr '[:lower:]' '[:upper:]')${month_day:1} (Asia/Tokyo)"
    fi
}

# === Haiku Probe (レート制限取得) ===
CACHE_FILE="/tmp/.claude-statusline-cache"
CACHE_TTL=360  # 6分

RATE_HEADERS=""

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    : # APIキー未設定 → Line 2/3 をスキップ
elif [ -f "$CACHE_FILE" ]; then
    cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    cache_age=$(( $(date +%s) - cache_mtime ))
    if [ "$cache_age" -lt "$CACHE_TTL" ]; then
        RATE_HEADERS=$(cat "$CACHE_FILE")
    fi
fi

# キャッシュなし or 期限切れ → Haiku Probe
if [ -z "$RATE_HEADERS" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    RATE_HEADERS=$(curl -s -I -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
        2>/dev/null | tr -d '\r') || RATE_HEADERS=""
    [ -n "$RATE_HEADERS" ] && echo "$RATE_HEADERS" > "$CACHE_FILE" || true
fi

# === Line 2/3 出力 (APIキーあり + レート制限取得成功時) ===
if [ -n "$RATE_HEADERS" ]; then
    # requests ヘッダー抽出
    REQ_REMAINING=$(echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-requests-remaining:' | awk '{print $2}' | head -1 | tr -d '[:space:]')
    REQ_LIMIT=$(    echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-requests-limit:'     | awk '{print $2}' | head -1 | tr -d '[:space:]')
    REQ_RESET=$(    echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-requests-reset:'     | awk '{print $2}' | head -1 | tr -d '[:space:]')

    # tokens ヘッダー抽出
    TOK_REMAINING=$(echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-tokens-remaining:' | awk '{print $2}' | head -1 | tr -d '[:space:]')
    TOK_LIMIT=$(    echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-tokens-limit:'     | awk '{print $2}' | head -1 | tr -d '[:space:]')
    TOK_RESET=$(    echo "$RATE_HEADERS" | grep -i '^anthropic-ratelimit-tokens-reset:'     | awk '{print $2}' | head -1 | tr -d '[:space:]')

    # パーセンテージ計算 (使用率 = (limit - remaining) / limit * 100)
    REQ_PCT=0
    if [ -n "$REQ_LIMIT" ] && [ "${REQ_LIMIT:-0}" -gt 0 ] 2>/dev/null; then
        REQ_USED=$(( REQ_LIMIT - ${REQ_REMAINING:-0} ))
        REQ_PCT=$(( REQ_USED * 100 / REQ_LIMIT ))
    fi

    TOK_PCT=0
    if [ -n "$TOK_LIMIT" ] && [ "${TOK_LIMIT:-0}" -gt 0 ] 2>/dev/null; then
        TOK_USED=$(( TOK_LIMIT - ${TOK_REMAINING:-0} ))
        TOK_PCT=$(( TOK_USED * 100 / TOK_LIMIT ))
    fi

    REQ_BAR=$(make_bar "$REQ_PCT")
    TOK_BAR=$(make_bar "$TOK_PCT")
    REQ_RESET_STR=$(format_reset "$REQ_RESET")
    TOK_RESET_STR=$(format_reset "$TOK_RESET")

    # Line 2: requests ウィンドウ (⏱ 5h)
    echo "⏱ 5h  ${REQ_BAR}  ${REQ_PCT}%  ${REQ_RESET_STR}"

    # Line 3: tokens ウィンドウ (📅 7d)
    echo "📅 7d  ${TOK_BAR}  ${TOK_PCT}%  ${TOK_RESET_STR}"
fi
