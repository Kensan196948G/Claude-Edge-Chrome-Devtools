#!/usr/bin/env bash
# ============================================================
# tmux-dashboard.sh - tmux ダッシュボードレイアウトエンジン
# ============================================================
# 引数:
#   $1 - PROJECT_NAME  (プロジェクト名)
#   $2 - PORT          (DevToolsポート番号)
#   $3 - LAYOUT        (レイアウト名: default|review-team|fullstack-dev-team|debug-team|auto)
#   $4 - CLAUDE_CMD    (Claude Code 起動コマンド)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANES_DIR="${SCRIPT_DIR}/panes"
LAYOUTS_DIR="${SCRIPT_DIR}/layouts"

PROJECT_NAME="${1:?ERROR: PROJECT_NAME が指定されていません}"
PORT="${2:?ERROR: PORT が指定されていません}"
LAYOUT="${3:-auto}"
CLAUDE_CMD="${4:-claude}"
SESSION_NAME="claude-${PROJECT_NAME}-${PORT}"

# ============================================================
# レイアウト自動検出
# ============================================================
detect_layout() {
    if [ "$LAYOUT" != "auto" ]; then
        echo "$LAYOUT"
        return
    fi

    # ~/.claude/teams/ からアクティブなチームを検出
    local teams_dir="$HOME/.claude/teams"
    if [ -d "$teams_dir" ]; then
        for team_config in "$teams_dir"/*/config.json; do
            [ -f "$team_config" ] || continue
            local team_dir
            team_dir=$(dirname "$team_config")
            local team_name
            team_name=$(basename "$team_dir")

            case "$team_name" in
                *review*)    echo "review-team"; return ;;
                *fullstack*) echo "fullstack-dev-team"; return ;;
                *debug*)     echo "debug-team"; return ;;
            esac
        done
    fi

    echo "default"
}

# ============================================================
# スクリプト名 → アイコン+ラベル変換
# ============================================================
get_pane_label() {
    local script_name="$1"
    local pane_name="$2"
    case "$script_name" in
        devtools-monitor.sh)    echo "🌐 DevTools Monitor" ;;
        mcp-health-monitor.sh)  echo "🔌 MCP Health" ;;
        git-status-monitor.sh)  echo "🌿 Git Status" ;;
        resource-monitor.sh)    echo "📊 Resources" ;;
        agent-teams-monitor.sh) echo "🤖 Agent Teams" ;;
        *)                      echo "📋 ${pane_name}" ;;
    esac
}

LAYOUT=$(detect_layout)
LAYOUT_FILE="${LAYOUTS_DIR}/${LAYOUT}.conf"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  tmux Dashboard: ${PROJECT_NAME}"
echo "  Port: ${PORT} | Layout: ${LAYOUT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================
# tmux 利用可能チェック
# ============================================================
if ! command -v tmux &>/dev/null; then
    echo "⚠️  tmux が見つかりません。通常モードで起動します。"
    # shellcheck disable=SC2086
    exec $CLAUDE_CMD
fi

# ============================================================
# 既存セッション処理
# ============================================================
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "📎 既存セッション '${SESSION_NAME}' に再接続します..."
    exec tmux attach-session -t "$SESSION_NAME"
fi

# ============================================================
# レイアウト設定読み込み
# ============================================================
if [ ! -f "$LAYOUT_FILE" ]; then
    echo "⚠️  レイアウトファイル '${LAYOUT_FILE}' が見つかりません。default を使用します。"
    LAYOUT_FILE="${LAYOUTS_DIR}/default.conf"
    LAYOUT="default"
fi

# .conf ファイルからペイン定義を読み取る
# 形式: PANE_NAME SPLIT_DIRECTION SPLIT_PERCENTAGE SCRIPT_NAME [ARGS...]
declare -a PANE_DEFS=()
if [ -f "$LAYOUT_FILE" ]; then
    while IFS= read -r line; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        PANE_DEFS+=("$line")
    done < "$LAYOUT_FILE"
fi

# ============================================================
# tmux セッション作成
# ============================================================
# 新規セッションをデタッチ状態で作成（メインペイン = Claude Code）
tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50
# WINDOW_MANUALSIZE フラグを確実に設定（tmux < 3.2 で new-session がフラグを設定しない場合の対策）
# これにより split-window -l N% が "size missing" を返すバグを回避する
tmux resize-window -t "$SESSION_NAME" -x 200 -y 50 2>/dev/null || true

# ステータスバーのカスタマイズ
tmux set-option -t "$SESSION_NAME" status on
tmux set-option -t "$SESSION_NAME" status-interval 5
tmux set-option -t "$SESSION_NAME" status-left-length 40
tmux set-option -t "$SESSION_NAME" status-right-length 60
tmux set-option -t "$SESSION_NAME" status-left "#[fg=colour39,bold] ${PROJECT_NAME} #[fg=colour240]| #[fg=colour154]Port:${PORT} "
tmux set-option -t "$SESSION_NAME" status-right "#[fg=colour240]| #[fg=colour39]${LAYOUT} #[fg=colour240]| #[fg=colour255]%H:%M "
tmux set-option -t "$SESSION_NAME" status-style "bg=colour235,fg=colour255"

# ペインボーダースタイル
tmux set-option -t "$SESSION_NAME" pane-active-border-style "fg=colour154,bg=colour235"
tmux set-option -t "$SESSION_NAME" pane-border-style "fg=colour240,bg=colour235"

# ペインボーダーラベル表示 (tmux 2.6+)
# アクティブペインは緑+太字、非アクティブはグレーで役割名を表示
tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format "#{?pane_active,#[bg=colour22,fg=colour154,bold],#[bg=colour237,fg=colour245]} #{pane_title} #[default]" 2>/dev/null || true

# マウスサポート有効化 (tmux 2.1+)
# ・マウスドラッグでペイン境界をリサイズ
# ・クリックでペイン選択
# ・スクロールホイールでペイン内スクロール
tmux set-option -t "$SESSION_NAME" mouse on 2>/dev/null || true

# 新規ペイン作成時の自動選択を無効化（メインペインを常にフォーカス状態にする）
tmux set-option -g even-panes off 2>/dev/null || true

# ============================================================
# ペイン分割 & モニタリングスクリプト起動
# ============================================================
PANE_INDEX=0
for pane_def in "${PANE_DEFS[@]}"; do
    read -r _pane_name split_dir split_pct script_name script_args <<< "$pane_def"

    local_script="${PANES_DIR}/${script_name}"
    if [ ! -f "$local_script" ]; then
        echo "⚠️  スクリプト '${script_name}' が見つかりません。スキップします。"
        continue
    fi

    # ペインを分割（-l N% は tmux 3.1+ 推奨構文、-p N は tmux 3.3a+ で非推奨）
    if [ "$split_dir" = "h" ]; then
        tmux split-window -h -t "${SESSION_NAME}" -l "${split_pct}%"
    else
        tmux split-window -v -t "${SESSION_NAME}" -l "${split_pct}%"
    fi

    PANE_INDEX=$((PANE_INDEX + 1))

    # script_args のプレースホルダー置換
    script_args="${script_args//__PORT__/$PORT}"
    script_args="${script_args//__PROJECT__/$PROJECT_NAME}"

    # ペインタイトル設定（アイコン + 役割名）
    pane_label=$(get_pane_label "$script_name" "$_pane_name")
    tmux select-pane -t "${SESSION_NAME}.${PANE_INDEX}" -T "$pane_label" 2>/dev/null || true

    # モニタリングスクリプト起動
    tmux send-keys -t "${SESSION_NAME}.${PANE_INDEX}" "bash '${local_script}' ${script_args}" C-m
done

# メインペイン（pane 0）のタイトル設定と Claude Code 起動
tmux select-pane -t "${SESSION_NAME}.0" -T "🤖 Claude Code [${PROJECT_NAME}]" 2>/dev/null || true
tmux select-pane -t "${SESSION_NAME}.0"
tmux send-keys -t "${SESSION_NAME}.0" "${CLAUDE_CMD}" C-m

# 起動完了を待ってメインペインを確実にフォーカス（Claudeのプロンプトを常に表示）
sleep 0.3
tmux select-pane -t "${SESSION_NAME}.0"

# ============================================================
# セッションにアタッチ
# ============================================================
echo "🚀 tmux ダッシュボードを起動します..."
exec tmux attach-session -t "$SESSION_NAME"
