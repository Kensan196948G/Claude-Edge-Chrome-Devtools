# ============================================================
# LogManager.psm1 - セッションログ管理モジュール
# Claude-EdgeChromeDevTools v1.8.0
# ============================================================

# --- モジュールスコープ変数 ---
$script:CurrentLogPath = $null
$script:LoggingActive = $false

function Start-SessionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$Config,

        [Parameter(Mandatory=$true)]
        [string]$ProjectName,

        [Parameter(Mandatory=$true)]
        [string]$Browser,

        [Parameter(Mandatory=$true)]
        [int]$Port
    )

    # logging セクション未定義 or disabled の場合はスキップ
    if (-not $Config.PSObject.Properties['logging'] -or -not $Config.logging.enabled) {
        $script:LoggingActive = $false
        return @{ LogPath = $null }
    }

    $logging = $Config.logging
    $prefix = if ($logging.logPrefix) { $logging.logPrefix } else { "claude-devtools" }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fileName = "$prefix-$ProjectName-$Browser-$Port-$timestamp.log"

    # ログディレクトリの決定（フォールバック付き）
    $logDir = $logging.logDir
    try {
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        # 書き込みテスト
        $testFile = Join-Path $logDir ".write-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
        [System.IO.File]::WriteAllText($testFile, "test")
        Remove-Item $testFile -Force
    }
    catch {
        Write-Warning "ログディレクトリにアクセスできません: $logDir → `$env:TEMP にフォールバック"
        $logDir = $env:TEMP
    }

    $logPath = Join-Path $logDir $fileName

    # Start-Transcript ラッパー
    try {
        Start-Transcript -Path $logPath -Append -ErrorAction Stop | Out-Null
        $script:CurrentLogPath = $logPath
        $script:LoggingActive = $true
    }
    catch {
        Write-Warning "Start-Transcript 失敗: $_"
        $script:LoggingActive = $false
        return @{ LogPath = $null }
    }

    return @{ LogPath = $logPath }
}

function Stop-SessionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [bool]$Success
    )

    if (-not $script:LoggingActive -or $null -eq $script:CurrentLogPath) {
        return
    }

    # Transcript 停止
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }

    $script:LoggingActive = $false

    # サフィックス付与リネーム
    if (Test-Path $script:CurrentLogPath) {
        $suffix = if ($Success) { 'SUCCESS' } else { 'FAILURE' }
        $dir      = [System.IO.Path]::GetDirectoryName($script:CurrentLogPath)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($script:CurrentLogPath)
        $ext      = [System.IO.Path]::GetExtension($script:CurrentLogPath)
        $newName  = "${baseName}-${suffix}${ext}"
        $newPath  = Join-Path $dir $newName

        try {
            Rename-Item -Path $script:CurrentLogPath -NewName $newName -Force
            Write-Host "📝 ログ記録終了: $newPath" -ForegroundColor Gray
        } catch {
            Write-Warning "ログファイルのリネームに失敗しました: $_"
        }
    }

    $script:CurrentLogPath = $null
}

function Invoke-LogRotation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$Config
    )

    if ($null -eq $Config.logging -or $Config.logging.enabled -ne $true) { return }

    $logConfig = $Config.logging
    $logDir    = $logConfig.logDir
    if (-not (Test-Path $logDir)) { return }

    $now = Get-Date
    $prefix = if ($logConfig.logPrefix) { $logConfig.logPrefix } else { 'claude-devtools' }

    Get-ChildItem -Path $logDir -Filter "${prefix}-*.log" -File | ForEach-Object {
        $age = ($now - $_.LastWriteTime).Days
        $name = $_.Name

        if ($name -match '-SUCCESS\.log$') {
            if ($age -gt $logConfig.successKeepDays) {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    Write-Verbose "ログローテーション: 削除 (SUCCESS, ${age}日経過) $name"
                } catch {
                    Write-Warning "ログ削除失敗: $name - $_"
                }
            }
        }
        elseif ($name -match '-FAILURE\.log$') {
            if ($age -gt $logConfig.failureKeepDays) {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    Write-Verbose "ログローテーション: 削除 (FAILURE, ${age}日経過) $name"
                } catch {
                    Write-Warning "ログ削除失敗: $name - $_"
                }
            }
        }
        else {
            # レガシーログ (サフィックスなし)
            if ($age -gt $logConfig.legacyKeepDays) {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    Write-Verbose "ログローテーション: 削除 (LEGACY, ${age}日経過) $name"
                } catch {
                    Write-Warning "ログ削除失敗: $name - $_"
                }
            }
        }
    }
}

function Invoke-LogArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$Config
    )

    if ($null -eq $Config.logging -or $Config.logging.enabled -ne $true) { return }

    $logConfig = $Config.logging
    $logDir    = $logConfig.logDir
    if (-not (Test-Path $logDir)) { return }

    $now = Get-Date
    $prefix = if ($logConfig.logPrefix) { $logConfig.logPrefix } else { 'claude-devtools' }
    $archiveDir = Join-Path $logDir 'archive'

    $toArchive = Get-ChildItem -Path $logDir -Filter "${prefix}-*.log" -File | Where-Object {
        ($now - $_.LastWriteTime).Days -gt $logConfig.archiveAfterDays
    }

    if ($toArchive.Count -eq 0) { return }

    if (-not (Test-Path $archiveDir)) {
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    }

    $monthGroup = $toArchive | Group-Object { $_.LastWriteTime.ToString('yyyy-MM') }
    foreach ($group in $monthGroup) {
        $zipName = "$($group.Name).zip"
        $zipPath = Join-Path $archiveDir $zipName

        try {
            Compress-Archive -Path ($group.Group | Select-Object -ExpandProperty FullName) `
                             -DestinationPath $zipPath -Update -ErrorAction Stop

            # アーカイブ成功後に元ファイル削除
            foreach ($file in $group.Group) {
                Remove-Item -Path $file.FullName -Force
            }
            Write-Verbose "ログアーカイブ: $($group.Group.Count) ファイル → $zipName"
        } catch {
            Write-Warning "ログアーカイブに失敗しました ($zipName): $_"
        }
    }
}

function Get-LogSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$Config
    )

    $result = @{
        TotalFiles     = 0
        SuccessCount   = 0
        FailureCount   = 0
        LegacyCount    = 0
        TotalSizeBytes = 0
        OldestLog      = $null
        NewestLog      = $null
    }

    if ($null -eq $Config.logging) { return $result }

    $logDir = $Config.logging.logDir
    if (-not $logDir -or -not (Test-Path $logDir)) { return $result }

    $prefix = if ($Config.logging.logPrefix) { $Config.logging.logPrefix } else { 'claude-devtools' }
    $files = Get-ChildItem -Path $logDir -Filter "${prefix}-*.log" -File

    if ($files.Count -eq 0) { return $result }

    $result.TotalFiles = $files.Count
    $result.TotalSizeBytes = ($files | Measure-Object -Property Length -Sum).Sum

    foreach ($f in $files) {
        if ($f.Name -match '-SUCCESS\.log$') { $result.SuccessCount++ }
        elseif ($f.Name -match '-FAILURE\.log$') { $result.FailureCount++ }
        else { $result.LegacyCount++ }
    }

    $sorted = $files | Sort-Object LastWriteTime
    $result.OldestLog = $sorted[0].Name
    $result.NewestLog = $sorted[-1].Name

    return $result
}

Export-ModuleMember -Function @(
    'Start-SessionLog',
    'Stop-SessionLog',
    'Invoke-LogRotation',
    'Invoke-LogArchive',
    'Get-LogSummary'
)
