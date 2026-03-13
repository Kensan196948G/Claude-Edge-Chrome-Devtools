# ============================================================
# Start-Menu.ps1 - AI CLI 統合メニュー
# ClaudeOS Agent Teams 対応: Agent Orchestrator / Scrum Master の操作入口
# docs/common/08_AgentTeams対応表.md を参照
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ProjectRoot "scripts\lib\LauncherCommon.psm1") -Force
Import-Module (Join-Path $ProjectRoot "scripts\lib\Config.psm1") -Force
Import-Module (Join-Path $ProjectRoot "scripts\lib\MenuCommon.psm1") -Force

Set-Location $ProjectRoot

$ConfigPath = Get-StartupConfigPath -StartupRoot $ProjectRoot
$Config = Import-LauncherConfig -ConfigPath $ConfigPath
$LinuxHost = if ($Config.linuxHost) { $Config.linuxHost } else { "未設定" }
$LinuxBase = if ($Config.linuxBase) { $Config.linuxBase } else { "未設定" }
$LocalDir  = if ($Config.projectsDir) { $Config.projectsDir } else { "未設定" }
$ShellExe = Get-LauncherShell

function Get-RecentProjectSortWeight {
    param([object]$Entry)

    switch ($Entry.result) {
        'success' { return 3 }
        'unknown' { return 2 }
        'cancelled' { return 1 }
        'failure' { return 0 }
        default { return 2 }
    }
}

function Get-RecentProjectSuccessRate {
    param([object]$Entry)

    $matchingEntries = @(
        Get-RecentProjects -HistoryPath $Config.recentProjects.historyFile |
            Where-Object {
                $_.project -eq $Entry.project -and
                $_.tool -eq $Entry.tool -and
                $_.mode -eq $Entry.mode
            }
    )
    return (Get-LauncherRecentSummary -Entries $matchingEntries).SuccessRate
}

function Get-SortedRecentProjects {
    param(
        [object[]]$Entries,
        [ValidateSet('success', 'timestamp', 'elapsed')]
        [string]$SortMode = 'success'
    )

    switch ($SortMode) {
        'timestamp' {
            return @(
                $Entries |
                    Sort-Object @{ Expression = {
                        if ($_.timestamp) { try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue } }
                        else { [datetimeoffset]::MinValue }
                    }; Descending = $true }
            )
        }
        'elapsed' {
            return @(
                $Entries |
                    Sort-Object `
                        @{ Expression = {
                            if ($null -ne $_.elapsedMs) { [int]$_.elapsedMs } else { [int]::MaxValue }
                        }; Descending = $false }, `
                        @{ Expression = { Get-RecentProjectSortWeight -Entry $_ }; Descending = $true }, `
                        @{ Expression = {
                            if ($_.timestamp) { try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue } }
                            else { [datetimeoffset]::MinValue }
                        }; Descending = $true }
            )
        }
    }

    return @(
        $Entries |
            Sort-Object `
                @{ Expression = { Get-RecentProjectSuccessRate -Entry $_ }; Descending = $true }, `
                @{ Expression = { Get-RecentProjectSortWeight -Entry $_ }; Descending = $true }, `
                @{ Expression = {
                    if ($_.timestamp) { try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue } }
                    else { [datetimeoffset]::MinValue }
                }; Descending = $true }
    )
}

function Get-FilteredRecentProjects {
    param(
        [object[]]$Entries,
        [string]$ToolFilter = '',
        [string]$SearchQuery = '',
        [ValidateSet('success', 'timestamp', 'elapsed')]
        [string]$SortMode = 'success'
    )

    $filtered = @($Entries)
    if (-not [string]::IsNullOrWhiteSpace($ToolFilter)) {
        $filtered = @($filtered | Where-Object { $_.tool -eq $ToolFilter })
    }
    if (-not [string]::IsNullOrWhiteSpace($SearchQuery)) {
        $filtered = @($filtered | Where-Object { $_.project -like "*$SearchQuery*" })
    }
    return @(@(Get-SortedRecentProjects -Entries $filtered -SortMode $SortMode))
}

function Get-RecentProjectLabel {
    param([Parameter(Mandatory)][object]$Entry)

    $tool = if ([string]::IsNullOrWhiteSpace($Entry.tool)) { $Config.tools.defaultTool } else { $Entry.tool }
    $mode = if ($Entry.mode -eq 'local') { 'Local' } else { 'SSH' }
    $timestamp = if ($Entry.timestamp) {
        try { (Get-Date $Entry.timestamp).ToString('yyyy-MM-dd HH:mm') } catch { $Entry.timestamp }
    }
    else {
        '時刻不明'
    }

    $result = switch ($Entry.result) {
        'success' { 'OK' }
        'failure' { 'FAIL' }
        'cancelled' { 'CANCEL' }
        default { 'UNKNOWN' }
    }

    $elapsed = if ($null -ne $Entry.elapsedMs) { "{0}ms" -f [int]$Entry.elapsedMs } else { 'n/a' }
    $matchingEntries = @(
        Get-RecentProjects -HistoryPath $Config.recentProjects.historyFile |
            Where-Object {
                $_.project -eq $Entry.project -and
                $_.tool -eq $Entry.tool -and
                $_.mode -eq $Entry.mode
            }
    )
    $summary = Get-LauncherRecentSummary -Entries $matchingEntries
    $successRate = if ($summary.Total -gt 0) { "$($summary.SuccessRate)%" } else { 'n/a' }

    return "{0} [{1}/{2}/{3}] ({4}, {5}, success {6})" -f $Entry.project, $tool, $mode, $result, $timestamp, $elapsed, $successRate
}

