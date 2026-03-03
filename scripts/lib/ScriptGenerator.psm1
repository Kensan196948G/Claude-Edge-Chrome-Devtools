# ============================================================
# ScriptGenerator.psm1 - スクリプト生成モジュール
# Claude-EdgeChromeDevTools v1.3.0
# ============================================================

<#
.SYNOPSIS
    config.jsonのclaudeCodeセクションからJSON文字列を生成

.DESCRIPTION
    claudeCode.envとclaudeCode.settingsをsettings.json形式のJSONに変換する。
    Linux側の ~/.claude/settings.json へのマージ適用に使用する。

.PARAMETER ClaudeEnv
    環境変数のハッシュテーブル（claudeCode.env）

.PARAMETER ClaudeSettings
    Claude Code設定のハッシュテーブル（claudeCode.settings）

.EXAMPLE
    $json = Build-ClaudeCodeJsonFromConfig -ClaudeEnv $config.claudeCode.env `
                                           -ClaudeSettings $config.claudeCode.settings
#>
function Build-ClaudeCodeJsonFromConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        $ClaudeEnv = $null,

        [Parameter(Mandatory=$false)]
        $ClaudeSettings = $null
    )

    # 環境変数JSON生成
    $envHash = @{}
    if ($null -ne $ClaudeEnv) {
        if ($ClaudeEnv -is [hashtable]) {
            foreach ($key in $ClaudeEnv.Keys) { $envHash[$key] = $ClaudeEnv[$key] }
        } elseif ($ClaudeEnv -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $ClaudeEnv.PSObject.Properties) { $envHash[$prop.Name] = $prop.Value }
        }
    }

    # 設定JSON生成
    $settingsHash = @{}
    if ($null -ne $ClaudeSettings) {
        if ($ClaudeSettings -is [hashtable]) {
            foreach ($key in $ClaudeSettings.Keys) { $settingsHash[$key] = $ClaudeSettings[$key] }
        } elseif ($ClaudeSettings -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $ClaudeSettings.PSObject.Properties) { $settingsHash[$prop.Name] = $prop.Value }
        }
    }

    $envJson      = $envHash      | ConvertTo-Json -Depth 5 -Compress
    $settingsJson = $settingsHash | ConvertTo-Json -Depth 5 -Compress

    # フル設定JSON (env含む)
    $fullHash = $settingsHash.Clone()
    if ($envHash.Count -gt 0) { $fullHash['env'] = $envHash }
    $fullJson = $fullHash | ConvertTo-Json -Depth 5

    return @{
        EnvJson      = $envJson
        SettingsJson = $settingsJson
        FullJson     = $fullJson
    }
}

<#
.SYNOPSIS
    UTF-8でbase64エンコード

.DESCRIPTION
    文字列をUTF-8エンコーディングでBase64エンコードする。
    SSHによるスクリプト転送に使用する。

.PARAMETER Content
    エンコードする文字列

.EXAMPLE
    $encoded = ConvertTo-Base64Utf8 -Content "echo 'hello world'"
#>
function ConvertTo-Base64Utf8 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    # LF改行に統一してからエンコード
    $contentLf = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($contentLf)
    return [Convert]::ToBase64String($bytes)
}

<#
.SYNOPSIS
    run-claude.sh の内容を生成

.DESCRIPTION
    指定されたパラメータからrun-claude.shのbashスクリプト内容を生成して返す。
    DevTools接続確認、環境変数設定、初期プロンプト、tmux対応を含む。

.PARAMETER Params
    以下のキーを含むハッシュテーブル:
    - Port          : DevToolsポート番号 (必須)
    - LinuxBase     : Linuxプロジェクトベースパス (必須)
    - ProjectName   : プロジェクト名 (必須)
    - Layout        : tmuxレイアウト名 (デフォルト: "auto")
    - TmuxEnabled   : tmuxダッシュボードを使用するか (デフォルト: $false)
    - EnvVars       : 追加環境変数のハッシュテーブル (オプション)
    - InitPrompt    : 初期プロンプト文字列 (オプション)

.EXAMPLE
    $script = New-RunClaudeScript -Params @{
        Port        = 9222
        LinuxBase   = "/mnt/LinuxHDD"
        ProjectName = "MyProject"
        TmuxEnabled = $true
        Layout      = "default"
    }
#>
function New-RunClaudeScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Params
    )

    # 必須パラメータ検証
    foreach ($required in @('Port', 'LinuxBase', 'ProjectName')) {
        if (-not $Params.ContainsKey($required) -or $null -eq $Params[$required]) {
            throw "New-RunClaudeScript: 必須パラメータが不足しています: $required"
        }
    }

    $port        = $Params['Port']
    $linuxBase   = $Params['LinuxBase']
    $projectName = $Params['ProjectName']
    $layout      = if ($Params.ContainsKey('Layout'))         { $Params['Layout'] }         else { "auto" }
    $tmuxEnabled = if ($Params.ContainsKey('TmuxEnabled'))    { $Params['TmuxEnabled'] }    else { $false }
    $envVars     = if ($Params.ContainsKey('EnvVars'))        { $Params['EnvVars'] }        else { @{} }
    $initPrompt  = if ($Params.ContainsKey('InitPrompt'))     { $Params['InitPrompt'] }     else { "" }
    $initPromptFile = if ($Params.ContainsKey('InitPromptFile')) { $Params['InitPromptFile'] } else { "" }
    $language    = if ($Params.ContainsKey('Language'))       { $Params['Language'] }       else { "ja" }

    # InitPromptFile が指定されていればファイルから読み込む（InitPrompt より優先度低）
    if ([string]::IsNullOrWhiteSpace($initPrompt) -and -not [string]::IsNullOrWhiteSpace($initPromptFile)) {
        if (Test-Path $initPromptFile) {
            $initPrompt = Get-Content -Path $initPromptFile -Raw -Encoding UTF8
        } else {
            Write-Warning "InitPromptFile が見つかりません: $initPromptFile (デフォルトプロンプトを使用)"
        }
    }

    # InitPromptFile が未指定の場合、言語設定に基づきデフォルトテンプレートを自動選択
    if ([string]::IsNullOrWhiteSpace($initPrompt)) {
        $scriptDir = Split-Path -Parent $PSScriptRoot
        $templateName = if ($language -eq 'en') { 'init-prompt-en.txt' } else { 'init-prompt-ja.txt' }
        $autoTemplatePath = Join-Path $scriptDir "templates" $templateName
        if (Test-Path $autoTemplatePath) {
            $initPrompt = Get-Content -Path $autoTemplatePath -Raw -Encoding UTF8
            Write-Host "📝 言語テンプレート自動選択: $templateName" -ForegroundColor Cyan
        }
    }

    # PowerShellパーサーを回避するためheredoc記号を変数経由で生成
    $hd = '<' + '<'

    $projectPath = "$linuxBase/$projectName"
    $sessionName = "claude-$projectName-$port"

    # 追加環境変数のbash export文を生成
    $envExports = ""
    foreach ($key in $envVars.Keys) {
        $val = $envVars[$key]
        $envExports += "export $key='$val'`n"
    }

    # tmux起動スクリプト部分
    $tmuxSection = if ($tmuxEnabled) {
@"
# --- tmuxダッシュボード起動 ---
TMUX_SCRIPT="`$PROJECT_ROOT/scripts/tmux/tmux-dashboard.sh"
if [ -f "`$TMUX_SCRIPT" ]; then
    echo "🖥️  tmuxダッシュボードを起動します (レイアウト: $layout)..."
    chmod +x "`$TMUX_SCRIPT"
    TMUX_LAYOUT="$layout" bash "`$TMUX_SCRIPT" "`$PROJECT_ROOT" "$port" "$sessionName"
    exit 0
else
    echo "⚠️  tmux-dashboard.sh が見つかりません。通常起動にフォールバックします"
fi
"@
    } else { "" }

    # 初期プロンプト設定（空の場合はデフォルト、$hd変数でheredoc記号を生成）
    $promptBody = if ([string]::IsNullOrWhiteSpace($initPrompt)) {
        "プロジェクトの準備が完了しました。`nDevTools ポート: $port`nプロジェクト: $projectName`n何かお手伝いできることはありますか？"
    } else {
        $initPrompt
    }
    $initPromptBlock = @"
