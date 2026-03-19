function Get-StartupRoot {
    param(
        [Parameter(Mandatory)]
        [string]$PSScriptRootPath
    )

    return (Split-Path -Parent (Split-Path -Parent $PSScriptRootPath))
}

function Get-StartupConfigPath {
    param(
        [Parameter(Mandatory)]
        [string]$StartupRoot
    )

    if ($env:AI_STARTUP_CONFIG_PATH) {
        return $env:AI_STARTUP_CONFIG_PATH
    }

    return (Join-Path $StartupRoot "config\\config.json")
}

function Import-LauncherConfig {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "設定ファイルが見つかりません: $ConfigPath"
    }

    return (Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Test-LauncherCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Assert-LauncherToolAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [string]$InstallCommand,
        [Parameter(Mandatory)]
        [string]$ToolLabel,
        [switch]$NonInteractive
    )

    if (Test-LauncherCommand -Command $Command) {
        return $true
    }

    Write-Host "[WARN] $Command コマンドが見つかりません。" -ForegroundColor Yellow
    Write-Host "[INFO] インストール: $InstallCommand" -ForegroundColor Cyan
    if ($NonInteractive) {
        return $false
    }

    $answer = Read-Host "今すぐインストールしますか？ [y/N]"
    if ($answer -match '^[yY]') {
        Invoke-Expression $InstallCommand
        return (Test-LauncherCommand -Command $Command)
    }

    return $false
}

function Get-LauncherApiKeyValue {
    param(
        [string]$ApiKeyName,
        [object]$EnvMap
    )

    if ([string]::IsNullOrWhiteSpace($ApiKeyName)) {
        return $null
    }

    $value = [Environment]::GetEnvironmentVariable($ApiKeyName)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
    }

    if ($EnvMap) {
        $envProperty = $EnvMap.PSObject.Properties[$ApiKeyName]
        if ($envProperty -and -not [string]::IsNullOrWhiteSpace($envProperty.Value)) {
            return $envProperty.Value
        }
    }

    return $null
}

function Show-LauncherApiKeyWarning {
    param(
        [string]$ApiKeyName,
        [string]$LoginHint,
        [string]$ApiHint
    )

    if ([string]::IsNullOrWhiteSpace($ApiKeyName)) {
        return
    }

    Write-Host "[WARN] $ApiKeyName は未設定です。" -ForegroundColor Yellow
    if ($LoginHint) {
        Write-Host "[INFO] $LoginHint" -ForegroundColor Cyan
    }
    if ($ApiHint) {
        Write-Host "[INFO] $ApiHint" -ForegroundColor Cyan
    }
}

function Resolve-LauncherMode {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [switch]$Local,
        [switch]$NonInteractive,
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if ($Local) {
        return $true
    }

    if ($Config.linuxHost) {
        return $false
    }

    Write-Host ""
    Write-Host "=== Linux接続先未設定 ===" -ForegroundColor Yellow
    Write-Host "config.json に linuxHost が設定されていません。" -ForegroundColor Yellow
    Write-Host "リモート実行を使うには設定が必要です。" -ForegroundColor Yellow
    Write-Host ""

    if ($NonInteractive) {
        throw "config.json に linuxHost が未設定のため、非対話モードでは続行できません: $ConfigPath"
    }

    Write-Host "[L] ローカル実行を続ける" -ForegroundColor Cyan
    Write-Host "[C] config.json を開いて設定する" -ForegroundColor Cyan
    Write-Host "[0] 終了" -ForegroundColor Cyan
    $choice = Read-Host "選択してください"

    switch ($choice.ToUpper()) {
        "L" { return $true }
        "C" {
            Start-Process notepad.exe $ConfigPath
            throw "USER_CANCELLED"
        }
        default {
            throw "USER_CANCELLED"
        }
    }
}

