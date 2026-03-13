<#
.SYNOPSIS
    AI CLI ユニバーサルスタートアップランチャー

.DESCRIPTION
    ClaudeOS Agent Teams 対応: Agent Orchestrator 相当の入口です。
    対応表は docs/common/08_AgentTeams対応表.md を参照してください。
    Claude Code / Codex CLI / GitHub Copilot CLI を統合して起動するランチャーです。
    config/config.json の設定を読み込み、選択したツールを適切なパラメータで起動します。

.PARAMETER Tool
    起動するツール: 'claude', 'codex', 'copilot'
    省略時は対話的に選択（config.json の defaultTool がデフォルト）。

.PARAMETER Project
    プロジェクト名。省略時は対話的に選択（claude/codex のみ）。

.PARAMETER NonInteractive
    対話モードを無効化します。

.PARAMETER DryRun
    実際には実行せず、実行内容のプレビューのみ表示します。

.PARAMETER Local
    SSHを使わずローカルで直接起動します（claude/codex のみ）。

.EXAMPLE
    .\Start-All.ps1
    ツールとプロジェクトを対話的に選択して起動

.EXAMPLE
    .\Start-All.ps1 -Tool claude -Project "my-project"
    Claude Code を my-project で起動

.EXAMPLE
    .\Start-All.ps1 -Tool codex -Project "backend" -NonInteractive
    Codex CLI を非対話モードで起動
#>

param(
    [ValidateSet('claude', 'codex', 'copilot', '')]
    [string]$Tool = '',

    [string]$Project = '',

    [switch]$NonInteractive,
    [switch]$DryRun,
    [switch]$Local
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot "scripts\lib\LauncherCommon.psm1") -Force
Import-Module (Join-Path $ScriptRoot "scripts\lib\Config.psm1") -Force
$ConfigPath = Get-StartupConfigPath -StartupRoot $ScriptRoot

