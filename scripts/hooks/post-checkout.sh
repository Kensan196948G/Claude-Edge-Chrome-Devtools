#!/usr/bin/env bash
# ============================================================
# post-checkout.sh - ブランチ切り替え後の自動処理
# ============================================================

set -euo pipefail

# Git hook の引数
PREV_HEAD="$1"
NEW_HEAD="$2"
BRANCH_CHECKOUT="$3"  # 1=ブランチ切り替え, 0=ファイル checkout

# ファイル checkout の場合はスキップ
if [ "$BRANCH_CHECKOUT" = "0" ]; then
    exit 0
fi

echo "🔄 post-checkout hook: ブランチ切り替え検出"
echo "  From: $(git rev-parse --short "$PREV_HEAD" 2>/dev/null || echo 'unknown')"
echo "  To:   $(git rev-parse --short "$NEW_HEAD" 2>/dev/null || echo 'unknown')"
echo ""

CHANGES_DETECTED=false

# ============================================================
# 1. package.json の変更確認（Node.js プロジェクト）
# ============================================================
if [ -f "package.json" ]; then
    if git diff --name-only "$PREV_HEAD" "$NEW_HEAD" | grep -q "package.json\|package-lock.json\|yarn.lock"; then
        echo "📦 package.json の変更を検出"
        CHANGES_DETECTED=true

        if command -v npm &>/dev/null; then
            echo "   npm install を実行中..."
            npm install
            echo "   ✅ npm install 完了"
        else
            echo "   ⚠️  npm がインストールされていません"
        fi
        echo ""
    fi
fi

# ============================================================
# 2. requirements.txt の変更確認（Python プロジェクト）
# ============================================================
if [ -f "requirements.txt" ]; then
    if git diff --name-only "$PREV_HEAD" "$NEW_HEAD" | grep -q "requirements.txt"; then
        echo "🐍 requirements.txt の変更を検出"
        CHANGES_DETECTED=true

        if command -v pip &>/dev/null; then
            echo "   pip install を実行中..."
            pip install -r requirements.txt
            echo "   ✅ pip install 完了"
        else
            echo "   ⚠️  pip がインストールされていません"
        fi
        echo ""
    fi
fi

# ============================================================
# 3. config.json の変更確認
# ============================================================
if git diff --name-only "$PREV_HEAD" "$NEW_HEAD" | grep -q "config/config.json\|config.json"; then
    echo "⚙️  config.json の変更を検出"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  重要な設定変更があります"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "以下の項目を確認してください:"
    echo "  • ポート番号の変更（ports 配列）"
    echo "  • ドライブパスの変更（zDrive, zDriveUncPath）"
    echo "  • SSH ホストの変更（linuxHost）"
    echo "  • MCP Token の変更（githubToken, braveApiKey）"
    echo ""
    echo "変更内容:"
    git diff "$PREV_HEAD" "$NEW_HEAD" -- config/config.json config.json 2>/dev/null | head -20
    echo ""

    CHANGES_DETECTED=true
fi

# ============================================================
# 4. .mcp.json の変更確認
# ============================================================
if git diff --name-only "$PREV_HEAD" "$NEW_HEAD" | grep -q ".mcp.json"; then
    echo "🔌 .mcp.json の変更を検出"
    echo "   .mcp.json のバックアップを推奨します"
    echo ""

    # バックアップ作成
    if [ -f ".mcp.json" ]; then
        BACKUP_PATH=".mcp.json.post-checkout-backup.$(date +%Y%m%d-%H%M%S)"
        cp .mcp.json "$BACKUP_PATH"
        echo "   ✅ バックアップ作成: $BACKUP_PATH"
    fi
    echo ""

    CHANGES_DETECTED=true
fi

# ============================================================
# 5. SSH 鍵権限の自動修正（Windows のみ）
# ============================================================
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # Windows (Git Bash) 環境
    SSH_KEY="$HOME/.ssh/id_ed25519"

    if [ -f "$SSH_KEY" ]; then
        echo "🔑 SSH 鍵権限の確認..."

        # icacls で権限確認（簡易）
        # Everyone や Users のアクセス権があれば修正
        if icacls "$SSH_KEY" 2>/dev/null | grep -E "Everyone.*RX|BUILTIN\\\\Users.*RX" >/dev/null; then
            echo "   ⚠️  SSH 鍵の権限が緩すぎます。修正中..."

            # Windows PowerShell で権限修正
            powershell -Command "icacls '$SSH_KEY' /inheritance:r /grant:r '${USERNAME}:(R)'" 2>&1 | grep "処理されたファイル" >/dev/null && \
                echo "   ✅ SSH 鍵権限を修正しました" || \
                echo "   ⚠️  権限修正に失敗しました（手動で icacls 実行してください）"
        else
            echo "   ✅ SSH 鍵権限は正常です"
        fi
        echo ""
    fi
fi

# ============================================================
# 6. Git submodule の更新確認
# ============================================================
if [ -f ".gitmodules" ]; then
    if git diff --name-only "$PREV_HEAD" "$NEW_HEAD" | grep -q ".gitmodules"; then
        echo "📦 Git submodule の変更を検出"
        CHANGES_DETECTED=true

        echo "   git submodule update を実行中..."
        git submodule update --init --recursive
        echo "   ✅ submodule 更新完了"
        echo ""
    fi
fi

# ============================================================
# 終了メッセージ
# ============================================================
if [ "$CHANGES_DETECTED" = false ]; then
    echo "✅ 重要な変更はありませんでした"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ post-checkout 処理完了"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

exit 0