function Resolve-LauncherProject {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [string]$Project,
        [switch]$Local,
        [switch]$NonInteractive,
        [string]$LinuxHost
    )

    if ($Project) {
        return $Project
    }

    $projectsRoot = if ($Local) { $Config.projectsDir } else { $Config.sshProjectsDir }

    if (-not (Test-Path $projectsRoot)) {
        throw "プロジェクトルートが見つかりません: $projectsRoot"
    }

    $dirs = Get-ChildItem -Path $projectsRoot -Directory | Sort-Object Name
    if ($Local -and $Config.localExcludes) {
        $dirs = $dirs | Where-Object { $_.Name -notin $Config.localExcludes }
    }

    if (-not $dirs) {
        throw "プロジェクトが見つかりません: $projectsRoot"
    }

    if ($NonInteractive) {
        throw "非対話モードでは -Project の指定が必要です。"
    }

    Show-LauncherProjectChoices -Projects $dirs.Name -Local:$Local -LinuxHost $LinuxHost

    $num = Read-Host "番号を入力してください"
    $numInt = $num -as [int]
    if (-not $numInt -or $numInt -lt 1 -or $numInt -gt $dirs.Count) {
        throw "USER_CANCELLED"
    }

    return $dirs[$numInt - 1].Name
}

function Show-LauncherProjectChoices {
    param(
        [Parameter(Mandatory)]
        [string[]]$Projects,
        [switch]$Local,
        [string]$LinuxHost
    )

    Write-Host ""
    Write-Host "=== プロジェクト選択 ===" -ForegroundColor Cyan
    if (-not $Local -and $LinuxHost) {
        Write-Host "接続先: $LinuxHost" -ForegroundColor DarkGray
    }
    for ($i = 0; $i -lt $Projects.Count; $i++) {
        "{0,2}: {1}" -f ($i + 1), $Projects[$i] | Write-Host
    }
}

function Get-LauncherModeLabel {
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        [switch]$Local,
        [string]$ProjectsDir,
        [string]$LinuxHost,
        [string]$LinuxBase
    )

    if ($Local) {
        return "ローカル  $ProjectsDir\$Project"
    }

    return "SSH  $LinuxHost → $LinuxBase/$Project"
}

function Get-LauncherModeName {
    param([switch]$Local)

    if ($Local) {
        return 'local'
    }

    return 'ssh'
}

function New-LauncherDryRunMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = '',
        [string]$LinuxHost = '',
        [string]$RemoteScript = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($RemoteScript)) {
        return @(
            "[DryRun] SSH接続先: $LinuxHost"
            $RemoteScript
        )
    }

    $joinedArgs = if ($Arguments.Count -gt 0) { " " + ($Arguments -join ' ') } else { '' }
    return @("[DryRun] cd $WorkingDirectory && $Command$joinedArgs")
}

function Confirm-LauncherStart {
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,
        [Parameter(Mandatory)]
        [string]$Project,
        [Parameter(Mandatory)]
        [string]$ModeLabel,
        [switch]$NonInteractive
    )

    if ($NonInteractive) {
        return $true
    }

    Write-Host ""
    Write-Host "=== 起動確認 ===" -ForegroundColor Yellow
    Write-Host "ツール   : $ToolName"
    Write-Host "プロジェクト: $Project"
    Write-Host "実行モード: $ModeLabel"
    $confirm = Read-Host "開始しますか？ (Y/n)"
    if ([string]::IsNullOrWhiteSpace($confirm)) {
        return $true
    }
    return ($confirm -notmatch '^(n|no)$')
}

function Set-LauncherEnvironment {
    param(
        [Parameter(Mandatory)]
        [object]$EnvMap
    )

    foreach ($p in $EnvMap.PSObject.Properties) {
        if ($null -ne $p.Value -and "$($p.Value)" -ne "") {
            [Environment]::SetEnvironmentVariable($p.Name, "$($p.Value)", "Process")
        }
    }
}

