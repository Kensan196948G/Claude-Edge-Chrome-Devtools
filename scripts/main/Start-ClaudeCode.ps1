<#
.SYNOPSIS
    Claude Code startup script
.DESCRIPTION
    ClaudeOS Agent Teams lane: Architect / DevAPI / QA.
#>

param(
    [string]$Project = '',
    [switch]$Local,
    [switch]$NonInteractive,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force

$ScriptRoot = Get-StartupRoot -PSScriptRootPath $PSScriptRoot
$ConfigPath = Get-StartupConfigPath -StartupRoot $ScriptRoot

function Write-Info { param($Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Ok { param($Message) Write-Host "[ OK ]  $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Error2 { param($Message) Write-Host "[ERR]   $Message" -ForegroundColor Red }

$launchContext = New-LauncherExecutionContext
$Config = $null

try {
    $Config = Import-LauncherConfig -ConfigPath $ConfigPath
    $toolConfig = $Config.tools.claude
    if (-not $toolConfig.enabled) {
        throw 'Claude Code is disabled in config.json.'
    }

    Write-Info 'Checking Claude Code...'
    if (-not (Assert-LauncherToolAvailable -Command 'claude' -InstallCommand $toolConfig.installCommand -ToolLabel 'Claude Code' -NonInteractive:$NonInteractive)) {
        exit 1
    }
    Write-Ok 'Claude Code is available.'

    $apiKeyName = $toolConfig.apiKeyEnvVar
    $apiKey = Get-LauncherApiKeyValue -ApiKeyName $apiKeyName -EnvMap $toolConfig.env

    $Local = Resolve-LauncherMode -Config $Config -Local:$Local -NonInteractive:$NonInteractive -ConfigPath $ConfigPath

    # SSH モードではリモート側の認証を使うため、ローカルの API キー警告は不要
    if ($Local -and [string]::IsNullOrEmpty($apiKey)) {
        Show-LauncherApiKeyWarning -ApiKeyName $apiKeyName -LoginHint 'Use /login after Claude Code starts if you rely on account auth.' -ApiHint "Set environment variable $apiKeyName for API auth."
    }

    $linuxHost = $Config.linuxHost
    $linuxBase = $Config.linuxBase
    $Project = Resolve-LauncherProject -Config $Config -Project $Project -Local:$Local -NonInteractive:$NonInteractive -LinuxHost $linuxHost
    $modeName = Get-LauncherModeName -Local:$Local
    $launchContext.Project = $Project
    $launchContext.Mode = $modeName
    $launchContext.Tool = 'claude'
    $modeLabel = Get-LauncherModeLabel -Project $Project -Local:$Local -ProjectsDir $Config.projectsDir -LinuxHost $linuxHost -LinuxBase $linuxBase

    if (-not (Confirm-LauncherStart -ToolName 'Claude Code' -Project $Project -ModeLabel $modeLabel -NonInteractive:$NonInteractive)) {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    if ($Local) {
        $localProjectDir = Join-Path $Config.projectsDir $Project
        Set-Location $localProjectDir
        Set-LauncherEnvironment -EnvMap $toolConfig.env

        if ($DryRun) {
            foreach ($line in (New-LauncherDryRunMessage -Command 'claude' -Arguments @($toolConfig.args) -WorkingDirectory $localProjectDir)) {
                Write-Info $line
            }
            $launchContext.Result = 'success'
            exit 0
        }

        Sync-ProjectTemplate -TemplatePath (Join-Path $ScriptRoot 'scripts\templates\CLAUDE.md') -TargetPath (Join-Path $localProjectDir 'CLAUDE.md') -Label 'CLAUDE.md'
        & claude @($toolConfig.args)
        $launchContext.Result = if ($LASTEXITCODE -eq 0) { 'success' } else { 'failure' }
        exit $LASTEXITCODE
    }

    $linuxProject = "$linuxBase/$Project"
    $claudeArgs = $toolConfig.args -join ' '

    # ssh -tt HOST "cd PROJECT && claude ARGS" の直接コマンド
    $runScript = "cd '$linuxProject' && claude $claudeArgs"

    if ($DryRun) {
        $dryRunLines = New-LauncherDryRunMessage -Command 'claude' -LinuxHost $linuxHost -RemoteScript $runScript
        Write-Info $dryRunLines[0]
        Write-Host $dryRunLines[1]
        $launchContext.Result = 'success'
        exit 0
    }

    Write-Info "Connecting via SSH: $linuxHost"
    $sshExitCode = Invoke-LauncherSshScript -LinuxHost $linuxHost -RunScript $runScript -RemoteScriptName "run-claude-$Project.sh"
    # 255 は SSH 接続失敗（Invoke-LauncherSshScript 内で診断メッセージ表示済み）
    # それ以外の終了コードはツールの正常終了として扱う
    if ($sshExitCode -eq 255) {
        $launchContext.Result = 'failure'
        exit $sshExitCode
    }

    $launchContext.Result = 'success'
    Write-Ok 'Claude Code session finished.'
}
catch {
    if ($_.Exception.Message -eq 'USER_CANCELLED') {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    $launchContext.Result = 'failure'
    Write-Error2 $_.Exception.Message
    exit 1
}
finally {
    if ($Config) {
        Complete-LauncherExecutionContext -Context $launchContext -Config $Config
    }
}