INIT_PROMPT=`$(cat $hd 'INITPROMPTEOF'
$promptBody
INITPROMPTEOF
)
"@

    # run-claude.sh 本体
    $script = @"
#!/bin/bash
# ============================================================
# run-claude.sh - Claude Code 起動スクリプト
# 生成元: Claude-EdgeChromeDevTools v1.3.0
# プロジェクト: $projectName
# DevToolsポート: $port
# ============================================================
set -euo pipefail

PROJECT_ROOT="$projectPath"
DEVTOOLS_PORT=$port
SESSION_NAME="$sessionName"

# --- ログ設定 ---
LOG_DIR="`$PROJECT_ROOT/logs"
MCP_LOG_DIR="`$LOG_DIR/mcp"
LOG_TIMESTAMP=`$(date +%Y%m%d-%H%M%S)
SESSION_LOG="`$LOG_DIR/claude-session-`$LOG_TIMESTAMP.log"

mkdir -p "`$LOG_DIR" "`$MCP_LOG_DIR"

# stdout + stderr をファイルとターミナル両方に出力
exec > >(tee -a "`$SESSION_LOG") 2>&1

# --- ログローテーション (30日超を削除) ---
find "`$LOG_DIR" -maxdepth 1 -name "claude-session-*.log" -mtime +30 -delete 2>/dev/null || true
find "`$MCP_LOG_DIR" -name "mcp-health-*.log" -mtime +30 -delete 2>/dev/null || true

