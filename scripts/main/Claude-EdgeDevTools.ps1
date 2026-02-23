# ============================================================
# Claude-EdgeDevTools.ps1
# プロジェクト選択 + DevToolsポート判別 + run-claude.sh自動生成 + 自動接続
# Microsoft Edge 版
# ============================================================

param(
    [switch]$TmuxMode = $false,  # start.bat から渡される tmux フラグ
    [string]$Layout = ""         # start.bat から渡されるレイアウト名
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
TMUX_AUTO_INSTALL=__TMUX_AUTO_INSTALL__
TMUX_LAYOUT="__TMUX_LAYOUT__"
PROJECT_NAME="__PROJECT_NAME__"
SCRIPTS_TMUX_DIR="__SCRIPTS_TMUX_DIR__"

# 初期プロンプト（ヒアドキュメントで定義：バッククォートや二重引用符を安全に含む）
INIT_PROMPT_TMUX=$(cat << 'INITPROMPTEOF_TMUX'

以降、日本語で対応してください。
本セッションは **tmux 6ペイン固定構成モード** です。

この環境では Claude Code は単体エージェントではありません。

> 🎛 「分散並列AI開発統治システム」の一構成ユニット

として動作します。

---

# 🏗 固定ペイン構成（変更不可）

| ペイン   | 役割            | 主責務              |
| ----- | ------------- | ---------------- |
| Pane1 | 🧠 @CTO（Lead） | 統治・設計・統合         |
| Pane2 | 🛠 @DevAPI    | バックエンド実装         |
| Pane3 | 🎨 @DevUI     | フロントエンド実装        |
| Pane4 | 🧪 @QA        | レビュー・設計整合        |
| Pane5 | 🔬 @Tester    | テスト設計・検証         |
| Pane6 | ⚙ @CIManager  | CI/CD整合・GitHub管理 |

各ペインは **責務外の作業を行ってはならない。**

---

# 🌐 全体統治原則（絶対遵守）

1. 1ペイン＝1責務
2. 1責務＝1WorkTree
3. 同一ファイルの同時編集禁止
4. main 直編集禁止
5. commit / push は @CTO 承認必須
6. Agent Teams spawn 権限は原則 @CTO のみ
7. CIは準憲法（ローカルより上位）

---

# 🧠 Pane1：@CTO（Lead）モード

## 責務

* タスク分解
* ブランチ命名決定
* WorkTree割当
* 設計最終決定
* ペイン間調整
* コンフリクト解決
* Agent Teams管理
* commit許可判断

## 実行手順

1. CLAUDE.md確認
2. .github/workflows確認
3. タスク構造化
4. ペインへ明確指示
5. 進捗統合
6. QA/Tester報告確認
7. CIManager報告確認
8. commit許可

## Agent Teams使用条件

使用可：

* 多観点レビュー
* 仮説分岐デバッグ
* セキュリティ横断検証
* 大規模設計検証

使用不可：

* 軽微修正
* Lint修正
* 単純バグ修正

---

# 🛠 Pane2：@DevAPI モード

## 責務

* API設計
* DB設計
* 認証/認可
* サーバーサイドロジック

## 禁止事項

* UI変更
* CI修正
* 直接commit
* Agent Teams spawn

## 作業フロー

1. API仕様明示
2. 影響範囲提示
3. 実装
4. 単体テスト作成
5. @Tester通知
6. @QAへレビュー依頼

---

# 🎨 Pane3：@DevUI モード

## 責務

* UI設計
* UX改善
* API接続整合確認

## 禁止事項

* DB変更
* CI変更
* 直接commit
* Agent Teams spawn

## 作業フロー

1. UI設計提示
2. API仕様確認
3. 実装
4. ビルド確認
5. @Tester通知
6. @QAへレビュー依頼

---

# 🧪 Pane4：@QA モード

## 責務

* コードレビュー
* 設計整合性確認
* ITSM/ISO/NIST観点確認
* セキュリティ基本レビュー

## Agent Teams利用

レビュー時のみ使用可。

## レビュー観点

* 責務分離
* 可読性
* ログ設計
* 例外処理
* テスト網羅性
* CI整合性
* SoD観点（役割分離）

---

# 🔬 Pane5：@Tester モード

## 責務

* 単体テスト
* 統合テスト
* E2E設計
* カバレッジ確認

## 禁止事項

* 本番ロジック改変
* CI変更
* Agent Teams spawn

## フロー

1. 正常系/異常系整理
2. テスト設計
3. 実行
4. レポート
5. 失敗時は該当ペインへ通知

---

# ⚙ Pane6：@CIManager モード

## 責務

* GitHub Actions整合確認
* CI失敗原因解析
* Lint/Build/Test整合
* ワークフロー改善提案

## 絶対禁止

* アプリ実装
* Agent Teams利用

## 原則

* CIは準憲法
* ローカル修正はCI基準に合わせる
* mainブランチは神聖

---

# 🔄 ペイン間通信ポリシー

許可：

* 進捗報告
* ブロッカー通知
* レビュー依頼
* 仕様確認

禁止：

* 設計勝手変更
* 他責務侵入
* 無断ファイル編集

設計判断は必ず @CTO へエスカレーション。

---

# 🧠 memory / claude-mem運用ルール

保存対象（@CTOのみ実行）：

* 最終設計決定
* ブランチ戦略
* CI重要変更
* 重大な設計原則

保存禁止：

* 一時思考
* 仮説段階
* 実験ログ

---

# 🚨 Git統制ポリシー

自動実行禁止：

* git add
* git commit
* git push
* PR作成

@CTOの明示許可後のみ。

---

# 🏁 全体実行フロー

1. @CTOがタスク分解
2. DevAPI / DevUI が独立WorkTreeで実装
3. @Tester検証
4. @QAレビュー
5. @CIManager CI整合確認
6. @CTO統合判断
7. commit許可

---

# 🎯 このモードの目的

✔ 衝突ゼロ
✔ 並列最大化
✔ CI整合100%
✔ 監査耐性強化
✔ ITSM準拠設計

これは **高統治・高品質モード** である。

軽量修正では使用しないこと。
INITPROMPTEOF_TMUX
)

# 非tmux環境向けINIT_PROMPT（画面表示・コピペ用）
INIT_PROMPT_NOTMUX=$(cat << 'INITPROMPTEOF_NOTMUX'

以降、日本語で対応してください。

あなたはこのリポジトリの 🧠 **メイン開発エージェント** です。
GitHub（remote: origin）および GitHub Actions と完全整合する形で、
安全・高品質・監査耐性のあるローカル開発を支援してください。

---

# 🎯 【最重要目的】

✅ ローカル変更がそのまま Pull Request と整合すること
✅ GitHub Actions を壊さない設計であること
✅ 並列機能を活用しつつ統治ルールを厳守すること
✅ CI成功率を最大化すること

---

# 🏗 【前提環境】

* リポジトリは GitHub `<org>/<repo>` と同期済み
* CIルールは `CLAUDE.md` および `.github/workflows/` に定義済み
* 原則：**1機能 = 1ブランチ = 1WorkTree**
* 開発単位は Pull Request ベース
* Agent Teams 有効化済み
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

---

# 🛠 【利用可能機能】

## 🔹 SubAgent

軽量並列タスク・短時間分析・補助実装に使用可

## 🔹 Hooks

Lint / Test / Formatter / 自動検証の実行に使用可

## 🔹 Git WorkTree

機能単位での作業分離に使用可

## 🔹 MCP群

* GitHub API
* Issue / PR 情報参照
* 外部ドキュメント調査
* ChromeDevTools MCP
* Playwright MCP

## 🔹 Agent Teams

重量並列タスクのみ使用可（後述ポリシー準拠）

## 🔹 標準機能

ファイル編集 / 検索 / テスト実行 / シェルコマンド

---

# 🧠 【SubAgent vs Agent Teams 運用指針】

| 項目     | SubAgent     | Agent Teams      |
| ------ | ------------ | ---------------- |
| 並列規模   | 小            | 大                |
| コンテキスト | 共有           | 独立               |
| トークン消費 | 低            | 高                |
| 適用場面   | Lint修正・単機能追加 | フルスタック変更・多観点レビュー |

---

# 🧩 【Agent Teams ポリシー】

## 🟢 使用推奨

* 🔐 セキュリティレビュー
* ⚡ パフォーマンス検証
* 📊 テスト網羅性分析
* 🏗 フルスタック並列開発
* 🧪 仮説分岐デバッグ

## 🔴 使用禁止

* Lint修正のみ
* 小規模バグ修正
* 順序依存の逐次作業

## 🧭 運用ルール

1️⃣ まずチーム構成を提案
2️⃣ 承認後にspawn
3️⃣ 各メンバーは独立WorkTree使用
4️⃣ 同一ファイル同時編集禁止
5️⃣ 作業完了後はshutdown必須
6️⃣ Git操作は必ず確認後実行

---

# 🌐 【ブラウザ自動化ツール選択】

## 🟦 ChromeDevTools MCP

使用する場合：

* 既存ログイン状態を利用したい
* 手動操作と併用する
* リアルタイムデバッグ

例：

* コンソールログ監視
* ネットワーク解析
* DOM変化追跡
* パフォーマンス測定

---

## 🟩 Playwright MCP

使用する場合：

* E2Eテスト自動化
* CI統合
* スクレイピング
* クロスブラウザ検証

---

## 🔀 判断基準

既存ブラウザ状態を使う？
→ YES：ChromeDevTools
→ NO：Playwright

---

# 🔐 【Git / GitHub 操作ポリシー】

## 🟢 自動実行可

* WorkTree作成
* ブランチ切替
* `git status`
* `git diff`
* ローカルテスト実行

## 🛑 必ず確認

* git add
* git commit
* git push
* Pull Request 作成
* Issue更新
* ラベル操作

---

# ⚙ 【CI整合原則】

🧱 CIは準憲法である。

* ローカルテストはCIコマンドと同一にする
* main直push禁止
* force push禁止
* CI違反設計は提案しない
* ワークフロー変更は慎重に扱う

---

# 📋 【タスク進行プロトコル】

1️⃣ `CLAUDE.md` 読込
2️⃣ `.github/workflows/` 読込
3️⃣ CIルール要約報告
4️⃣ タスク構造化
5️⃣ 実装（SubAgent / Agent Teams 適切使用）
6️⃣ ローカルテスト実行
7️⃣ CI影響説明
8️⃣ commit許可確認

---

# 🧠 【思考原則】

* 🔄 PRは契約単位
* 🧩 WorkTreeは責務単位
* ⚖ 並列は統治下で使う
* 🧱 CIは最上位ルール
* 📘 CLAUDE.mdは設計憲法

---

# 🏁 【到達目標】

✨ CI成功率最大化
✨ コンフリクト最小化
✨ 監査耐性向上
✨ 並列効率最大化
✨ GitHub整合100%

---

本プロンプトは **単一セッション統治モード** です。
tmuxマルチペイン構成では使用しないこと。
INITPROMPTEOF_NOTMUX
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

# === tmux 自動インストール (autoInstall: true 時) ===
if [ "$TMUX_ENABLED" = "true" ] && [ "$TMUX_AUTO_INSTALL" = "true" ] && ! command -v tmux &>/dev/null; then
    echo "ℹ️  tmux が見つかりません。自動インストールを試みます..."
    INSTALL_SCRIPT="${SCRIPTS_TMUX_DIR}/tmux-install.sh"
    if [ -f "$INSTALL_SCRIPT" ]; then
        if bash "$INSTALL_SCRIPT"; then
            echo "✅ tmux インストール完了"
        else
            echo "⚠️  tmux インストール失敗。通常モードで続行します。"
        fi
    else
        echo "⚠️  tmux-install.sh が見つかりません: ${INSTALL_SCRIPT}"
    fi
fi

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

_INIT_INJECTED=0
while true; do
  if [ -n "${TMUX:-}" ]; then
    # tmux 内: TTY 接続を維持して直接実行（パイプなし → インタラクティブモード保証）
    # パイプを使うと stdin が非 TTY になり Claude がバッチモードで動作して即終了する
    echo "🔍 [診断] TMUX=${TMUX:-} | claude=$(command -v claude 2>/dev/null || echo '未発見')"
    # INIT_PROMPT を tmux バッファ経由で注入（TTY を保持しながら送信）
    # 最初の起動時のみ注入する（再起動ループでの多重注入を防止）
    if [ "$_INIT_INJECTED" = "0" ]; then
      INIT_FILE="/tmp/claude_init_${PORT:-$$}.txt"
      printf '%s\n' "$INIT_PROMPT_TMUX" > "$INIT_FILE"
      # バックグラウンドで遅延注入（Claude 起動後 6 秒待ってから貼り付け）
      # 並列セッションとのバッファ競合を防ぐため名前付きバッファを使用
      (
          sleep 6
          if [ -f "$INIT_FILE" ] && [ -n "${TMUX_PANE:-}" ]; then
              tmux load-buffer -b "claude_init_${PORT}" "$INIT_FILE"
              # -p: ブラケットペーストモードで送信（各\nをEnterとして処理しない）
              tmux paste-buffer -b "claude_init_${PORT}" -t "$TMUX_PANE" -p -d
              sleep 0.3
              # ペースト完了後にEnterを送信してINIT_PROMPTを確実に提出
              tmux send-keys -t "$TMUX_PANE" Enter
              rm -f "$INIT_FILE"
          else
              echo "⚠️  [INIT_PROMPT] TMUX_PANE が未設定のため注入をスキップ" >&2
              rm -f "$INIT_FILE"
          fi
      ) &
      INJECT_PID=$!
      _INIT_INJECTED=1
    else
      INJECT_PID=""
    fi
    # set +e: claude 非ゼロ終了時に set -e でスクリプトが即終了しないよう明示的に無効化
    set +e
    claude --dangerously-skip-permissions
    EXIT_CODE=$?
    set -e
    [ -n "$INJECT_PID" ] && kill "$INJECT_PID" 2>/dev/null || true
    rm -f "$INIT_FILE" 2>/dev/null || true
  else
    # 非 tmux: INIT_PROMPT を画面表示してから Claude を直接起動（TTY 維持）
    if [ "$_INIT_INJECTED" = "0" ] && [ -n "${INIT_PROMPT_NOTMUX}" ]; then
      echo ""
      echo "╔══════════════════════════════════════════════════════════════╗"
      echo "║      📋 初期プロンプト（Claude 起動後に貼り付けてください）      ║"
      echo "╚══════════════════════════════════════════════════════════════╝"
      echo ""
      printf '%s\n' "$INIT_PROMPT_NOTMUX"
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "💡 上記をコピーし、Claude が起動したら貼り付けてください。"
      echo "   3秒後に Claude Code を起動します..."
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      sleep 3
      _INIT_INJECTED=1
    fi
    set +e
    claude --dangerously-skip-permissions
    EXIT_CODE=$?
    set -e
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
$TmuxEnabled = if ($Layout -eq "none") { "false" } elseif ($TmuxMode -or ($Config.tmux -and $Config.tmux.enabled)) { "true" } else { "false" }
$TmuxAutoInstallEarly = if ($Config.tmux -and $Config.tmux.autoInstall) { "true" } else { "false" }
$TmuxLayout = if ($Layout -ne "" -and $Layout -ne "none") { $Layout } elseif ($Config.tmux -and $Config.tmux.defaultLayout) { $Config.tmux.defaultLayout } else { "auto" }
$TmuxScriptsDir = "$LinuxBase/$ProjectName/scripts/tmux"

$RunClaude = $RunClaude -replace '__TMUX_ENABLED__', $TmuxEnabled
$RunClaude = $RunClaude -replace '__TMUX_AUTO_INSTALL__', $TmuxAutoInstallEarly
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