function Get-RecentProjectColor {
    param([Parameter(Mandatory)][object]$Entry)

    switch ($Entry.result) {
        'success' { return 'Green' }
        'failure' { return 'Red' }
        'cancelled' { return 'Yellow' }
        default { return 'Cyan' }
    }
}

function Get-RecentProjectLaunchSpec {
    param([Parameter(Mandatory)][object]$Entry)

    $tool = if ([string]::IsNullOrWhiteSpace($Entry.tool)) { $Config.tools.defaultTool } else { $Entry.tool }
    $modeIsLocal = ($Entry.mode -eq 'local')
    $scriptMap = @{
        'claude' = "scripts\main\Start-ClaudeCode.ps1"
        'codex' = "scripts\main\Start-CodexCLI.ps1"
        'copilot' = "scripts\main\Start-CopilotCLI.ps1"
    }

    $scriptArgs = @("-Project", $Entry.project)
    if ($modeIsLocal) {
        $scriptArgs += "-Local"
    }

    return [pscustomobject]@{
        tool = $tool
        file = $scriptMap[$tool]
        scriptArgs = $scriptArgs
    }
}

function Show-Menu {
    Clear-Host
    $sep = " " + ("=" * 55)

    Write-Host ""
    Write-Host $sep -ForegroundColor Cyan
    Write-Host "   AI CLI ユニバーサルスタートアップツール v2.0" -ForegroundColor Cyan
    Write-Host "   Claude Code / Codex CLI / GitHub Copilot CLI" -ForegroundColor DarkCyan
    Write-Host $sep -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  -- SSH 接続 ($LinuxHost -> $LinuxBase) --" -ForegroundColor Yellow
    Write-Host "    S1. Claude Code を起動" -ForegroundColor Yellow
    Write-Host "    S2. Codex CLI を起動" -ForegroundColor Yellow
    Write-Host "    S3. GitHub Copilot CLI を起動" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "  -- ローカル ($LocalDir) --" -ForegroundColor Green
    Write-Host "    L1. Claude Code を起動" -ForegroundColor Green
    Write-Host "    L2. Codex CLI を起動" -ForegroundColor Green
    Write-Host "    L3. GitHub Copilot CLI を起動" -ForegroundColor Green
    Write-Host ""

    Write-Host "  -- 診断・セットアップ --" -ForegroundColor Magenta
    Write-Host "    5.  ツール確認・診断" -ForegroundColor Magenta
    Write-Host "    6.  ドライブマッピング診断" -ForegroundColor Magenta
    Write-Host "    7.  Windows Terminal セットアップ" -ForegroundColor Magenta
    Write-Host ""

    Write-Host "    0.  終了" -ForegroundColor Gray
    Write-Host ""
    Write-Host $sep -ForegroundColor DarkGray
    Write-Host "  推奨: Windows Terminal から実行" -ForegroundColor DarkGray
    Write-Host $sep -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-MenuScript {
    param(
        [Parameter(Mandatory)]
        [string]$File,
        [string[]]$ScriptArgs = @()
    )

    & $ShellExe -NoProfile -ExecutionPolicy Bypass -File $File @ScriptArgs
    Write-Host ""
    Write-Host "  何かキーを押してメニューに戻ります..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Invoke-ToolFromMenu {
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [switch]$Local
    )

    $args = @("-Tool", $Tool)
    if ($Local) {
        $args += "-Local"
    }

    Invoke-MenuScript -File "scripts\main\Start-All.ps1" -ScriptArgs $args
}

if ($env:AI_STARTUP_MENU_TEST_EXPORT -eq '1') {
    return
}

while ($true) {
    Show-Menu
    $choice = Read-Host "  番号を入力してください"

    switch ($choice.ToUpper()) {
        "S1" { Invoke-ToolFromMenu -Tool "claude" }
        "S2" { Invoke-ToolFromMenu -Tool "codex" }
        "S3" { Invoke-ToolFromMenu -Tool "copilot" }
        "L1" { Invoke-ToolFromMenu -Tool "claude" -Local }
        "L2" { Invoke-ToolFromMenu -Tool "codex" -Local }
        "L3" { Invoke-ToolFromMenu -Tool "copilot" -Local }
        "5"  { Invoke-MenuScript -File "scripts\test\Test-AllTools.ps1" }
        "6"  { Invoke-MenuScript -File "scripts\test\test-drive-mapping.ps1" }
        "7"  { Invoke-MenuScript -File "scripts\setup\setup-windows-terminal.ps1" }
        "0"  { exit 0 }
        default {
            Write-Host ""
            Write-Host "  無効な入力です。もう一度選択してください。" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