function ConvertTo-BashExports {
    param(
        [Parameter(Mandatory)]
        [object]$EnvMap
    )

    $lines = @()
    foreach ($p in $EnvMap.PSObject.Properties) {
        if ($null -ne $p.Value -and "$($p.Value)" -ne "") {
            $escaped = "$($p.Value)".Replace('"', '\"')
            $lines += "export $($p.Name)=""$escaped"""
        }
    }

    return ($lines -join "`n")
}

function Sync-ProjectTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [Parameter(Mandatory)]
        [string]$Label,
        [switch]$EnsureParentDirectory
    )

    if (-not (Test-Path $TemplatePath)) {
        return
    }

    if ($EnsureParentDirectory) {
        $parent = Split-Path -Parent $TargetPath
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }

    $needsCopy = $true
    if (Test-Path $TargetPath) {
        $src = Get-Content $TemplatePath -Raw -Encoding UTF8
        $dst = Get-Content $TargetPath -Raw -Encoding UTF8
        if ($src -eq $dst) {
            $needsCopy = $false
        }
    }

    if ($needsCopy) {
        Copy-Item $TemplatePath $TargetPath -Force
        Write-Host "[OK] $Label を配置/更新しました: $TargetPath" -ForegroundColor Green
    } else {
        Write-Host "[INFO] $Label は最新です: $TargetPath" -ForegroundColor Cyan
    }
}

function New-RemoteTemplateDeployScript {
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [Parameter(Mandatory)]
        [string]$Label,
        [switch]$EnsureParentDirectory
    )

    if (-not (Test-Path $TemplatePath)) {
        return ""
    }

    $content = Get-Content $TemplatePath -Raw -Encoding UTF8
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
    $mkdir = ""
    if ($EnsureParentDirectory) {
        $parent = Split-Path -Parent $TargetPath
        if ($parent) {
            $mkdir = "mkdir -p ""$parent""`n"
        }
    }

    return @"
$mkdir
TMP_FILE=`$(mktemp)
printf '%s' '$base64' | base64 -d > "`$TMP_FILE"
if [ ! -f "$TargetPath" ] || ! cmp -s "`$TMP_FILE" "$TargetPath"; then
  mv "`$TMP_FILE" "$TargetPath"
  echo "[OK] $Label を配置/更新しました: $TargetPath"
else
  rm -f "`$TMP_FILE"
  echo "[INFO] $Label は最新です: $TargetPath"
fi
"@
}