function Write-Info  { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "[ OK ]  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Error2 { param($msg) Write-Host "[ERR]   $msg" -ForegroundColor Red }
function Write-Banner {
    Write-Host ""
    Write-Host " ══════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host "   AI CLI ユニバーサルスタートアップツール v2.0" -ForegroundColor Magenta
    Write-Host "   Claude Code / Codex CLI / GitHub Copilot CLI" -ForegroundColor Magenta
    Write-Host " ══════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host ""
}

function Write-ClaudeOsStartupDashboard {
    param(
        [object]$Config,
        [string]$ConfiguredDefaultTool,
        [switch]$LocalMode,
        [switch]$NonInteractiveMode
    )

    $mode = if ($NonInteractiveMode) { 'Auto Mode' } else { 'Interactive Mode' }
    $execution = if ($LocalMode) { 'Local Preferred' } else { 'SSH Preferred' }
    $token = Get-LauncherTokenBudgetStatus
    $recentEntries = @()
    $recentSummary = [pscustomobject]@{ Total = 0; SuccessRate = 0; AverageElapsedMs = 0 }
    $recentToolResults = @()
    $metadataEntries = @()
    $toolStatistics = @()
    $agentLaneEvents = @()
    $backlogSummary = Get-LauncherBacklogSummary -TasksPath (Join-Path $ScriptRoot 'TASKS.md')
    if (Test-RecentProjectsEnabled -Config $Config) {
        $recentEntries = Get-LauncherRecentEntries -Config $Config -MaxCount 20
        $recentSummary = Get-LauncherRecentSummary -Entries $recentEntries
        $recentToolResults = Get-LauncherRecentToolResults -Entries $recentEntries
    }
    $metadataEntries = Get-LauncherMetadataEntries -Config $Config -MaxCount 20
    if (@($metadataEntries).Count -gt 0) {
        $toolStatistics = Get-LauncherToolStatistics -Entries $metadataEntries
    }
    else {
        $toolStatistics = Get-LauncherToolStatistics -Entries $recentEntries
    }
    $agentLaneEvents = Get-LauncherAgentLaneEvents -Config $Config -MetadataEntries $(if (@($metadataEntries).Count -gt 0) { $metadataEntries } else { $recentEntries }) -BacklogSummary $backlogSummary

    Write-Host " ClaudeOS" -ForegroundColor Cyan
    Write-Host " Claude Code Autonomous Development System" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " Mode: $mode" -ForegroundColor White
    Write-Host " Orchestration: Agent Teams (visualized lanes)" -ForegroundColor White
    Write-Host " SubAgents: Architect / DevAPI / DevUI / Ops / QA" -ForegroundColor White
    Write-Host " Preferred Execution: $execution" -ForegroundColor White
    Write-Host " Default Tool: $ConfiguredDefaultTool" -ForegroundColor White
    Write-Host " Token Budget: $($token.Zone) $(if ($null -ne $token.Percent) { "$($token.Percent)%" } else { '' }) $($token.Status)" -ForegroundColor White
    Write-Host " Agent Teams Backlog: count=$($backlogSummary.Count) priority=$($(if ($backlogSummary.Priorities.Count -gt 0) { $backlogSummary.Priorities -join ', ' } else { 'none' }))" -ForegroundColor White
    Write-Host " Recent Summary: success=$($recentSummary.SuccessRate)% avg=$($recentSummary.AverageElapsedMs)ms runs=$($recentSummary.Total)" -ForegroundColor White
    foreach ($lane in $agentLaneEvents) {
        Write-Host (" [{0}] {1}" -f $lane.lane, $lane.message) -ForegroundColor White
    }
    foreach ($entry in $recentToolResults) {
        $timeLabel = if ($entry.timestamp) {
            try { (Get-Date $entry.timestamp).ToString('MM-dd HH:mm') } catch { "$($entry.timestamp)" }
        }
        else {
            'n/a'
        }
        $elapsedLabel = if ($null -ne $entry.elapsedMs) { "$($entry.elapsedMs)ms" } else { 'n/a' }
        Write-Host " Recent Tool: $($entry.tool) result=$($entry.result) time=$timeLabel elapsed=$elapsedLabel" -ForegroundColor White
    }
    foreach ($stat in $toolStatistics) {
        Write-Host " Tool Stats: $($stat.tool) success=$($stat.successRate)% avg=$($stat.averageElapsedMs)ms runs=$($stat.runs)" -ForegroundColor White
    }
    Write-Host ""
}

# ===============================
# 設定読み込み
# ===============================

if (-not (Test-Path $ConfigPath)) {
    Write-Error2 "設定ファイルが見つかりません: $ConfigPath"
    Write-Info "config\config.json.template をコピーして config\config.json を作成してください。"
    exit 1
}

$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

Write-Banner
Write-ClaudeOsStartupDashboard -Config $Config -ConfiguredDefaultTool $Config.tools.defaultTool -LocalMode:$Local -NonInteractiveMode:$NonInteractive

# ===============================
# ツール選択
# ===============================

$defaultTool = $Config.tools.defaultTool

if ([string]::IsNullOrEmpty($Tool)) {
    if ($NonInteractive) {
        $Tool = $defaultTool
        Write-Info "ツール（デフォルト）: $Tool"
    }
    else {
        # 有効なツールを一覧表示
        $tools = @()
        $toolNames = @('claude', 'codex', 'copilot')
        $toolLabels = @{
            'claude'  = 'Claude Code      (Anthropic) - コード生成・エージェント作業'
            'codex'   = 'Codex CLI        (OpenAI)    - OpenAI APIを使ったコード生成'
            'copilot' = 'GitHub Copilot CLI (GitHub)  - シェルコマンド提案・説明'
        }

        Write-Host "--- 起動するAI CLIツールを選択してください ---" -ForegroundColor Cyan
        $idx = 1
        foreach ($t in $toolNames) {
            $toolConf = $Config.tools.$t
            if ($toolConf.enabled) {
                $mark = if ($t -eq $defaultTool) { " ★デフォルト" } else { "" }
                Write-Host "  [$idx] $($toolLabels[$t])$mark"
                $tools += $t
                $idx++
            }
        }
        Write-Host "  [0] 戻る" -ForegroundColor DarkGray
        Write-Host ""

        $sel = Read-Host "番号を入力"
        if ($sel -eq "0" -or [string]::IsNullOrEmpty($sel)) { exit 0 }
        $selIdx = [int]$sel - 1
        if ($selIdx -lt 0 -or $selIdx -ge $tools.Count) {
            Write-Error2 "無効な選択です。"
            exit 1
        }
        $Tool = $tools[$selIdx]
    }
}

Write-Info "選択されたツール: $Tool"

# ===============================
# 対応スクリプトに委譲
# ===============================

$scriptMap = @{
    'claude'  = Join-Path $PSScriptRoot "Start-ClaudeCode.ps1"
    'codex'   = Join-Path $PSScriptRoot "Start-CodexCLI.ps1"
    'copilot' = Join-Path $PSScriptRoot "Start-CopilotCLI.ps1"
}

$targetScript = $scriptMap[$Tool]
if (-not (Test-Path $targetScript)) {
    Write-Error2 "起動スクリプトが見つかりません: $targetScript"
    exit 1
}

# パラメータを構築
$params = @{}
if ($Project)        { $params['Project'] = $Project }
if ($NonInteractive) { $params['NonInteractive'] = $true }
if ($DryRun)         { $params['DryRun'] = $true }
if ($Local) { $params['Local'] = $true }

Write-Info "起動スクリプト: $targetScript"
Write-Host ""

$LASTEXITCODE = 0
& $targetScript @params
exit $LASTEXITCODE
