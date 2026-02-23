# ============================================================
# Claude-EdgeDevTools.ps1
# プロジェクト選択 + DevToolsポート判別 + run-claude.sh自動生成 + 自動接続
# Microsoft Edge 版
# ============================================================

param(
    [switch]$TmuxMode = $false   # start.bat から渡される tmux フラグ
)

$ErrorActionPreference = "Stop"

# ===== ログ記録開始 =====
$LogPath = $null
$LogTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir = $env:TEMP
$LogPrefix = "claude-devtools-edge"
$LogPath = Join-Path $LogDir "${LogPrefix}-${LogTimestamp}.log"

try {
    Start-Transcript -Path $LogPath -Append -ErrorAction Stop
    Write-Host "📝 ログ記録開始: $LogPath" -ForegroundColor Gray
} catch {
    Write-Warning "ログ記録の開始に失敗しましたが続行します: $_"
    $LogPath = $null
}

# ===== ヘルパー関数 =====

# SSH引数を安全にエスケープ (bash変数として)
function Escape-SSHArgument {
    param([string]$Value)
    # シングルクォートで囲み、内部のシングルクォートを '\'' でエスケープ
    return "'" + ($Value -replace "'", "'\\''") + "'"
}

# config.jsonバックアップ関数
function Backup-ConfigFile {
    param(
        [string]$ConfigPath,
        [string]$BackupDir,
        [int]$MaxBackups = 10,
        [bool]$MaskSensitive = $true,
        [string[]]$SensitiveKeys = @()
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "バックアップ対象が見つかりません: $ConfigPath"
        return
    }

    # バックアップディレクトリ作成
    $BackupDirFull = Join-Path (Split-Path $ConfigPath -Parent) $BackupDir
    if (-not (Test-Path $BackupDirFull)) {
        New-Item -ItemType Directory -Path $BackupDirFull -Force | Out-Null
    }

    # タイムスタンプ付きバックアップファイル名
    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $BackupFileName = "config-${Timestamp}.json"
    $BackupPath = Join-Path $BackupDirFull $BackupFileName

    # config.json読み込み
    $ConfigObj = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    # 機密情報マスク
    if ($MaskSensitive) {
        foreach ($keyPath in $SensitiveKeys) {
            $keys = $keyPath -split '\.'
            $currentObj = $ConfigObj

            # ネストされたキーにアクセス
            for ($i = 0; $i -lt $keys.Count - 1; $i++) {
                if ($currentObj.PSObject.Properties.Name -contains $keys[$i]) {
                    $currentObj = $currentObj.$($keys[$i])
                } else {
                    break
                }
            }

            # 最終キーの値をマスク
            $finalKey = $keys[-1]
            if ($currentObj.PSObject.Properties.Name -contains $finalKey) {
                $originalValue = $currentObj.$finalKey
                if ($originalValue) {
                    $currentObj.$finalKey = "***MASKED*** (length: $($originalValue.Length))"
                }
            }
        }
    }

    # バックアップ保存
    $ConfigObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $BackupPath -Encoding UTF8 -Force
    Write-Host "💾 config.jsonをバックアップしました: $BackupFileName" -ForegroundColor Green

    # 古いバックアップ削除
    $ExistingBackups = Get-ChildItem -Path $BackupDirFull -Filter "config-*.json" |
        Sort-Object LastWriteTime -Descending

    if ($ExistingBackups.Count -gt $MaxBackups) {
        $ToDelete = $ExistingBackups | Select-Object -Skip $MaxBackups
        $ToDelete | Remove-Item -Force
        Write-Host "🧹 古いバックアップを削除しました: $($ToDelete.Count)件" -ForegroundColor Gray
    }
}

# 最近使用プロジェクト履歴管理関数
function Get-RecentProjects {
    param([string]$HistoryPath)

    if (-not (Test-Path $HistoryPath)) {
        return @()
    }

    try {
        $history = Get-Content $HistoryPath -Raw | ConvertFrom-Json
        return $history.projects
    } catch {
        Write-Warning "履歴ファイル読み込みエラー: $_"
        return @()
    }
}