function Invoke-LauncherSshScript {
    param(
        [Parameter(Mandatory)]
        [string]$LinuxHost,
        [Parameter(Mandatory)]
        [string]$RunScript,
        [Parameter(Mandatory)]
        [string]$RemoteScriptName
    )

    if ($env:AI_STARTUP_SSH_CAPTURE_DIR) {
        $captureDir = $env:AI_STARTUP_SSH_CAPTURE_DIR
        if (-not (Test-Path $captureDir)) {
            New-Item -ItemType Directory -Force -Path $captureDir | Out-Null
        }

        Set-Content -Path (Join-Path $captureDir "host.txt") -Value $LinuxHost -Encoding UTF8
        Set-Content -Path (Join-Path $captureDir "script-name.txt") -Value $RemoteScriptName -Encoding UTF8
        Set-Content -Path (Join-Path $captureDir "script.sh") -Value $RunScript -Encoding UTF8
        Write-Host "[INFO] SSH_CAPTURE $LinuxHost $RemoteScriptName" -ForegroundColor DarkGray
        return 0
    }

    $sshCommand = if ($env:AI_STARTUP_SSH_EXE) { $env:AI_STARTUP_SSH_EXE } else { "ssh" }
    $connectTimeout = if ($env:AI_STARTUP_SSH_CONNECT_TIMEOUT) { $env:AI_STARTUP_SSH_CONNECT_TIMEOUT } else { "10" }

    # PowerShell の & 演算子は対話型プログラムのコンソール制御を妨げることがある。
    # Start-Process -NoNewWindow -Wait でコンソールを直接 SSH に渡す。
    Write-Host "[INFO] SSH 接続中: $LinuxHost ..." -ForegroundColor Cyan

    $sshArgList = @("-tt",
        "-o", "ConnectTimeout=$connectTimeout",
        "-o", "StrictHostKeyChecking=accept-new",
        $LinuxHost, $RunScript)

    $process = Start-Process -FilePath $sshCommand -ArgumentList $sshArgList `
        -NoNewWindow -Wait -PassThru
    $exitCode = if ($null -ne $process.ExitCode) { $process.ExitCode } else { 0 }

    if ($exitCode -eq 255) {
        Write-Host "[ERR]  SSH 接続に失敗しました: $LinuxHost" -ForegroundColor Red
        Write-Host "[INFO] 確認事項:" -ForegroundColor Cyan
        Write-Host "  1. ssh $LinuxHost echo test  で手動接続を確認" -ForegroundColor White
        Write-Host "  2. ~/.ssh/config のホスト名・鍵設定を確認" -ForegroundColor White
        Write-Host "  3. ping $LinuxHost  でネットワーク疎通を確認" -ForegroundColor White
        Write-Host "  4. ssh -vvv $LinuxHost  で詳細ログを確認" -ForegroundColor White
    }

    return $exitCode
}

function Get-LauncherShell {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        return "pwsh.exe"
    }

    return "powershell.exe"
}

function Write-LauncherExecutionResult {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Project,
        [Parameter(Mandatory)]
        [ValidateSet('claude', 'codex', 'copilot')]
        [string]$Tool,
        [Parameter(Mandatory)]
        [ValidateSet('local', 'ssh')]
        [string]$Mode,
        [Parameter(Mandatory)]
        [ValidateSet('success', 'failure', 'cancelled', 'unknown')]
        [string]$Result,
        [int]$ElapsedMs = 0
    )

    if (-not (Get-Command Update-RecentProjects -ErrorAction SilentlyContinue)) {
        return
    }

    if ($null -eq $Config.recentProjects -or -not $Config.recentProjects.enabled -or [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile)) {
        return
    }

    Update-RecentProjects `
        -ProjectName $Project `
        -Tool $Tool `
        -Mode $Mode `
        -Result $Result `
        -ElapsedMs $ElapsedMs `
        -HistoryPath $Config.recentProjects.historyFile `
        -MaxHistory $Config.recentProjects.maxHistory
}

