#!/usr/bin/env bash
# ============================================================
# tmux-install.sh - tmux 自動インストール・検証
# ============================================================
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  tmux インストールチェック"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 既にインストール済みか確認
if command -v tmux &>/dev/null; then
    TMUX_VER=$(tmux -V 2>/dev/null || echo "unknown")
    echo "✅ tmux は既にインストールされています: $TMUX_VER"
    exit 0
fi

echo "⚠️  tmux が見つかりません。インストールを試みます..."
echo ""

# パッケージマネージャーの自動検出とインストール
install_tmux() {
    if command -v apt-get &>/dev/null; then
        echo "📦 apt-get を使用してインストール中..."
        sudo apt-get update -qq && sudo apt-get install -y tmux
    elif command -v dnf &>/dev/null; then
        echo "📦 dnf を使用してインストール中..."
        sudo dnf install -y tmux
    elif command -v yum &>/dev/null; then
        echo "📦 yum を使用してインストール中..."
        sudo yum install -y tmux
    elif command -v pacman &>/dev/null; then
        echo "📦 pacman を使用してインストール中..."
        sudo pacman -S --noconfirm tmux
    elif command -v brew &>/dev/null; then
        echo "📦 brew を使用してインストール中..."
        brew install tmux
    elif command -v apk &>/dev/null; then
        echo "📦 apk を使用してインストール中..."
        sudo apk add tmux
    else
        echo "❌ サポートされているパッケージマネージャーが見つかりません"
        echo ""
        echo "💡 手動でインストールしてください:"
        echo "   Debian/Ubuntu: sudo apt-get install tmux"
        echo "   RHEL/CentOS:   sudo yum install tmux"
        echo "   Fedora:        sudo dnf install tmux"
        echo "   Arch:          sudo pacman -S tmux"
        echo "   macOS:         brew install tmux"
        exit 1
    fi
}

install_tmux

echo ""

# インストール後の検証
if command -v tmux &>/dev/null; then
    TMUX_VER=$(tmux -V 2>/dev/null || echo "unknown")
    echo "✅ tmux インストール成功: $TMUX_VER"
    exit 0
else
    echo "❌ tmux インストールに失敗しました"
    exit 1
fi