function Update-RecentProjects {
    param(
        [string]$ProjectName,
        [string]$HistoryPath,
        [int]$MaxHistory = 10
    )

    $recentList = Get-RecentProjects -HistoryPath $HistoryPath

    if ($recentList -is [PSCustomObject]) {
        $recentList = @($recentList)
    }

    # 新規選択を先頭に追加（重複削除）
    $newList = @($ProjectName) + ($recentList | Where-Object { $_ -ne $ProjectName })
    $newList = $newList[0..([Math]::Min($MaxHistory - 1, $newList.Count - 1))]

    $historyDir = Split-Path $HistoryPath -Parent
    if (-not (Test-Path $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }

    $historyObj = @{
        lastUpdated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        projects = $newList
    }

    $historyObj | ConvertTo-Json -Depth 3 | Out-File -FilePath $HistoryPath -Encoding UTF8 -Force
}

# ログファイルをステータス別フォルダに移動
function Move-LogToStatusFolder {
    param(
        [string]$LogPath,
        [string]$LogRootDir,
        [int]$ExitCode,
        [bool]$IsError = $false
    )

    if (-not $LogPath -or -not (Test-Path $LogPath)) { return }

    $Status = if ($IsError -or $ExitCode -ne 0) { "failure" } else { "success" }
    $TargetDir = Join-Path $LogRootDir $Status

    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    $FileName = Split-Path $LogPath -Leaf
    $NewFileName = $FileName -replace '\.log$', "-${Status}.log"
    $NewPath = Join-Path $TargetDir $NewFileName

    try {
        Move-Item -Path $LogPath -Destination $NewPath -Force
        Write-Host "📝 ログ保存: $Status/$NewFileName" -ForegroundColor Gray
    } catch {
        Write-Warning "ログ移動失敗（元の場所に残します）: $_"
    }
}

# ===== グローバル変数 (クリーンアップ用) =====
$Global:BrowserProcess = $null
$Global:DevToolsPort = $null
$Global:LinuxHost = $null

# ===== エラートラップ (クリーンアップハンドラー) =====
trap {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    Write-Host "⚠️ エラーが発生しました" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow

    # エラー詳細を先に表示（クリーンアップでブロックされる前に）
    Write-Host "`n❌ エラー詳細: $_" -ForegroundColor Red
    Write-Host "   発生場所: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n" -ForegroundColor Red

    Write-Host "🧹 クリーンアップ中..." -ForegroundColor Yellow

    # ブラウザプロセス終了
    if ($Global:BrowserProcess) {
        try {
            if (-not $Global:BrowserProcess.HasExited) {
                Write-Host "🧹 ブラウザプロセスを終了中 (PID: $($Global:BrowserProcess.Id))..."
                $Global:BrowserProcess | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                Write-Host "✅ ブラウザプロセス終了完了" -ForegroundColor Green
            }
        } catch {
            Write-Warning "ブラウザプロセス終了中にエラー: $_"
        }
    }

    # ログパス表示（エラー発生時）
    if ($LogPath) {
        Write-Host "`n📄 詳細ログ: $LogPath" -ForegroundColor Cyan

        # エラー時のログ移動
        try {
            Stop-Transcript -ErrorAction SilentlyContinue

            if ($Config -and $Config.logging) {
                $LogRootDir = if ([System.IO.Path]::IsPathRooted($Config.logging.logDir)) {
                    $Config.logging.logDir
                } else {
                    Join-Path $RootDir $Config.logging.logDir
                }

                Move-LogToStatusFolder -LogPath $LogPath -LogRootDir $LogRootDir -ExitCode 1 -IsError $true
            }
        } catch {
            # 移動失敗時は元の場所に残す
        }
    }

    # Linux側ポートクリーンアップ（BatchMode=yesでパスワード要求を防止）
    if ($Global:DevToolsPort -and $Global:LinuxHost) {
        try {
            Write-Host "🧹 Linux側ポート $Global:DevToolsPort をクリーンアップ中..."
            $escapedPort = Escape-SSHArgument $Global:DevToolsPort
            ssh -o ConnectTimeout=3 -o BatchMode=yes $Global:LinuxHost "fuser -k $escapedPort/tcp 2>/dev/null || true" 2>$null
            Write-Host "✅ ポートクリーンアップ完了" -ForegroundColor Green
        } catch {
            Write-Warning "ポートクリーンアップスキップ（SSH接続不可）"
        }
    }

    Write-Host "`n❌ スクリプトを中断しました。`n" -ForegroundColor Red

    exit 1
}

# ===== 設定ファイル読み込み =====
$RootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConfigPath = Join-Path $RootDir "config\config.json"
if (Test-Path $ConfigPath) {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    Write-Host "✅ 設定ファイルを読み込みました: $ConfigPath"
} else {
    Write-Error "❌ 設定ファイルが見つかりません: $ConfigPath"
}

# 古いログファイルクリーンアップ（成功/失敗別 + レガシー）
if ($Config.logging -and $Config.logging.enabled) {
    try {
        $LogRootDir = if ([System.IO.Path]::IsPathRooted($Config.logging.logDir)) {
            $Config.logging.logDir
        } else {
            Join-Path $RootDir $Config.logging.logDir
        }

        # success/failure/archiveディレクトリ作成
        @('success', 'failure', 'archive') | ForEach-Object {
            $dir = Join-Path $LogRootDir $_
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        # 成功ログクリーンアップ
        if ($Config.logging.successKeepDays -gt 0) {
            $cutoff = (Get-Date).AddDays(-$Config.logging.successKeepDays)
            Get-ChildItem (Join-Path $LogRootDir "success") -Filter "*-success.log" -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }

        # 失敗ログクリーンアップ
        if ($Config.logging.failureKeepDays -gt 0) {
            $cutoff = (Get-Date).AddDays(-$Config.logging.failureKeepDays)
            Get-ChildItem (Join-Path $LogRootDir "failure") -Filter "*-failure.log" -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }

        # レガシーログクリーンアップ（TEMP フォルダ）
        if ($Config.logging.legacyKeepDays -gt 0) {
            $cutoff = (Get-Date).AddDays(-$Config.logging.legacyKeepDays)
            Get-ChildItem $env:TEMP -Filter "${LogPrefix}*.log" -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }

        Write-Host "🧹 ログクリーンアップ完了（成功: $($Config.logging.successKeepDays)日、失敗: $($Config.logging.failureKeepDays)日）" -ForegroundColor Gray
    } catch {
        Write-Warning "ログクリーンアップに失敗: $_"
    }
}

# config.json自動バックアップ
if ($Config.backupConfig -and $Config.backupConfig.enabled) {
    try {
        Backup-ConfigFile `
            -ConfigPath $ConfigPath `
            -BackupDir $Config.backupConfig.backupDir `
            -MaxBackups $Config.backupConfig.maxBackups `
            -MaskSensitive $Config.backupConfig.maskSensitive `
            -SensitiveKeys $Config.backupConfig.sensitiveKeys
    } catch {
        Write-Warning "バックアップに失敗しましたが続行します: $_"
    }
}

$ZRoot      = $Config.zDrive
$ZUncPath   = $Config.zDriveUncPath
$LinuxHost  = $Config.linuxHost
$LinuxBase  = $Config.linuxBase
$EdgeExe    = $Config.edgeExe
$ChromeExe  = $Config.chromeExe

# グローバル変数に設定 (クリーンアップハンドラー用)
$Global:LinuxHost = $LinuxHost

# ===== ポート自動選択 =====
$AvailablePorts = $Config.ports

function Get-AvailablePort {
    param([int[]]$Ports)
    foreach ($port in $Ports) {
        $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if (-not $listener) {
            return $port
        }
    }
    return $null
}

$DevToolsPort = Get-AvailablePort -Ports $AvailablePorts
if (-not $DevToolsPort) {
    Write-Error "❌ 利用可能なポートがありません。ポート $($AvailablePorts -join ', ') はすべて使用中です。"
}

# グローバル変数に設定 (クリーンアップハンドラー用)
$Global:DevToolsPort = $DevToolsPort

# ===== ブラウザ自動選択UI =====
Write-Host "`n🌐 ブラウザを選択してください:`n"
Write-Host "[1] Microsoft Edge"
Write-Host "[2] Google Chrome"
Write-Host ""

# 入力検証付きブラウザ選択
do {
    $BrowserChoice = Read-Host "番号を入力 (1-2, デフォルト: 1)"

    # 空入力はデフォルト
    if ([string]::IsNullOrWhiteSpace($BrowserChoice)) {
        $BrowserChoice = "1"
        break
    }

    # 有効な選択肢のみ受付
    if ($BrowserChoice -in @("1", "2")) {
        break
    }

    Write-Host "❌ 無効な入力です。1 または 2 を入力してください。" -ForegroundColor Red
} while ($true)

if ($BrowserChoice -eq "2") {
    $SelectedBrowser = "chrome"
    $BrowserExe = $ChromeExe
    $BrowserName = "Google Chrome"
} else {
    $SelectedBrowser = "edge"
    $BrowserExe = $EdgeExe
    $BrowserName = "Microsoft Edge"
}

if (-not (Test-Path $BrowserExe)) {
    Write-Error "❌ $BrowserName が見つかりません: $BrowserExe"
}

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "🤖 Claude DevTools セットアップ ($BrowserName)"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"
Write-Host "✅ 自動選択されたポート: $DevToolsPort"

# ============================================================
# ① プロジェクト選択
# ============================================================
# pwsh (PowerShell 7) ではマップドドライブが見えない場合がある
# config.json の UNC パスを使って確実にアクセスする
Write-Host "`n🔍 プロジェクトルート確認..." -ForegroundColor Cyan

$ProjectRootPath = $null
$driveLetter = ($ZRoot -replace '[:\\]', '')

# ステップ1: ドライブレターで直接アクセス試行
if (Test-Path $ZRoot) {
    Write-Host "✅ ドライブ ${driveLetter}: は直接アクセス可能です" -ForegroundColor Green
    $ProjectRootPath = $ZRoot
} else {
    Write-Host "⚠️ ドライブ ${driveLetter}: が直接アクセスできません" -ForegroundColor Yellow

    # ステップ2: UNC パスを取得
    $uncPath = $null

    # 2-1: config.json から UNC パスを取得（最優先）
    if ($ZUncPath) {
        Write-Host "  🔍 config.json の UNC パス検証: $ZUncPath" -ForegroundColor Yellow
        if (Test-Path $ZUncPath) {
            $uncPath = $ZUncPath
            Write-Host "  ✅ config.json の UNC パスが有効: $uncPath" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️ config.json の UNC パスにアクセスできません: $ZUncPath" -ForegroundColor Yellow
            Write-Host "  🔍 他の方法を試行します..." -ForegroundColor Yellow
        }
    }

    # 2-2: レジストリから取得
    if (-not $uncPath) {
        $regPath = "HKCU:\Network\$driveLetter"
        if (Test-Path $regPath) {
            $uncPath = (Get-ItemProperty $regPath).RemotePath
            Write-Host "  ✅ レジストリから UNC パス取得: $uncPath" -ForegroundColor Green
        }
    }

    # 2-3: SMBマッピングから取得
    if (-not $uncPath) {
        $smbMapping = Get-SmbMapping -ErrorAction SilentlyContinue | Where-Object LocalPath -eq "${driveLetter}:"
        if ($smbMapping) {
            $uncPath = $smbMapping.RemotePath
            Write-Host "  ✅ SMB マッピングから UNC パス取得: $uncPath" -ForegroundColor Green
        }
    }

    # 2-4: PSDrive から取得
    if (-not $uncPath) {
        $psDrive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
        if ($psDrive -and $psDrive.DisplayRoot) {
            $uncPath = $psDrive.DisplayRoot
            Write-Host "  ✅ PSDrive から UNC パス取得: $uncPath" -ForegroundColor Green
        }
    }

    # ステップ3: UNC パスでドライブをマッピング
    if ($uncPath) {
        Write-Host "`n  🔧 ドライブ ${driveLetter}: をマッピング中 ($uncPath)..." -ForegroundColor Yellow

        # 既存のPSDriveを削除
        Remove-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue

        # -Persist なしでマッピング（セッション内のみ有効）
        $newDrive = New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root $uncPath -Scope Global -ErrorAction SilentlyContinue

        Start-Sleep -Milliseconds 500

        if (Test-Path $ZRoot) {
            Write-Host "  ✅ ドライブマッピング成功" -ForegroundColor Green
            $ProjectRootPath = $ZRoot
        } else {
            Write-Host "  ⚠️ ドライブマッピング失敗。UNC パスを直接使用します" -ForegroundColor Yellow
            $ProjectRootPath = $uncPath
        }
    } else {
        Write-Error "❌ UNC パスが見つかりません。config.json に 'zDriveUncPath' を設定してください（例: \\\\server\\share）"
    }
}

# 最終確認
if (-not $ProjectRootPath -or -not (Test-Path $ProjectRootPath)) {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host "診断情報:" -ForegroundColor Yellow
    Write-Host "  設定ドライブ: $ZRoot" -ForegroundColor White
    Write-Host "  UNC パス: $uncPath" -ForegroundColor White
    Write-Host "  使用パス: $ProjectRootPath" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Error "❌ プロジェクトルートにアクセスできません"
}

Write-Host "✅ プロジェクトルート: $ProjectRootPath" -ForegroundColor Green

$Projects = Get-ChildItem $ProjectRootPath -Directory | Sort-Object Name

if ($Projects.Count -eq 0) {
    Write-Error "❌ プロジェクトルート ($ProjectRootPath) にプロジェクトが見つかりません"
}

Write-Host "📦 プロジェクトを選択してください`n"

# 履歴読み込み
$HistoryEnabled = $Config.recentProjects.enabled
$HistoryPath = $ExecutionContext.InvokeCommand.ExpandString($Config.recentProjects.historyFile)
$RecentProjects = @()

if ($HistoryEnabled) {
    $RecentProjects = Get-RecentProjects -HistoryPath $HistoryPath
}

# プロジェクト一覧表示（⭐付き）
for ($i = 0; $i -lt $Projects.Count; $i++) {
    $projectName = $Projects[$i].Name
    $isRecent = $RecentProjects -contains $projectName
    $marker = if ($isRecent) { "⭐ " } else { "   " }
    Write-Host "[$($i+1)]$marker$projectName"
}

# 入力検証付きインデックス選択
do {
    $Index = Read-Host "`n番号を入力 (1-$($Projects.Count))"

    # 数値チェック
    if ($Index -notmatch '^\d+$') {
        Write-Host "❌ 数字を入力してください。" -ForegroundColor Red
        continue
    }

    $IndexNum = [int]$Index

    # 範囲チェック
    if ($IndexNum -lt 1 -or $IndexNum -gt $Projects.Count) {
        Write-Host "❌ 1から$($Projects.Count)の範囲で入力してください。" -ForegroundColor Red
        continue
    }

    # 検証成功
    $Project = $Projects[$IndexNum - 1]
    break

} while ($true)

$ProjectName = $Project.Name
$ProjectRoot = $Project.FullName

Write-Host "`n✅ 選択プロジェクト: $ProjectName"

# 履歴更新
if ($HistoryEnabled) {
    try {
        Update-RecentProjects -ProjectName $ProjectName -HistoryPath $HistoryPath -MaxHistory $Config.recentProjects.maxHistory
        Write-Host "📝 最近使用プロジェクトに記録しました" -ForegroundColor Gray
    } catch {
        Write-Warning "履歴更新に失敗しましたが続行します: $_"
    }
}

# ============================================================
# ② SSH接続事前確認
# ============================================================
Write-Host "`n🔍 SSH接続確認中: $LinuxHost ..." -ForegroundColor Cyan

try {
    $sshTestStart = Get-Date
    $sshResult = ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new $LinuxHost "echo OK" 2>$null

    if ($LASTEXITCODE -ne 0 -or "$sshResult" -ne "OK") {
        throw "SSH接続テスト失敗 (exit code: $LASTEXITCODE, output: $sshResult)"
    }

    $elapsed = ((Get-Date) - $sshTestStart).TotalSeconds
    Write-Host "✅ SSH接続成功 ($([math]::Round($elapsed, 1))秒)" -ForegroundColor Green

} catch {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host "❌ SSHホスト '$LinuxHost' に接続できません" -ForegroundColor Red
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Red

    Write-Host "確認事項:" -ForegroundColor Yellow
    Write-Host "  1. ~/.ssh/config で $LinuxHost が定義されているか"
    Write-Host "  2. ssh $LinuxHost でパスワードなしで接続できるか"
    Write-Host "  3. ホストが起動しているか (ping $LinuxHost)"
    Write-Host "  4. ネットワーク接続が有効か`n"

    Write-Host "詳細ログの確認: " -NoNewline
    Write-Host "ssh -vvv $LinuxHost" -ForegroundColor Cyan
    Write-Host ""

    throw "SSH接続テストに失敗しました。上記を確認してください。"
}

# ============================================================
# ③ ポート確保（自動選択されたポート）
# ============================================================
Write-Host "✅ 使用ポート: $DevToolsPort (自動選択)"

# ============================================================
# ④ ブラウザ DevTools 起動（専用プロファイル + 事前設定）
# ============================================================
$BrowserProfile = Join-Path ($Config.browserProfileDir ?? "C:\") "DevTools-$SelectedBrowser-$DevToolsPort"
$ProcessName = if ($SelectedBrowser -eq "edge") { "msedge" } else { "chrome" }

Write-Host "`n🌐 $BrowserName DevTools 起動準備..."

# 既存の DevTools プロセスを確認して終了
$existingProcesses = Get-Process $ProcessName -ErrorAction SilentlyContinue | Where-Object {
    try {
        $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        $cmdLine -match "DevTools-$SelectedBrowser-$DevToolsPort"
    } catch { $false }
}

if ($existingProcesses) {
    Write-Host "⚠️  既存のDevTools $BrowserName を終了中..."
    $existingProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# プロファイルディレクトリを作成（存在しない場合）
if (-not (Test-Path $BrowserProfile)) {
    New-Item -ItemType Directory -Path $BrowserProfile -Force | Out-Null
    Write-Host "📁 プロファイルディレクトリ作成: $BrowserProfile"
}

# ============================================================
# ④-a DevTools Preferences ファイル生成（事前設定）
# ============================================================
$PrefsDir = Join-Path $BrowserProfile "Default"
$PrefsFile = Join-Path $PrefsDir "Preferences"

if (-not (Test-Path $PrefsDir)) {
    New-Item -ItemType Directory -Path $PrefsDir -Force | Out-Null
}

# DevTools設定を含むPreferencesを作成
$DevToolsPrefs = @{
    devtools = @{
        preferences = @{
            # General: Disable cache (while DevTools is open)
            "cacheDisabled" = "true"
            # General: Auto-open DevTools for popups
            "autoOpenDevToolsForPopups" = "true"
            # Console: Preserve log
            "preserveConsoleLog" = "true"
            # Console: Show timestamps
            "consoleTimestampsEnabled" = "true"
            # 追加の便利設定
            "network_log.preserve-log" = "true"
            "InspectorView.splitViewState" = '{"vertical":{"size":400},"horizontal":{"size":300}}'
        }
    }
    browser = @{
        enabled_labs_experiments = @()
    }
}

# 既存のPreferencesがあれば読み込んでマージ
if (Test-Path $PrefsFile) {
    try {
        $existingPrefs = Get-Content $PrefsFile -Raw | ConvertFrom-Json -AsHashtable
        # devtools設定をマージ
        if ($existingPrefs.devtools -and $existingPrefs.devtools.preferences) {
            foreach ($key in $DevToolsPrefs.devtools.preferences.Keys) {
                $existingPrefs.devtools.preferences[$key] = $DevToolsPrefs.devtools.preferences[$key]
            }
            $DevToolsPrefs = $existingPrefs
        }
    } catch {
        Write-Host "   既存Preferences読み込みスキップ（新規作成）"
    }
}

$PrefsJson = $DevToolsPrefs | ConvertTo-Json -Depth 10 -Compress
[System.IO.File]::WriteAllText($PrefsFile, $PrefsJson, [System.Text.UTF8Encoding]::new($false))

Write-Host "✅ DevTools設定を適用:"
Write-Host "   - Disable cache (while DevTools is open)"
Write-Host "   - Auto-open DevTools for popups"
Write-Host "   - Preserve log"
Write-Host "   - Show timestamps"

# ============================================================
# ④-b ブラウザ DevTools 起動
# ============================================================
Write-Host "`n🌐 $BrowserName DevTools 起動中..."

$StartUrl = "http://localhost:$DevToolsPort"

$browserArgs = @(
    "--remote-debugging-port=$DevToolsPort",
    "--user-data-dir=`"$BrowserProfile`"",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-allow-origins=*",
    "--auto-open-devtools-for-tabs",
    $StartUrl
)

Write-Host "🌐 起動URL: $StartUrl"
$browserProc = Start-Process -FilePath $BrowserExe -ArgumentList $browserArgs -PassThru

# ブラウザプロセスをグローバル変数に保存 (クリーンアップハンドラー用)
$Global:BrowserProcess = $browserProc

# ブラウザが起動してポートがリスニング状態になるまで待機
Write-Host "⏳ $BrowserName 起動待機中..."

$maxWait = 15
$waited = 0
$devToolsReady = $false

while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 1
    $waited++

    # ポートがリスニング状態か確認
    $listening = Get-NetTCPConnection -LocalPort $DevToolsPort -State Listen -ErrorAction SilentlyContinue

    if ($listening) {
        # DevToolsエンドポイントに接続確認
        try {
            $versionInfo = Invoke-RestMethod -Uri "http://localhost:$DevToolsPort/json/version" -TimeoutSec 3 -ErrorAction Stop
            $devToolsReady = $true
            break
        } catch {
            Write-Host "   ポート検出、応答待機中... ($waited/$maxWait)"
        }
    } else {
        Write-Host "   起動中... ($waited/$maxWait)"
    }
}

if ($devToolsReady) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "✅ $BrowserName DevTools 接続テスト成功!"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
    Write-Host "📊 テスト結果:"
    Write-Host "   - DevToolsポート: $DevToolsPort (リスニング中)"
    Write-Host "   - エンドポイント: http://localhost:$DevToolsPort/json/version"
    Write-Host "   - 起動URL: http://localhost:$DevToolsPort"
    Write-Host ""

    # バージョン情報を表示 ($versionInfo は既に取得済み)
    try {
        Write-Host "📋 $BrowserName 情報:"
        Write-Host "   - Browser: $($versionInfo.Browser)"
        Write-Host "   - Protocol: $($versionInfo.'Protocol-Version')"
        Write-Host "   - V8: $($versionInfo.'V8-Version')"
    } catch {
        Write-Host "   (バージョン情報取得スキップ)"
    }
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "❌ $BrowserName DevTools 接続テスト失敗"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
    Write-Host "💡 トラブルシューティング:"
    Write-Host "   1. すべての$BrowserName ウィンドウを閉じてから再実行"
    Write-Host "   2. 以下のコマンドで手動起動を試す:"
    Write-Host ""
    Write-Host "   `"$BrowserExe`" --remote-debugging-port=$DevToolsPort --user-data-dir=`"$BrowserProfile`" http://localhost:$DevToolsPort"
    Write-Host ""

    $continue = Read-Host "続行しますか？ (y/N)"
    if ($continue -ne "y" -and $continue -ne "Y") {
        exit 1
    }
}

# ============================================================
# ⑤ run-claude.sh 自動生成
# ============================================================

$RunClaudePath = Join-Path $ProjectRoot "run-claude.sh"
$LinuxPath = "$LinuxBase/$ProjectName/run-claude.sh"

# シングルクォートヒアストリングでbash変数を保護し、後からポート番号だけ置換
$RunClaude = @'
#!/usr/bin/env bash
set -euo pipefail

PORT=__DEVTOOLS_PORT__
RESTART_DELAY=3

# tmux ダッシュボード設定
TMUX_ENABLED=__TMUX_ENABLED__
TMUX_LAYOUT="__TMUX_LAYOUT__"
PROJECT_NAME="__PROJECT_NAME__"
SCRIPTS_TMUX_DIR="__SCRIPTS_TMUX_DIR__"

# 初期プロンプト（ヒアドキュメントで定義：バッククォートや二重引用符を安全に含む）
INIT_PROMPT=$(cat << 'INITPROMPTEOF'
以降、日本語で対応してください。

あなたはこのリポジトリのメイン開発エージェントです。
GitHub（リモート origin）および GitHub Actions 上の自動実行と整合が取れる形で、
ローカル開発作業を支援してください。

## 【目的】

- ローカル開発での変更が、そのまま GitHub の Pull Request / GitHub Actions ワークフローと
  矛盾なく連携できる形で行われること。
- SubAgent / Hooks / Git WorkTree / MCP / Agent Teams / 標準機能をフル活用しつつも、
  Git・GitHub 操作には明確なルールを守ること。

## 【前提・環境】

- このリポジトリは GitHub 上の `<org>/<repo>` と同期している。
- GitHub Actions では CLAUDE.md とワークフローファイル（.github/workflows 配下）に
  CI 上のルールや制約が定義されている前提とする。
- Worktree は「1 機能 = 1 WorkTree/ブランチ」を基本とし、
  PR 単位の開発を前提にする。
- Agent Teams が有効化されている（環境変数 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 設定済み）。

## 【利用してよい Claude Code 機能】

- **全 SubAgent 機能**：並列での解析・実装・テスト分担に自由に利用してよい。
- **全 Hooks 機能**：テスト実行、lint、フォーマッタ、ログ出力などの開発フロー自動化に利用してよい。
- **全 Git WorkTree 機能**：機能ブランチ/PR 単位での作業ディレクトリ分離に利用してよい。
- **全 MCP 機能**：GitHub API、Issue/PR 情報、外部ドキュメント・監視など必要な範囲で利用してよい。
  なお **Codex MCP**（`mcp__codex__codex`）が利用可能な場合、コード生成タスクを Codex に委譲してよい（詳細は末尾「Claude × Codex 開発体制」参照）。
- **全 Agent Teams 機能**：複数の Claude Code インスタンスをチームとして協調動作させてよい（後述のポリシーに従うこと）。
- **標準機能**：ファイル編集、検索、テスト実行、シェルコマンド実行など通常の開発作業を行ってよい。

## 【Agent Teams（オーケストレーション）ポリシー】

### 有効化設定

Agent Teams は以下のいずれかの方法で有効化されている前提とする：

```bash
# 方法1: 環境変数で設定
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# 方法2: settings.json で設定（推奨：プロジェクト単位での共有が可能）
# .claude/settings.json に以下を追加
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

### SubAgent と Agent Teams の使い分け

| 観点 | SubAgent | Agent Teams |
|------|----------|-------------|
| 実行モデル | 単一セッション内の子プロセス | 独立した複数の Claude Code インスタンス |
| コミュニケーション | 親エージェントへの報告のみ | チームメイト間で相互メッセージ可能 |
| コンテキスト | 親のコンテキストを共有 | 各自が独立したコンテキストウィンドウを持つ |
| 適用場面 | 短時間で完結する集中タスク | 並列探索・相互レビュー・クロスレイヤー作業 |
| コスト | 低（単一セッション内） | 高（複数インスタンス分のトークン消費） |

### Agent Teams を使うべき場面

以下のタスクでは Agent Teams の利用を積極的に検討すること：

1. **リサーチ・レビュー系**：複数の観点（セキュリティ、パフォーマンス、アーキテクチャ）から同時にコードレビューを行う場合
2. **新規モジュール・機能開発**：フロントエンド・バックエンド・テストなど独立したレイヤーを並列で開発する場合
3. **デバッグ・原因調査**：複数の仮説を並列で検証し、結果を突き合わせて原因を特定する場合
4. **クロスレイヤー協調**：API設計・DB設計・UI設計など、相互に影響するがそれぞれ独立して作業できる変更

### Agent Teams を使うべきでない場面

以下の場合は SubAgent または単一セッションを優先すること：

- 単純な定型タスク（lint修正、フォーマット適用など）
- 順序依存の強い逐次作業
- トークンコストを抑えたいルーチン作業

### Agent Teams 運用ルール

1. **チーム編成の提案**：Agent Teams を使う場合、まずチーム構成（役割・人数・タスク分担）を提案し、私の承認を得てから spawn すること。
2. **リード（自分自身）の責務**：
   - タスクの分割と割り当て
   - チームメイトの進捗モニタリング
   - 結果の統合・コンフリクト解決
   - 作業完了後のチーム shutdown とクリーンアップ
3. **チームメイトの独立性**：各チームメイトは独立した WorkTree/ブランチで作業すること。同一ファイルへの同時編集を避ける。
4. **コミュニケーション方針**：
   - チームメイト間のメッセージは、発見事項・ブロッカー・完了報告に限定する
   - 設計判断が必要な場合はリード（メインエージェント）に escalate する
5. **クリーンアップ義務**：作業完了時は必ずリードがチームメイトの shutdown を行い、cleanup を実行すること。チームメイト側から cleanup を実行してはならない。
6. **Git 操作との統合**：Agent Teams の各メンバーも【Git / GitHub 操作ポリシー】に従うこと。特に `git commit` / `git push` は確認を求めてから行う。

### Agent Teams 利用例

```
# PR レビューを複数観点で同時実施
「PR #142 をレビューするために Agent Teams を作成してください。
  - セキュリティ担当：脆弱性・入力バリデーションの観点
  - パフォーマンス担当：N+1クエリ・メモリリーク・アルゴリズム効率の観点
  - テストカバレッジ担当：テスト網羅性・エッジケースの観点
各担当はそれぞれの観点でレビューし、発見事項をリードに報告してください。」

# フルスタック機能開発
「ユーザー認証機能を Agent Teams で並列開発してください。
  - バックエンド担当：API設計・認証ロジック実装（feature/auth-backend ブランチ）
  - フロントエンド担当：ログインUI・トークン管理（feature/auth-frontend ブランチ）
  - テスト担当：E2Eテスト・統合テスト設計（feature/auth-tests ブランチ）
各担当は独立した WorkTree で作業し、API仕様はリードが調整してください。」
```

## 【ブラウザ自動化ツール使い分けガイド】

このプロジェクトではブラウザ自動化に **Puppeteer MCP** と **Playwright MCP** の2つが利用可能です。
以下のガイドラインに従って適切なツールを選択してください。

### Puppeteer MCP を使用すべき場合

**状況**：Windows側のブラウザインスタンスに接続してデバッグ・検証を行う場合

**特徴**：
- Windows側で起動済みのEdge/Chromeブラウザに接続（SSHポートフォワーディング経由）
- DevTools Protocol経由のリアルタイムアクセス
- 既存のユーザーセッション・Cookie・ログイン状態を利用可能
- 手動操作との併用が容易（開発者が手動で操作したブラウザをそのままデバッグ）
- Node.js Puppeteer APIの全機能利用可能（待機、リトライ、複雑な操作シーケンス）

**適用例**：
- ログイン済みのWebアプリをデバッグ（セッション情報を再現する必要がない）
- ブラウザコンソールのエラーログをリアルタイム監視
- ネットワークトラフィック（XHR/Fetch）の詳細解析
- DOM要素の動的変更を追跡・検証
- パフォーマンス計測（Navigation Timing、Resource Timing等）
- 手動操作とスクリプト操作を交互に実行する検証作業
- 複雑な操作フロー（ドラッグ&ドロップ、複数タブ操作等）

**接続確認方法**：
\`\`\`bash
# 環境変数 MCP_CHROME_DEBUG_PORT（または CLAUDE_CHROME_DEBUG_PORT）が設定されていることを確認
echo \$MCP_CHROME_DEBUG_PORT

# DevTools接続テスト
curl -s http://127.0.0.1:\${MCP_CHROME_DEBUG_PORT}/json/version | jq '.'

# 利用可能なタブ一覧
curl -s http://127.0.0.1:\${MCP_CHROME_DEBUG_PORT}/json/list | jq '.'
\`\`\`

**利用可能なMCPツール**：
- \`mcp__plugin_puppeteer_puppeteer__navigate\`: ページ遷移
- \`mcp__plugin_puppeteer_puppeteer__click\`: 要素クリック
- \`mcp__plugin_puppeteer_puppeteer__evaluate\`: JavaScriptコード実行
- \`mcp__plugin_puppeteer_puppeteer__screenshot\`: スクリーンショット取得
- （その他、\`ToolSearch "puppeteer"\` で検索）

### Playwright MCP を使用すべき場合

**状況**：自動テスト・スクレイピング・クリーンな環境での検証を行う場合

**特徴**：
- ヘッドレスブラウザを新規起動（Linux側で完結、Xサーバ不要）
- 完全に独立した環境（クリーンなプロファイル、Cookie無し）
- クロスブラウザ対応（Chromium/Firefox/WebKit）
- 自動待機・リトライ・タイムアウト処理が組み込み済み
- マルチタブ・マルチコンテキスト対応

**適用例**：
- E2Eテストの自動実行（CI/CDパイプライン組み込み）
- スクレイピング・データ収集（ログイン不要の公開ページ）
- 複数ブラウザでの互換性テスト
- 並列実行が必要な大規模テスト
- ログイン認証を含む自動テストフロー（認証情報をコードで管理）

**接続確認方法**：
\`\`\`bash
# Playwrightインストール確認（通常はMCPサーバーが自動管理）
# 特別な環境変数設定は不要（MCPサーバーが自動起動）
\`\`\`

**利用可能なMCPツール**：
- \`mcp__plugin_playwright_playwright__browser_navigate\`: ページ遷移
- \`mcp__plugin_playwright_playwright__browser_click\`: 要素クリック
- \`mcp__plugin_playwright_playwright__browser_fill_form\`: フォーム入力
- \`mcp__plugin_playwright_playwright__browser_run_code\`: JavaScriptコード実行
- \`mcp__plugin_playwright_playwright__browser_take_screenshot\`: スクリーンショット取得
- \`mcp__plugin_playwright_playwright__browser_console_messages\`: コンソールログ取得
- \`mcp__plugin_playwright_playwright__browser_network_requests\`: ネットワークリクエスト一覧
- （その他、\`mcp__plugin_playwright_playwright__*\` で利用可能なツールを検索）

### 使い分けの判断フロー

\`\`\`
既存ブラウザの状態（ログイン・Cookie等）を利用したい？
├─ YES → Puppeteer MCP
│         （Windows側ブラウザに接続、環境変数 MCP_CHROME_DEBUG_PORT 使用）
│
└─ NO  → 以下をさらに判断
          │
          ├─ 自動テスト・CI/CD統合？ → Playwright MCP
          ├─ スクレイピング？ → Playwright MCP
          ├─ クロスブラウザ検証？ → Playwright MCP
          └─ 手動操作との併用が必要？ → Puppeteer MCP
\`\`\`

### 注意事項

1. **Xサーバ不要（重要）**：LinuxホストにXサーバがインストールされていなくても、両ツールとも動作します
   - **Puppeteer MCP**: Windows側のブラウザに接続するため、Linux側にXサーバ不要（SSHポートフォワーディング経由）
   - **Playwright MCP**: Linux側でヘッドレスブラウザを起動するため、Xサーバ不要
   - ⚠️ **選択基準はXサーバの有無ではありません**。既存ブラウザ（ログイン状態等）を使うか、クリーンな環境かで判断してください
2. **ポート範囲**：Puppeteer MCPは9222～9229の範囲で動作（config.jsonで設定）
3. **並行利用**：両ツールは同時に使用可能（異なるユースケースで併用可）
4. **ツール検索**：利用可能なツールを確認するには \`ToolSearch\` を使用してキーワード検索（例：\`ToolSearch "puppeteer screenshot"\`）
5. **Puppeteer 優先原則**：ユーザーがブラウザ操作を依頼した場合、**既存のWindows側ブラウザ（Puppeteer MCP）を優先使用**してください。Playwrightは自動テスト・スクレイピング・クリーンな環境が必要な場合のみ使用

### 推奨ワークフロー

1. **開発・デバッグフェーズ**：Puppeteer MCPで手動操作と併用しながら検証
2. **テスト自動化フェーズ**：Playwrightで自動テストスクリプト作成
3. **CI/CD統合フェーズ**：PlaywrightテストをGitHub Actionsに組み込み

## 【Git / GitHub 操作ポリシー】

### ローカルで行ってよい自動操作

- 既存ブランチからの Git WorkTree 作成
- 作業用ブランチの作成・切替
- `git status` / `git diff` の取得
- テスト・ビルド用の一時ファイル作成・削除

### 必ず確認を求めてから行う操作

- `git add` / `git commit` / `git push` など履歴に影響する操作
- GitHub 上での Pull Request 作成・更新
- GitHub 上の Issue・ラベル・コメントの作成/更新

### GitHub Actions との整合

- CI で使用しているテストコマンド・ビルドコマンド・Lint 設定は、
  .github/workflows および CLAUDE.md を参照し、それと同一のコマンドをローカルでも優先的に実行すること。
- CI で禁止されている操作（例：main 直 push、特定ブランチへの force push など）は、
  ローカルからも提案せず、代替手順（PR 経由など）を提案すること。

## 【タスクの進め方】

1. まずこのリポジトリ内の CLAUDE.md と .github/workflows 配下を確認し、
   プロジェクト固有のルール・テスト手順・ブランチ運用方針を要約して報告してください。
2. その上で、私が指示するタスク（例：機能追加、バグ修正、レビューなど）を
   SubAgent / Hooks / WorkTree / Agent Teams を活用して並列実行しつつ進めてください。
   コード生成が必要な場合は **Codex MCP**（`ToolSearch "codex"` で可用性を確認）の活用も検討してください。
3. 各ステップで、GitHub Actions 上でどのように動くか（どのワークフローが動き、
   どのコマンドが実行されるか）も合わせて説明してください。
4. タスクの規模・性質に応じて、SubAgent（軽量・単一セッション内）と
   Agent Teams（重量・マルチインスタンス）を適切に使い分けてください。
   判断に迷う場合は私に確認してください。

## 【Claude × Codex 開発体制】

### 基本思想
このセッションは **Claude（開発指揮官）× Codex（実装ドライバー）** のペアプロ体制で動作します。

### 🧠 Claude = 開発指揮官（CTO + PM + アーキテクト）

**統治する能力群（開発OSレベル）:**
- SubAgents / Agent Teams — 並列・分散実行の指揮
- Hooks — イベント駆動の自動化制御
- WorkTree — 並列ブランチ管理
- MCP群 — 外部ツール・サービス統合
- Memory群（CLAUDE.md + MEMORY.md + claude-mem + Memory MCP）— 知識の永続化と伝播

**担当領域:**
| 作業 | 詳細 |
|------|------|
| 要件分析・設計判断 | アーキテクチャ設計、トレードオフ評価 |
| コードレビュー・統合 | Codex 生成コードのレビューとファイルへの書き込み |
| ファイル操作・git | Read/Edit/Write/Bash による直接操作 |
| テスト実行・CI確認 | Bash によるテスト実行と結果判定 |
| オーケストレーション | SubAgents / Agent Teams への指示と統合 |
| 人間への確認・報告 | CLAUDE.md 第4条に基づく意思決定の委譲 |

### 🤖 Codex = 実装ドライバー（複数の実装担当エンジニア）

**特化能力:**
- 高速コード生成（関数・クラス・モジュール単位）
- 定型コードの大量変換・リファクタリング
- 局所最適化（アルゴリズム改善、型付け強化等）
- threadId を使った継続的なセッション管理

**MCPツール:**
- `mcp__codex__codex`: 新規セッションでコード生成 → threadId を保存
- `mcp__codex__codex_reply`: threadId を使って同じコンテキストで継続

### 🔁 シナリオ別ワークフロー

**新機能実装:**
1. Claude: 要件整理・既存コード調査（Read/Grep）
2. Claude → Codex: 仕様＋コンテキストを送信（`mcp__codex__codex`）
3. Codex: コード生成 → threadId を保存
4. Claude: レビュー後にファイルへ書き込み（Edit/Write）

**バグ修正:**
1. Claude: バグ箇所特定（Grep/Read）
2. Claude → Codex: バグ箇所＋エラー情報を送信
3. Codex: 修正パッチ生成
4. Claude: Edit で適用 → テスト実行

**大規模リファクタリング:**
1. Claude: 計画立案 → **人間へ承認取得**（CLAUDE.md 第4条）
2. Claude → Codex: ファイルごとに依頼（threadId で継続）
3. Claude: 全変更後にlint・テスト確認

### ⚠️ 運用原則
- OPENAI_API_KEY 未設定時は Claude 単独で対応（Codex 依存なし）
- Codex 生成コードは **必ずレビューしてからファイルに書き込む**（自動書き込み禁止）
- 大規模変更は CLAUDE.md 第4条に従い人間の承認必須
- ToolSearch "codex" でツールの可用性を随時確認

---

## 【統合運用基本方針（vNext 2.1.50 + 自己修復ループ v4）】

ClaudeCode 2.1.50 の機能および接続済みMCP群を最大限活用せよ。
本仕様は **開発オーケストレーション制御仕様** であり、例外なく遵守すること。

同時に実現すること：

* 設計の一貫性
* 記憶の継続性
* 並列開発効率の最大化
* 自動レビュー品質の向上
* CI連動型自己修復（学習型）

---

## 【Git / CI / 自己修復ループ v4（学習型）】

### 🔁 v4 概要

自己修復は単なる再試行ではない。
**CI失敗パターンを記録し、次回以降の修復精度を向上させる学習型ループ**とする。

### 🔁 自己修復フロー

**Phase 1：ログ取得**

1. `github` MCPでCIログ取得
2. エラー種別分類：Lintエラー / テスト失敗 / ビルドエラー / 依存関係エラー / 型エラー / E2E失敗 / 環境依存エラー

**Phase 2：原因分析**

* 最小単位で原因特定、影響ファイル範囲を限定
* 再現可能性の確認
* 既存Memoryに類似失敗があるか検索（優先順：memory → claude-mem → context7）

**Phase 3：修正戦略決定**

修正は必ず以下順で検討せよ（最小差分を原則とする）：
1. 設定修正（config）
2. テスト修正（期待値修正）
3. 実装修正（ロジック修正）
4. 依存関係修正

**Phase 4：再実行制御**

自己修復ループには必ず「最大試行回数（例：3回）」「状態遷移ログ」「変更差分履歴」「失敗パターン分類ID」を保持せよ。

### 🔁 学習機構（v4の核心）

CI失敗ごとに以下を保存せよ：

* **memory に保存**：修正内容、変更ファイル、試行回数、成否
* **claude-mem に保存**：失敗原因の本質、再発防止策、設計上の教訓
* **memory-keeper に保存（条件付き）**：再発率が高い場合のみ、CI原則として追加すべきルール

### 🔁 再発防止ルール生成

CI失敗が2回以上同種で発生した場合：
1. 「再発防止ルール候補」を生成
2. CI準憲法に追加提案
3. pre-commit / pre-push Hook への組込提案

### 🔁 無限ループ防止

以下の場合は修復を停止し、「根本原因仮説」「修復不能理由」「人間判断が必要な項目」を明示せよ：

* 試行上限到達
* 同一差分で2回失敗
* 根本設計変更が必要と判断
* セキュリティ違反検出

---

## 【最終処理プロトコル（v4強化版）】

タスク完了時は必ず以下を提示せよ：

* 実施内容
* 残課題
* 更新したMCP一覧
* CI失敗履歴（あれば）
* 学習追加内容（memory / claude-mem / keeper）
* 次フェーズ可否確認

---

## 【実行原則（最終版）】

* 記憶前提で思考せよ
* 並列可能なものは並列化せよ
* 設計整合性を崩すな
* テストなき変更は禁止
* CI成功なきマージは禁止
* 記録なき進行は禁止
* CI失敗は学習対象とせよ

---

## 利用可能な Agent Skills (.claude/skills/)

以下のスキルが利用可能です。`Skill` ツールまたは `/skill-name` で呼び出せます。

| スキル名 | 用途 |
|---------|------|
| `tmux-ops` | tmuxレイアウト切替・ペイン操作・セッション管理 |
| `agent-teams-ops` | Agent Teamsチーム作成・監視・シャットダウン |
| `devops-monitor` | DevTools/MCP診断・リソース確認・ネットワーク診断 |
| `session-restore` | SSH切断後のtmuxセッション復元手順 |
| `tmux-layout-sync` | Agent Teams起動/停止時のtmuxレイアウト同期 |
INITPROMPTEOF
)

trap 'echo "🛑 Ctrl+C を受信 — while ループで exit 130 処理します"' INT
trap 'echo "❌ エラー発生: line ${LINENO} (exit ${?})" >&2' ERR

# on-startup hook 実行（存在する場合）
# ヘルスチェック失敗はエラーとしない（Claude 起動を妨げない）
if [ -f ".claude/hooks/on-startup.sh" ]; then
    bash .claude/hooks/on-startup.sh || echo "⚠️  on-startup.sh 失敗 (exit $?) — Claude 起動は続行します"
fi

echo "🔍 DevTools 応答確認..."
MAX_RETRY=10
for i in $(seq 1 $MAX_RETRY); do
  if curl -sf --connect-timeout 2 http://127.0.0.1:${PORT}/json/version >/dev/null 2>&1; then
    echo "✅ DevTools 接続成功!"
    break
  fi
  if [ "$i" -eq "$MAX_RETRY" ]; then
    echo "❌ DevTools 応答なし (port=${PORT})"
    exit 1
  fi
  echo "   リトライ中... ($i/$MAX_RETRY)"
  sleep 2
done

# 環境変数を設定
export CLAUDE_CHROME_DEBUG_PORT=${PORT}
export MCP_CHROME_DEBUG_PORT=${PORT}

# Puppeteer MCP: 既存ブラウザへの接続設定
echo "🔌 既存ブラウザへの接続準備..."
WS_ENDPOINT=$(curl -s http://127.0.0.1:${PORT}/json/version 2>/dev/null | jq -r '.webSocketDebuggerUrl' 2>/dev/null)

if [ -n "$WS_ENDPOINT" ] && [ "$WS_ENDPOINT" != "null" ]; then
  echo "✅ WebSocketエンドポイント取得成功: $WS_ENDPOINT"
  export PUPPETEER_LAUNCH_OPTIONS="{\\\"browserWSEndpoint\\\": \\\"${WS_ENDPOINT}\\\"}"
  echo "   Puppeteer MCPは既存ブラウザに接続します"
else
  echo "⚠️  既存ブラウザが見つかりません。Puppeteerは新規ブラウザを起動します。"
  export PUPPETEER_LAUNCH_OPTIONS="{\\\"headless\\\": false, \\\"timeout\\\": 30000}"
fi

# Agent Teams オーケストレーション有効化
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# DevTools詳細接続テスト関数
test_devtools_connection() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 DevTools 詳細接続テスト"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 1. バージョン情報
    echo "📋 1. バージョン情報:"
    if command -v jq &> /dev/null; then
        curl -s http://127.0.0.1:${PORT}/json/version | jq '.' || echo "❌ バージョン取得失敗"
    else
        curl -s http://127.0.0.1:${PORT}/json/version || echo "❌ バージョン取得失敗"
    fi
    echo ""

    # 2. タブ数確認
    echo "📋 2. 開いているタブ数:"
    if command -v jq &> /dev/null; then
        TAB_COUNT=$(curl -s http://127.0.0.1:${PORT}/json/list | jq 'length')
        echo "   タブ数: ${TAB_COUNT}"
    else
        echo "   (jqがインストールされていないため詳細表示不可)"
        curl -s http://127.0.0.1:${PORT}/json/list | head -n 3
    fi
    echo ""

    # 3. WebSocketエンドポイント確認
    echo "📋 3. WebSocket接続エンドポイント:"
    if command -v jq &> /dev/null; then
        WS_URL=$(curl -s http://127.0.0.1:${PORT}/json/list | jq -r '.[0].webSocketDebuggerUrl // "N/A"')
        echo "   ${WS_URL}"
    else
        echo "   (jqがインストールされていないため表示不可)"
    fi
    echo ""

    # 4. Protocol version確認
    echo "📋 4. DevTools Protocol Version:"
    if command -v jq &> /dev/null; then
        PROTO_VER=$(curl -s http://127.0.0.1:${PORT}/json/version | jq -r '."Protocol-Version" // "N/A"')
        echo "   ${PROTO_VER}"
    else
        echo "   (jqがインストールされていないため表示不可)"
    fi
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ DevTools接続テスト完了"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 詳細テスト実行
test_devtools_connection

# === tmux ダッシュボード起動 ===
# TMUX 環境変数が未設定 = tmux の外からの初回起動
# → tmux-dashboard.sh へ exec（メインペインで run-claude.sh を再実行）
# → 再実行時は TMUX 環境変数が設定済みなのでこのブロックをスキップ
if [ "$TMUX_ENABLED" = "true" ] && [ -z "${TMUX:-}" ]; then
    if command -v tmux &>/dev/null; then
        DASHBOARD_SCRIPT="${SCRIPTS_TMUX_DIR}/tmux-dashboard.sh"
        if [ -f "$DASHBOARD_SCRIPT" ] && [ -x "$DASHBOARD_SCRIPT" ]; then
            echo ""
            echo "🖥️  tmux ダッシュボード起動中..."
            echo "   レイアウト: ${TMUX_LAYOUT}"
            echo "   セッション: claude-${PROJECT_NAME}-${PORT}"
            echo ""
            exec "$DASHBOARD_SCRIPT" "$PROJECT_NAME" "$PORT" "$TMUX_LAYOUT" "cd $(pwd) && ./run-claude.sh"
        else
            echo "⚠️  tmux-dashboard.sh が見つかりません: ${DASHBOARD_SCRIPT}"
            echo "   tmux なしで続行します..."
        fi
    else
        echo "ℹ️  tmux がインストールされていません。通常モードで起動します。"
    fi
fi

echo ""
echo "🚀 Claude 起動 (port=${PORT})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 初期プロンプトを自動入力します..."
echo ""

# claude コマンド存在確認
if ! command -v claude &>/dev/null; then
    echo "❌ claude コマンドが見つかりません。"
    echo "   インストール: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

while true; do
  if [ -n "${TMUX:-}" ]; then
    # tmux 内: TTY 接続を維持して直接実行（パイプなし → インタラクティブモード保証）
    # パイプを使うと stdin が非 TTY になり Claude がバッチモードで動作して即終了する
    echo "🔍 [診断] TMUX=${TMUX:-} | claude=$(command -v claude 2>/dev/null || echo '未発見')"
    # INIT_PROMPT を tmux バッファ経由で注入（TTY を保持しながら送信）
    INIT_FILE="/tmp/claude_init_${PORT:-$$}.txt"
    printf '%s\n' "$INIT_PROMPT" > "$INIT_FILE"
    # バックグラウンドで遅延注入（Claude 起動後 6 秒待ってから貼り付け）
    (
        sleep 6
        if [ -f "$INIT_FILE" ] && [ -n "${TMUX_PANE:-}" ]; then
            tmux load-buffer "$INIT_FILE"
            tmux paste-buffer -t "$TMUX_PANE" -d
            rm -f "$INIT_FILE"
        fi
    ) &
    INJECT_PID=$!
    # set +e: claude 非ゼロ終了時に set -e でスクリプトが即終了しないよう明示的に無効化
    set +e
    claude --dangerously-skip-permissions
    EXIT_CODE=$?
    set -e
    kill "$INJECT_PID" 2>/dev/null || true
    rm -f "$INIT_FILE" 2>/dev/null || true
  else
    # 非 tmux: INIT_PROMPT をパイプで自動入力（従来方式）
    set +e
    set +o pipefail
    (echo "$INIT_PROMPT"; cat) | claude --dangerously-skip-permissions
    EXIT_CODE=$?
    set -e
    set -o pipefail
  fi

  echo "ℹ️  Claude 終了 (exit code: ${EXIT_CODE})"
  # 正常終了(0)または Ctrl+C(130) は再起動しない
  [ "$EXIT_CODE" -eq 0 ] && break
  [ "$EXIT_CODE" -eq 130 ] && break

  echo ""
  echo "🔄 Claude 再起動 (${RESTART_DELAY}秒後)..."
  sleep $RESTART_DELAY
done

echo "👋 終了しました"
'@

# ポート番号を置換
$RunClaude = $RunClaude -replace '__DEVTOOLS_PORT__', $DevToolsPort

# tmux 設定値を置換
$TmuxEnabled = if ($TmuxMode -or ($Config.tmux -and $Config.tmux.enabled)) { "true" } else { "false" }
$TmuxLayout = if ($Config.tmux -and $Config.tmux.defaultLayout) { $Config.tmux.defaultLayout } else { "auto" }
$TmuxScriptsDir = "$LinuxBase/$ProjectName/scripts/tmux"

$RunClaude = $RunClaude -replace '__TMUX_ENABLED__', $TmuxEnabled
$RunClaude = $RunClaude -replace '__TMUX_LAYOUT__', $TmuxLayout
$RunClaude = $RunClaude -replace '__PROJECT_NAME__', $ProjectName
$RunClaude = $RunClaude -replace '__SCRIPTS_TMUX_DIR__', $TmuxScriptsDir

# CRLF を LF に変換
$RunClaude = $RunClaude -replace "`r`n", "`n"
$RunClaude = $RunClaude -replace "`r", "`n"

# run-claude.sh を Base64 エンコード（SSH 経由で転送するため UNC パスへの直接書き込みは行わない）
$EncodedRunClaude = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RunClaude))

Write-Host "✅ run-claude.sh 生成完了（SSH 経由転送予定）"

# ============================================================
# ⑤-b リモートセットアップ（統合版）
# ============================================================
Write-Host "🔧 リモート環境セットアップ中..."

# エスケープされた変数を準備
$EscapedLinuxBase = Escape-SSHArgument $LinuxBase
$EscapedProjectName = Escape-SSHArgument $ProjectName
$EscapedLinuxPath = Escape-SSHArgument $LinuxPath
$EscapedDevToolsPort = Escape-SSHArgument $DevToolsPort

# Statusline設定とbase64エンコードされたデータを準備
$statuslineEnabled = $Config.statusline.enabled
$encodedStatusline = ""
$encodedSettings = ""
$encodedGlobalScript = ""

if ($statuslineEnabled) {
    # statusline.sh を読み込み
    $StatuslineSource = Join-Path (Split-Path $PSScriptRoot -Parent) "statusline.sh"

    if (Test-Path $StatuslineSource) {
        # statusline.sh をbase64エンコード
        $statuslineContent = Get-Content $StatuslineSource -Raw
        $statuslineContent = $statuslineContent -replace "`r`n", "`n"
        $statuslineContent = $statuslineContent -replace "`r", "`n"
        $encodedStatusline = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($statuslineContent))

        # settings.json を生成
        $SettingsJson = @{
            statusLine = @{
                type = "command"
                command = "$LinuxBase/$ProjectName/.claude/statusline.sh"
                padding = 0
            }
        } | ConvertTo-Json -Depth 3
        $encodedSettings = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($SettingsJson))

        # グローバル設定更新スクリプトを生成
        $ClaudeEnv = $Config.claudeCode.env
        $ClaudeSettings = $Config.claudeCode.settings

        # env エントリーをJSON文字列化
        $envEntries = @()
        foreach ($key in $ClaudeEnv.PSObject.Properties.Name) {
            $envEntries += "`"$key`": `"$($ClaudeEnv.$key)`""
        }
        $envJson = "{$($envEntries -join ', ')}"

        # settings エントリーをJSON文字列化
        $settingsEntries = @()
        foreach ($key in $ClaudeSettings.PSObject.Properties.Name) {
            $value = $ClaudeSettings.$key
            $jsonValue = if ($value -is [bool]) {
                $value.ToString().ToLower()
            } elseif ($value -is [int]) {
                $value
            } else {
                "`"$value`""
            }
            $settingsEntries += "`"$key`": $jsonValue"
        }
        $settingsJson = "{$($settingsEntries -join ', ')}"

        # グローバルsettings.jsonを包括的に更新（config.json駆動）
        $GlobalSettingsScript = @"
#!/bin/bash
SETTINGS_FILE="`$HOME/.claude/settings.json"
mkdir -p "`$HOME/.claude"

if [ -f "`$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
    # 既存設定とマージ（config.jsonのclaudeCodeセクションから生成）
    jq '. + $settingsJson + {
      "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}
    } | .env = ((.env // {}) + $envJson)' "`$SETTINGS_FILE" > "`$SETTINGS_FILE.tmp" && mv "`$SETTINGS_FILE.tmp" "`$SETTINGS_FILE"
    echo "✅ グローバル設定をマージ更新しました (config.json駆動)"
else
    cat > "`$SETTINGS_FILE" << 'SETTINGSEOF'
{
  "env": $envJson,
  $($settingsEntries -join ',
  '),
  "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}
}
SETTINGSEOF
    echo "✅ グローバル設定を新規作成しました (config.json駆動)"
fi
"@
        $GlobalSettingsScript = $GlobalSettingsScript -replace "`r`n", "`n"
        $GlobalSettingsScript = $GlobalSettingsScript -replace "`r", "`n"
        $encodedGlobalScript = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($GlobalSettingsScript))
    }
}

# MCP セットアップスクリプトの準備
$McpSetupSource = Join-Path (Split-Path $PSScriptRoot -Parent) "mcp\setup-mcp.sh"
$McpEnabled = $Config.mcp.enabled -and $Config.mcp.autoSetup -and (Test-Path $McpSetupSource)
$EncodedMcpScript = ""
$GithubTokenB64 = ""
$BraveApiKey = ""

if ($McpEnabled) {
    # setup-mcp.sh をBase64エンコード
    $mcpScriptContent = Get-Content $McpSetupSource -Raw
    $mcpScriptContent = $mcpScriptContent -replace "`r`n", "`n"
    $mcpScriptContent = $mcpScriptContent -replace "`r", "`n"
    $EncodedMcpScript = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($mcpScriptContent))

    # GitHub Token を取得 (既にbase64エンコード済み)
    if ($Config.mcp.githubToken) {
        $GithubTokenB64 = $Config.mcp.githubToken
    }

    # Brave API Key を取得
    if ($Config.mcp.braveApiKey) {
        $BraveApiKey = $Config.mcp.braveApiKey
    }
}

# === tmux スクリプト base64 エンコーディング ===
$TmuxAutoInstall = if ($Config.tmux -and $Config.tmux.autoInstall) { "true" } else { "false" }
$EncodedTmuxScripts = @{}
$TmuxSetupBlock = "echo 'ℹ️  tmux ダッシュボード無効'"

if ($Config.tmux -and $Config.tmux.enabled) {
    $TmuxBaseDir = Join-Path (Split-Path $PSScriptRoot -Parent) "tmux"

    $TmuxFiles = @(
        "tmux-dashboard.sh",
        "tmux-install.sh",
        "panes/devtools-monitor.sh",
        "panes/mcp-health-monitor.sh",
        "panes/git-status-monitor.sh",
        "panes/resource-monitor.sh",
        "panes/agent-teams-monitor.sh",
        "layouts/default.conf",
        "layouts/review-team.conf",
        "layouts/fullstack-dev-team.conf",
        "layouts/debug-team.conf",
        "layouts/custom.conf.template"
    )

    foreach ($TmuxFile in $TmuxFiles) {
        $TmuxFilePath = Join-Path $TmuxBaseDir $TmuxFile
        if (Test-Path $TmuxFilePath) {
            $TmuxContent = Get-Content $TmuxFilePath -Raw -Encoding UTF8
            $TmuxContent = $TmuxContent -replace "`r`n", "`n"
            $TmuxContent = $TmuxContent -replace "`r", "`n"
            $EncodedTmuxScripts[$TmuxFile] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($TmuxContent))
        } else {
            Write-Warning "tmux スクリプトが見つかりません: $TmuxFilePath"
        }
    }

    # tmux ファイルデプロイ用 bash コマンドを事前生成
    # (PowerShell変数を展開済みの文字列として組み立てることで、
    #  @"..."@ ヒアストリング内での bash 変数エスケープ問題を回避)
    $tmuxLines = @()
    $tmuxLines += ""
    $tmuxLines += "# === tmux スクリプト配置 ==="
    $tmuxLines += 'echo "🖥️  tmux スクリプト配置中..."'
    $tmuxLines += 'TMUX_BASE="${LINUX_BASE}/${PROJECT_NAME}/scripts/tmux"'
    $tmuxLines += 'sudo mkdir -p "${TMUX_BASE}/panes"'
    $tmuxLines += 'sudo mkdir -p "${TMUX_BASE}/layouts"'

    foreach ($entry in $EncodedTmuxScripts.GetEnumerator()) {
        $tmuxLines += "echo '" + $entry.Value + "' | base64 -d | sudo tee " + '"${TMUX_BASE}/' + $entry.Key + '"' + ' > /dev/null'
    }

    $tmuxLines += 'sudo chmod +x "${TMUX_BASE}"/*.sh "${TMUX_BASE}/panes"/*.sh 2>/dev/null || true'

    if ($TmuxAutoInstall -eq "true") {
        $tmuxLines += ""
        $tmuxLines += "# tmux 自動インストール"
        $tmuxLines += 'if ! command -v tmux &>/dev/null; then'
        $tmuxLines += '    echo "📦 tmux インストール中..."'
        $tmuxLines += '    "${TMUX_BASE}/tmux-install.sh" || echo "⚠️  tmux インストールに失敗しました"'
        $tmuxLines += 'else'
        $tmuxLines += '    echo "✅ tmux インストール済み: $(tmux -V)"'
        $tmuxLines += 'fi'
    }

    $tmuxLines += 'echo "✅ tmux スクリプト配置完了"'
    $TmuxSetupBlock = $tmuxLines -join "`n"

    Write-Host "✅ tmux スクリプト $($EncodedTmuxScripts.Count) 件エンコード完了" -ForegroundColor Green
}

# 統合リモートセットアップスクリプトを生成
$McpBackupTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$ConsolidatedSetupScript = @"
#!/bin/bash
set -euo pipefail

# 変数定義
MCP_ENABLED=$($McpEnabled.ToString().ToLower())
MCP_BACKUP_TIMESTAMP='$McpBackupTimestamp'

echo "🔍 jq パッケージ確認..."
if ! command -v jq &>/dev/null; then
    echo "⚠️  jq がインストールされていません。インストール中..."
    apt-get update && apt-get install -y jq 2>/dev/null || \
    yum install -y jq 2>/dev/null || \
    echo "❌ jqインストールに失敗しました。手動でインストールしてください: apt-get install jq または yum install jq"
else
    echo "✅ jq インストール済み"
fi

# ============================================================
# 0. プロジェクトディレクトリの書き込み権限確保（passwordless sudo）
# ============================================================
echo "🔑 プロジェクトディレクトリ権限設定中..."
sudo mkdir -p $EscapedLinuxBase/$EscapedProjectName
sudo chown -R `$USER:`$USER $EscapedLinuxBase/$EscapedProjectName
echo "✅ 権限設定完了"

# プロジェクトディレクトリ作成
echo "📁 ディレクトリ作成中..."
sudo mkdir -p $EscapedLinuxBase/$EscapedProjectName/.claude
mkdir -p ~/.claude

$TmuxSetupBlock

$(if ($statuslineEnabled -and $encodedStatusline) {@"
# statusline.sh 転送と配置
echo "📝 statusline.sh 配置中..."
echo '$encodedStatusline' | base64 -d | sudo tee $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh > /dev/null
sudo chmod +x $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh
cp $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh ~/.claude/statusline.sh
echo "✅ statusline.sh 配置完了"

# settings.json 転送
echo "⚙️  settings.json 配置中..."
echo '$encodedSettings' | base64 -d | sudo tee $EscapedLinuxBase/$EscapedProjectName/.claude/settings.json > /dev/null
echo "✅ settings.json 配置完了"

# グローバル設定更新
echo "🔄 グローバル設定更新中..."
echo '$encodedGlobalScript' | base64 -d > /tmp/update_global_settings.sh
chmod +x /tmp/update_global_settings.sh
/tmp/update_global_settings.sh
rm /tmp/update_global_settings.sh
"@} else { "echo 'ℹ️  Statusline 無効'" })

# .mcp.json バックアップ
echo "📦 .mcp.json バックアップ中..."
if [ -f $EscapedLinuxBase/$EscapedProjectName/.mcp.json ]; then
    sudo cp $EscapedLinuxBase/$EscapedProjectName/.mcp.json $EscapedLinuxBase/$EscapedProjectName/.mcp.json.bak.`${MCP_BACKUP_TIMESTAMP}
    echo "✅ バックアップ完了: .mcp.json → .mcp.json.bak.`${MCP_BACKUP_TIMESTAMP}"
else
    echo "ℹ️  .mcp.jsonが存在しません（初回起動の可能性）"
fi

# MCP 自動セットアップ
if [ "`$MCP_ENABLED" = "true" ]; then
    echo ""
    echo "🔌 MCP 自動セットアップ開始..."

    # setup-mcp.sh をデコードして実行
    MCP_SETUP_SCRIPT="/tmp/setup-mcp-`${MCP_BACKUP_TIMESTAMP}.sh"
    echo '$EncodedMcpScript' | base64 -d > "`${MCP_SETUP_SCRIPT}"
    chmod +x "`${MCP_SETUP_SCRIPT}"

    # MCP セットアップ実行 (プロジェクトディレクトリ、GitHub Token、Brave API Keyを渡す)
    "`${MCP_SETUP_SCRIPT}" "$EscapedLinuxBase/$EscapedProjectName" '$GithubTokenB64' '$BraveApiKey' || echo "⚠️  MCP セットアップでエラーが発生しましたが続行します"

    # 一時ファイル削除
    rm -f "`${MCP_SETUP_SCRIPT}"

    echo ""
fi

# （run-claude.sh は PowerShell 側から別途転送）
echo "ℹ️  run-claude.sh はセットアップ後に個別転送されます"

# ポートクリーンアップ
echo "🧹 ポート $EscapedDevToolsPort クリーンアップ中..."
fuser -k $EscapedDevToolsPort/tcp 2>/dev/null || true
echo "✅ ポートクリーンアップ完了"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ リモートセットアップ完了"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"@

# CRLF を LF に変換
$ConsolidatedSetupScript = $ConsolidatedSetupScript -replace "`r`n", "`n"
$ConsolidatedSetupScript = $ConsolidatedSetupScript -replace "`r", "`n"

# base64エンコードして転送・実行（stdin パイプ方式: コマンドライン長制限回避）
$encodedSetupScript = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ConsolidatedSetupScript))
$setupResult = $encodedSetupScript | ssh $LinuxHost "tr -d '\r' | base64 -d > /tmp/remote_setup.sh && chmod +x /tmp/remote_setup.sh && /tmp/remote_setup.sh && rm /tmp/remote_setup.sh"
Write-Host $setupResult
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ リモートセットアップに失敗しました (終了コード: $LASTEXITCODE)" -ForegroundColor Red
    Write-Host "   上記のエラー出力を確認してください" -ForegroundColor Yellow
    exit 1
}

# run-claude.sh を個別転送（stdin パイプ方式: コマンドライン長制限回避）
Write-Host "📝 run-claude.sh を転送中..."
$EncodedRunClaude | ssh $LinuxHost "tr -d '\r' | base64 -d > /tmp/run-claude-tmp.sh && chmod +x /tmp/run-claude-tmp.sh && sudo cp -f /tmp/run-claude-tmp.sh $EscapedLinuxPath && rm /tmp/run-claude-tmp.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ run-claude.sh 転送に失敗しました (終了コード: $LASTEXITCODE)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅ run-claude.sh 転送完了"
}

if ($statuslineEnabled) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  Statusline設定を反映させるには" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "【方法1: すぐに反映（推奨）】" -ForegroundColor Green
    Write-Host "   Claude Codeで以下のコマンドを実行:" -ForegroundColor White
    Write-Host "   /statusline" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host ""
    Write-Host "【方法2: 確実に反映】" -ForegroundColor Green
    Write-Host "   1. exit でClaude Codeを終了" -ForegroundColor White
    Write-Host "   2. 再度スクリプトを実行" -ForegroundColor White
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

# ============================================================
# ⑥ SSH接続 + run-claude.sh 自動実行
# ============================================================
Write-Host "`n🎉 セットアップ完了"
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "🚀 Claudeを起動します..."
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""

# SSH接続してrun-claude.shを実行（-t でpseudo-ttyを割り当て）
$EscapedLinuxBaseForSSH = Escape-SSHArgument $LinuxBase
$EscapedProjectNameForSSH = Escape-SSHArgument $ProjectName
ssh -t -o ControlMaster=no -o ControlPath=none -R "${DevToolsPort}:127.0.0.1:${DevToolsPort}" $LinuxHost "cd $EscapedLinuxBaseForSSH/$EscapedProjectNameForSSH && ./run-claude.sh"
$SSHExitCode = $LASTEXITCODE

# ===== ログ記録終了 =====
if ($LogPath) {
    try {
        Stop-Transcript

        # ログをステータス別フォルダに移動
        $LogRootDir = if ([System.IO.Path]::IsPathRooted($Config.logging.logDir)) {
            $Config.logging.logDir
        } else {
            Join-Path $RootDir $Config.logging.logDir
        }

        Move-LogToStatusFolder -LogPath $LogPath -LogRootDir $LogRootDir -ExitCode $SSHExitCode -IsError $false
    } catch {
        Write-Warning "ログ記録終了処理エラー: $_"
    }
}

# SSH終了コードをプロセス終了コードとして伝播（start.bat の ERRORLEVEL 検出に必要）
exit $SSHExitCode