function Get-LauncherMetadataLogPath {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    if ($Config.logging -and -not [string]::IsNullOrWhiteSpace($Config.logging.logDir)) {
        return (Join-Path $Config.logging.logDir ("launch-metadata-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd')))
    }

    if ($Config.recentProjects -and -not [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile)) {
        $historyDir = Split-Path -Parent ([Environment]::ExpandEnvironmentVariables($Config.recentProjects.historyFile))
        if (-not [string]::IsNullOrWhiteSpace($historyDir)) {
            return (Join-Path $historyDir ("launch-metadata-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd')))
        }
    }

    return $null
}

function Get-LauncherMetadataEntries {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [int]$MaxCount = 20
    )

    $logPath = Get-LauncherMetadataLogPath -Config $Config
    if ([string]::IsNullOrWhiteSpace($logPath)) {
        return @()
    }

    $logDir = Split-Path -Parent $logPath
    if ([string]::IsNullOrWhiteSpace($logDir) -or -not (Test-Path $logDir)) {
        return @()
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -Path $logDir -Filter 'launch-metadata-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    foreach ($file in $files) {
        foreach ($line in @(Get-Content -Path $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            try {
                $entries.Add(($line | ConvertFrom-Json))
            }
            catch {
            }
            if ($entries.Count -ge $MaxCount) {
                break
            }
        }
        if ($entries.Count -ge $MaxCount) {
            break
        }
    }

    return @(
        $entries |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First $MaxCount
    )
}

function Get-LauncherBacklogSummary {
    param(
        [string]$TasksPath = (Join-Path (Get-Location) 'TASKS.md')
    )

    if (-not (Test-Path $TasksPath)) {
        return [pscustomobject]@{
            Count = 0
            Priorities = @()
        }
    }

    $tasks = @(Get-Content -Path $TasksPath -Encoding UTF8 | Where-Object {
        $_ -match '^\d+\.\s' -and $_ -notmatch '\[DONE\]'
    })
    $priorities = @(
        $tasks |
            ForEach-Object {
                if ($_ -match '\[Priority:([^\]]+)\]') { $Matches[1] }
            } |
            Where-Object { $_ } |
            Group-Object |
            Sort-Object Name |
            ForEach-Object { "{0}:{1}" -f $_.Name, $_.Count }
    )

    return [pscustomobject]@{
        Count = $tasks.Count
        Priorities = $priorities
    }
}

function Write-LauncherMetadataLog {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [pscustomobject]$Entry
    )

    $logPath = Get-LauncherMetadataLogPath -Config $Config
    if ([string]::IsNullOrWhiteSpace($logPath)) {
        return
    }

    $logDir = Split-Path -Parent $logPath
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $line = $Entry | ConvertTo-Json -Compress -Depth 6
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

function New-LauncherExecutionContext {
    return [pscustomobject]@{
        StartTime = Get-Date
        Result = 'unknown'
        Project = $null
        Mode = $null
        Tool = $null
    }
}

function Complete-LauncherExecutionContext {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,
        [Parameter(Mandatory)]
        [object]$Config
    )

    if (-not $Context.Project -or -not $Context.Mode -or -not $Context.Tool) {
        return
    }

    $elapsedMs = [int][Math]::Max(0, ((Get-Date) - $Context.StartTime).TotalMilliseconds)
    Write-LauncherExecutionResult -Config $Config -Project $Context.Project -Tool $Context.Tool -Mode $Context.Mode -Result $Context.Result -ElapsedMs $elapsedMs
    Write-LauncherMetadataLog -Config $Config -Entry ([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        project = $Context.Project
        tool = $Context.Tool
        mode = $Context.Mode
        result = $Context.Result
        elapsedMs = $elapsedMs
        host = if ($Config.linuxHost) { $Config.linuxHost } else { $env:COMPUTERNAME }
    })
}

function Get-LauncherRecentSummary {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries
    )

    $total = @($Entries).Count
    if ($total -eq 0) {
        return [pscustomobject]@{
            Total = 0
            SuccessRate = 0
            AverageElapsedMs = 0
        }
    }

    $successCount = @($Entries | Where-Object { $_.result -eq 'success' }).Count
    $elapsedEntries = @($Entries | Where-Object { $null -ne $_.elapsedMs })
    $avgElapsed = if ($elapsedEntries.Count -gt 0) {
        [int](($elapsedEntries | Measure-Object -Property elapsedMs -Average).Average)
    }
    else {
        0
    }

    return [pscustomobject]@{
        Total = $total
        SuccessRate = [int][Math]::Round(($successCount / $total) * 100)
        AverageElapsedMs = $avgElapsed
    }
}

function Get-LauncherToolStatistics {
    param(
        [AllowEmptyCollection()]
        [object[]]$Entries = @(),
        [string[]]$Tools = @('claude', 'codex', 'copilot')
    )

    $stats = [System.Collections.Generic.List[object]]::new()
    foreach ($tool in $Tools) {
        $toolEntries = @($Entries | Where-Object { $_.tool -eq $tool })
        $summary = Get-LauncherRecentSummary -Entries $toolEntries
        $latest = @(
            $toolEntries |
                Sort-Object @{ Expression = {
                    if ($_.timestamp) {
                        try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                    }
                    else {
                        [datetimeoffset]::MinValue
                    }
                }; Descending = $true } |
                Select-Object -First 1
        )
        $stats.Add([pscustomobject]@{
            tool = $tool
            runs = $summary.Total
            successRate = $summary.SuccessRate
            averageElapsedMs = $summary.AverageElapsedMs
            lastResult = if ($latest.Count -gt 0 -and $latest[0].result) { $latest[0].result } else { 'none' }
            lastProject = if ($latest.Count -gt 0) { $latest[0].project } else { $null }
            lastTimestamp = if ($latest.Count -gt 0) { $latest[0].timestamp } else { $null }
        })
    }

    return @($stats)
}

function Get-LauncherAgentLaneEvents {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [AllowEmptyCollection()]
        [object[]]$MetadataEntries = @(),
        [AllowNull()]
        [object]$BacklogSummary = $null
    )

    $toolStats = Get-LauncherToolStatistics -Entries $MetadataEntries
    $architectLatest = @(
        $MetadataEntries |
            Where-Object { $_.tool -in @('claude', 'codex') } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 1
    )
    $opsLatest = @(
        $MetadataEntries |
            Where-Object { $_.tool -eq 'copilot' } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 1
    )
    $overallSummary = Get-LauncherRecentSummary -Entries $MetadataEntries
    $priorityLabel = if ($BacklogSummary -and @($BacklogSummary.Priorities).Count -gt 0) { @($BacklogSummary.Priorities) -join ', ' } else { 'none' }

    $recentArchitectEvents = @(
        $MetadataEntries |
            Where-Object { $_.tool -in @('claude', 'codex') } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 3
    )
    $recentOpsEvents = @(
        $MetadataEntries |
            Where-Object { $_.tool -eq 'copilot' } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 3
    )
    $recentQaEvents = @(
        $MetadataEntries |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 3
    )

    $architectRecentLabel = @($recentArchitectEvents | ForEach-Object { '{0}:{1}' -f $_.project, $_.result }) -join ', '
    $qaRecentLabel = @($recentQaEvents | ForEach-Object { '{0}/{1}' -f $_.tool, $_.result }) -join ', '
    $opsRecentLabel = @($recentOpsEvents | ForEach-Object { '{0}:{1}' -f $_.project, $_.result }) -join ', '

    return @(
        [pscustomobject]@{
            lane = 'Architect'
            message = if ($architectLatest.Count -gt 0) {
                "latest=$($architectLatest[0].tool)/$($architectLatest[0].project) result=$($architectLatest[0].result) recent=$architectRecentLabel"
            }
            else {
                "defaultTool=$($Config.tools.defaultTool) recent=none"
            }
        },
        [pscustomobject]@{
            lane = 'QA'
            message = "runs=$($overallSummary.Total) success=$($overallSummary.SuccessRate)% avg=$($overallSummary.AverageElapsedMs)ms recent=$qaRecentLabel"
        },
        [pscustomobject]@{
            lane = 'Ops'
            message = if ($opsLatest.Count -gt 0) {
                "backlog=$($BacklogSummary.Count) priorities=$priorityLabel lastCopilot=$($opsLatest[0].result) recent=$opsRecentLabel"
            }
            else {
                "backlog=$($BacklogSummary.Count) priorities=$priorityLabel lastCopilot=none"
            }
        }
    )
}

function Get-LauncherTokenBudgetStatus {
    $pct = if ($env:AI_STARTUP_TOKEN_USAGE_PCT) { [int]$env:AI_STARTUP_TOKEN_USAGE_PCT } else { -1 }
    if ($pct -lt 0) {
        return [pscustomobject]@{ Percent = $null; Zone = 'Unknown'; Status = 'Token usage unavailable' }
    }
    if ($pct -lt 60) {
        return [pscustomobject]@{ Percent = $pct; Zone = 'Green'; Status = 'Normal development' }
    }
    if ($pct -lt 75) {
        return [pscustomobject]@{ Percent = $pct; Zone = 'Yellow'; Status = 'Reduced build activity' }
    }
    if ($pct -lt 90) {
        return [pscustomobject]@{ Percent = $pct; Zone = 'Orange'; Status = 'Monitor priority' }
    }

    return [pscustomobject]@{ Percent = $pct; Zone = 'Red'; Status = 'Development stop threshold' }
}

function Get-LauncherRecentEntries {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [int]$MaxCount = 20
    )

    if (-not (Get-Command Get-RecentProjects -ErrorAction SilentlyContinue)) {
        return @()
    }
    if ($null -eq $Config.recentProjects -or -not $Config.recentProjects.enabled -or [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile)) {
        return @()
    }

    return @(
        Get-RecentProjects -HistoryPath $Config.recentProjects.historyFile |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First $MaxCount
    )
}