# --- 月次アーカイブ ---
ARCHIVE_DIR="`$LOG_DIR/archive"
PREV_MONTH=`$(date -d "last month" +%Y-%m 2>/dev/null || date -v-1m +%Y-%m 2>/dev/null)
if [ -n "`$PREV_MONTH" ]; then
    ARCHIVE_FILES=`$(find "`$LOG_DIR" -maxdepth 1 -name "claude-session-`${PREV_MONTH}*.log" 2>/dev/null)
    if [ -n "`$ARCHIVE_FILES" ]; then
        mkdir -p "`$ARCHIVE_DIR"
        zip -j "`${ARCHIVE_DIR}/`${PREV_MONTH}.zip" `$ARCHIVE_FILES 2>/dev/null && rm -f `$ARCHIVE_FILES
    fi
fi

# --- 環境変数設定 ---
export CLAUDE_CHROME_DEBUG_PORT="`$DEVTOOLS_PORT"
export MCP_CHROME_DEBUG_PORT="`$DEVTOOLS_PORT"
$envExports
cd "`$PROJECT_ROOT" || { echo "❌ プロジェクトディレクトリに移動できません: `$PROJECT_ROOT"; exit 1; }

echo "📁 プロジェクト: `$PROJECT_ROOT"
echo "🔌 DevToolsポート: `$DEVTOOLS_PORT"

# --- DevTools接続確認 ---
echo "🌐 DevTools接続確認中..."
DEVTOOLS_READY=false
for i in `$(seq 1 10); do
    if curl -sf "http://127.0.0.1:`$DEVTOOLS_PORT/json/version" > /dev/null 2>&1; then
        DEVTOOLS_READY=true
        echo "✅ DevTools接続OK (試行: `$i)"
        # バージョン情報表示
        curl -s "http://127.0.0.1:`$DEVTOOLS_PORT/json/version" | grep -o '"Browser":"[^"]*"' || true
        break
    fi
    echo "  ... DevTools待機中 (`$i/10)"
    sleep 2
done

if [ "`$DEVTOOLS_READY" = "false" ]; then
    echo "⚠️  DevToolsへの接続を確認できませんでした (ポート: `$DEVTOOLS_PORT)"
    echo "   ブラウザが起動しているか確認してください"
fi

# --- 初期プロンプト設定 ---
$initPromptBlock

$tmuxSection

# --- Claude Code 起動ループ ---
echo "🤖 Claude Code を起動します..."
while true; do
    if [ -n "`$INIT_PROMPT" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📋 初期プロンプト指示内容:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "`$INIT_PROMPT"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        claude --dangerously-skip-permissions "`$INIT_PROMPT" || true
    else
        # 対話モード: exec tee によるstdoutリダイレクト迂回のため /dev/tty を使用
        claude --dangerously-skip-permissions </dev/tty >/dev/tty 2>&1 || true
    fi
    echo ""
    echo "🔄 Claude Code が終了しました。再起動モードを選択してください:"
    echo "  [P] プロンプト指示付きで再起動 (デフォルト)"
    echo "  [I] 対話モードで再起動 (プロンプト指示なし)"
    echo "  [N] 終了"
    read -r RESTART_ANSWER
    case "`$RESTART_ANSWER" in
        [Nn])
            echo "👋 終了します"
            break
            ;;
        [Ii])
            INIT_PROMPT=""
            ;;
        *)
            ;;
    esac
done
"@

    return $script
}

# モジュールのエクスポート
Export-ModuleMember -Function @(
    'Build-ClaudeCodeJsonFromConfig',
    'ConvertTo-Base64Utf8',
    'New-RunClaudeScript'
)
