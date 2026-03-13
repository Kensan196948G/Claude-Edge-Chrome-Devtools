<#
.SYNOPSIS
    GitHub Copilot CLI startup script.
.DESCRIPTION
    ClaudeOS Agent Teams lane entry for DevUI / Ops / QA.
    See docs/common/08_AgentTeams対応表.md for the mapping table.
#>

param(
    [string]$Project = '',
    [switch]$Local,
    [switch]$NonInteractive,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StartupRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $StartupRoot 'scripts\lib\LauncherCommon.psm1') -Force
Import-Module (Join-Path $StartupRoot 'scripts\lib\Config.psm1') -Force

$ConfigPath = Get-StartupConfigPath -StartupRoot $StartupRoot

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "[ OK ] $Message" -ForegroundColor Green }
function Write-Err { param([string]$Message) Write-Host "[ERR ] $Message" -ForegroundColor Red }

$launchContext = New-LauncherExecutionContext
$config = $null

try {
    $config = Import-LauncherConfig -ConfigPath $ConfigPath
    $toolConfig = $config.tools.copilot
    if (-not $toolConfig.enabled) {
        throw 'GitHub Copilot CLI is disabled in config.json.'
    }

    $command = if ([string]::IsNullOrWhiteSpace($toolConfig.command)) { 'gh' } else { "$($toolConfig.command)" }
    $arguments = if ($null -ne $toolConfig.args) { @($toolConfig.args | ForEach-Object { "$_" }) } else { @('copilot') }

    if ($Local) {
        Write-Info 'Checking GitHub Copilot CLI availability...'
        if (-not (Assert-LauncherToolAvailable -Command $command -InstallCommand $toolConfig.installCommand -ToolLabel 'GitHub Copilot CLI' -NonInteractive:$NonInteractive)) {
            exit 1
        }
        Write-Ok 'GitHub Copilot CLI command is available.'
    }

    $Local = Resolve-LauncherMode -Config $config -Local:$Local -NonInteractive:$NonInteractive -ConfigPath $ConfigPath
    $linuxHost = $config.linuxHost
    $linuxBase = $config.linuxBase
    $Project = Resolve-LauncherProject -Config $config -Project $Project -Local:$Local -NonInteractive:$NonInteractive -LinuxHost $linuxHost
    $modeName = Get-LauncherModeName -Local:$Local
    $modeLabel = Get-LauncherModeLabel -Project $Project -Local:$Local -ProjectsDir $config.projectsDir -LinuxHost $linuxHost -LinuxBase $linuxBase

    $launchContext.Project = $Project
    $launchContext.Mode = $modeName
    $launchContext.Tool = 'copilot'

    if (-not (Confirm-LauncherStart -ToolName 'GitHub Copilot CLI' -Project $Project -ModeLabel $modeLabel -NonInteractive:$NonInteractive)) {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    if ($Local) {
        $projectDir = Join-Path $config.projectsDir $Project
        if (-not (Test-Path $projectDir)) {
            throw "Project directory not found: $projectDir"
        }

        Write-Info "Starting GitHub Copilot CLI locally for $Project"
        Set-Location $projectDir
        Set-LauncherEnvironment -EnvMap $toolConfig.env

        # CopilotCLI\AGENTS.md を正規ソースとして使用（フォールバック: scripts\templates\copilot-instructions.md）
        $copilotTemplatePath = Join-Path $StartupRoot 'CopilotCLI\AGENTS.md'
        if (-not (Test-Path $copilotTemplatePath)) {
            $copilotTemplatePath = Join-Path $StartupRoot 'scripts\templates\copilot-instructions.md'
        }
        Sync-ProjectTemplate `
            -TemplatePath $copilotTemplatePath `
            -TargetPath (Join-Path $projectDir '.github\copilot-instructions.md') `
            -Label 'copilot-instructions.md' `
            -EnsureParentDirectory

        if ($DryRun) {
            foreach ($line in (New-LauncherDryRunMessage -Command $command -Arguments $arguments -WorkingDirectory $projectDir)) {
                Write-Info $line
            }
            $launchContext.Result = 'success'
            exit 0
        }

        # Start-Process -NoNewWindow -Wait を使用してコンソール制御を正しく渡す
        # & $command @arguments では PowerShell の引数展開が問題を引き起こす場合がある
        $process = Start-Process -FilePath $command -ArgumentList $arguments `
            -WorkingDirectory $projectDir -NoNewWindow -Wait -PassThru
        $exitCode = if ($null -ne $process -and $null -ne $process.ExitCode) { $process.ExitCode } else { 0 }
        $launchContext.Result = if ($exitCode -eq 0) { 'success' } else { 'failure' }
        exit $exitCode
    }

    $linuxProject = "$linuxBase/$Project"

    # SSH（Linux）モードでは config と同じ copilot --yolo を使用
    $sshArgs = if (@($arguments).Count -gt 0) { $arguments -join ' ' } else { '--yolo' }
    $runScript = "cd '$linuxProject' && $command $sshArgs"

    if ($DryRun) {
        $lines = New-LauncherDryRunMessage -Command $command -LinuxHost $linuxHost -RemoteScript $runScript
        Write-Info $lines[0]
        Write-Host $lines[1]
        $launchContext.Result = 'success'
        exit 0
    }

    Write-Info "Connecting via SSH: $linuxHost"
    $sshExitCode = Invoke-LauncherSshScript -LinuxHost $linuxHost -RunScript $runScript -RemoteScriptName "run-copilot-$Project.sh"
    # 255 は SSH 接続失敗（Invoke-LauncherSshScript 内で診断メッセージ表示済み）
    # それ以外の終了コードはツールの正常終了として扱う
    if ($sshExitCode -eq 255) {
        $launchContext.Result = 'failure'
        exit $sshExitCode
    }

    $launchContext.Result = 'success'
    Write-Ok 'GitHub Copilot CLI session finished.'
    exit 0
}
catch {
    if ($_.Exception.Message -eq 'USER_CANCELLED') {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    $launchContext.Result = 'failure'
    Write-Err $_.Exception.Message
    exit 1
}
finally {
    if ($null -ne $config) {
        Complete-LauncherExecutionContext -Context $launchContext -Config $config
    }
}