function Get-LauncherRecentToolResults {
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries,
        [string[]]$Tools = @('claude', 'codex', 'copilot')
    )

    $results = @()
    foreach ($tool in $Tools) {
        $latest = @($Entries | Where-Object { $_.tool -eq $tool } | Select-Object -First 1)
        if ($latest.Count -eq 0) {
            $results += [pscustomobject]@{
                tool = $tool
                result = 'none'
                elapsedMs = $null
                timestamp = $null
            }
            continue
        }

        $results += [pscustomobject]@{
            tool = $tool
            result = if ($latest[0].result) { $latest[0].result } else { 'unknown' }
            elapsedMs = $latest[0].elapsedMs
            timestamp = $latest[0].timestamp
        }
    }

    return @($results)
}

Export-ModuleMember -Function Get-StartupRoot
Export-ModuleMember -Function Get-StartupConfigPath
Export-ModuleMember -Function Import-LauncherConfig
Export-ModuleMember -Function Test-LauncherCommand
Export-ModuleMember -Function Assert-LauncherToolAvailable
Export-ModuleMember -Function Get-LauncherApiKeyValue
Export-ModuleMember -Function Show-LauncherApiKeyWarning
Export-ModuleMember -Function Resolve-LauncherMode
Export-ModuleMember -Function Resolve-LauncherProject
Export-ModuleMember -Function Show-LauncherProjectChoices
Export-ModuleMember -Function Get-LauncherModeLabel
Export-ModuleMember -Function Get-LauncherModeName
Export-ModuleMember -Function New-LauncherDryRunMessage
Export-ModuleMember -Function Confirm-LauncherStart
Export-ModuleMember -Function Set-LauncherEnvironment
Export-ModuleMember -Function ConvertTo-BashExports
Export-ModuleMember -Function Sync-ProjectTemplate
Export-ModuleMember -Function New-RemoteTemplateDeployScript
Export-ModuleMember -Function Invoke-LauncherSshScript
Export-ModuleMember -Function Get-LauncherShell
Export-ModuleMember -Function Write-LauncherExecutionResult
Export-ModuleMember -Function Get-LauncherMetadataLogPath
Export-ModuleMember -Function Get-LauncherMetadataEntries
Export-ModuleMember -Function Write-LauncherMetadataLog
Export-ModuleMember -Function New-LauncherExecutionContext
Export-ModuleMember -Function Complete-LauncherExecutionContext
Export-ModuleMember -Function Get-LauncherRecentSummary
Export-ModuleMember -Function Get-LauncherRecentEntries
Export-ModuleMember -Function Get-LauncherRecentToolResults
Export-ModuleMember -Function Get-LauncherToolStatistics
Export-ModuleMember -Function Get-LauncherAgentLaneEvents
Export-ModuleMember -Function Get-LauncherTokenBudgetStatus
Export-ModuleMember -Function Get-LauncherBacklogSummary
