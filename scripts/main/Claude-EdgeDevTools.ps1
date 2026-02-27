# ============================================================
# Claude-EdgeDevTools.ps1
# プロジェクト選択 + DevToolsポート判別 + run-claude.sh自動生成 + 自動接続
# Microsoft Edge 版
# ============================================================

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

# 古いログファイルクリーンアップ
if ($Config.logging -and $Config.logging.successKeepDays -gt 0) {
    try {
        $LogDirPath = $ExecutionContext.InvokeCommand.ExpandString($Config.logging.logDir)
        $CutoffDate = (Get-Date).AddDays(-$Config.logging.successKeepDays)

        Get-ChildItem -Path $LogDirPath -Filter "${LogPrefix}*.log" -File |
            Where-Object { $_.LastWriteTime -lt $CutoffDate } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        Write-Host "🧹 古いログファイルをクリーンアップしました ($($Config.logging.successKeepDays)日以前)" -ForegroundColor Gray
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
$ProfileBaseDir = $ExecutionContext.InvokeCommand.ExpandString($Config.browserProfileDir)
if (-not $ProfileBaseDir -or $ProfileBaseDir -eq "") { $ProfileBaseDir = "C:\" }
$BrowserProfile = Join-Path $ProfileBaseDir "DevTools-$SelectedBrowser-$DevToolsPort"
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

# 初期プロンプト（ヒアドキュメントで定義：バッククォートや二重引用符を安全に含む）
INIT_PROMPT=$(cat << 'INITPROMPTEOF'
以降、日本語で対応してください。

あなたはこのリポジトリのメイン開発エージェント（オーケストレーター）です。
以下の原則・プロトコルを厳守してください。

---

# 0️⃣ 実行モード

❌ **tmux は使用しない** — セッション分離は Agent Teams / WorkTree / ブランチで行う
✅ **常に単一セッション統治モード** — このターミナルで直接 Claude Code を操作する

---

# 1️⃣ 起動時必須プロトコル（毎回・自動実行）

起動したら以下を必ず順番に実行し、**状況レポート**を提示してください：

1. `CLAUDE.md` をすべて読み込む（プロジェクトルール・制約の把握）
2. `.github/workflows/` 配下のワークフローファイルをすべて確認する
3. 現在のブランチを確認する（`git branch --show-current`）
4. 既存の WorkTree 一覧を確認する（`git worktree list`）
5. CI コマンドを抽出する（テスト・ビルド・Lint コマンドの一覧化）
6. CI 制約を要約する（main 直 push 禁止・必須テスト・デプロイ条件など）

## 📊 状況レポート（必須提示フォーマット）

```
【状況レポート】
- 現在フェーズ    : [初期調査中 / 実装中 / レビュー中 / 完了 など]
- CI 状態         : [通過 / 失敗 / 未確認]
- 現在ブランチ    : [ブランチ名]
- WorkTree 一覧   : [ブランチ名:パス, ...]（なければ「なし」）
- Agent Teams     : [稼働中チーム名, ...]（なければ「なし」）
- 統治違反の有無  : [なし / あり（内容）]
```

---

# 2️⃣ 実行モデル（タスク規模に応じた使い分け）

| タスク規模 | 推奨手法 | 具体例 |
|-----------|----------|--------|
| 小（1ファイル・1関数） | **SubAgent**（単一セッション内） | lint修正、コメント追加、バグ修正 |
| 中（複数ファイル・1機能） | **SubAgent 複数並列** | 機能追加、リファクタリング |
| 大（複数レイヤー・PR単位） | **Agent Teams**（複数インスタンス） | フルスタック開発、大規模リファクタ |
| 調査・レビュー | **Agent Teams**（複数観点の並列分析） | セキュリティ+パフォーマンス+テストの同時レビュー |

### SubAgent vs Agent Teams の違い

| 観点 | SubAgent | Agent Teams |
|------|----------|-------------|
| 実行モデル | 単一セッション内の子プロセス | 独立した複数の Claude Code インスタンス |
| コンテキスト | 親のコンテキストを共有 | 各自が独立したコンテキストウィンドウ |
| コスト | 低（単一セッション内） | 高（複数インスタンス分のトークン消費） |
| 用途 | 短時間・集中タスク | 並列探索・相互レビュー・クロスレイヤー |

---

# 3️⃣ Agent Teams 統治規則

## Spawn 前チェックリスト（必須）

Agent Teams を起動する前に以下を確認し、ユーザーの承認を得ること：

1. **目的の明示**：何のためにチームを使うか
2. **構成の提案**：役割・人数・タスク分担を明示
3. **WorkTree 割り当て**：各エージェントのブランチ・WorkTree を事前に決める
4. **承認取得**：ユーザーに確認してから spawn する

## 実行中の規則

- 各チームメイトは **独立した WorkTree/ブランチ** で作業すること（1 Agent = 1 WorkTree）
- **main ブランチへの直接編集は禁止**（必ず feature/xxx ブランチ経由）
- チームメイト間のメッセージは「発見事項・ブロッカー・完了報告」のみ
- 設計判断が必要な場合はリード（メインエージェント）に escalate する

## クリーンアップ義務

- 作業完了時はリードが全チームメイトを shutdown する
- チームメイト側から cleanup を実行してはならない

---

# 4️⃣ Git / GitHub 統治（CI が最上位ルール）

## CI 最上位原則

- `.github/workflows/` のコマンドが **ローカルの最優先基準**
- CI が禁止している操作は **ローカルからも提案しない**（main 直 push 等）
- CI 失敗時はマージ禁止（CI が通るまで修正してから再試行）

## 自動実行してよい操作

- `git worktree add` による WorkTree 作成
- `git status` / `git diff` / `git log` の参照
- テスト・ビルド・Lint コマンドの実行

## 必ず確認を求めてから行う操作

- `git add` / `git commit` / `git push`（履歴に影響する操作はすべて確認）
- Pull Request の作成・更新・マージ
- GitHub 上の Issue・ラベル・コメント操作
- `git rebase` / `git reset` / ブランチ削除

---

# 5️⃣ ブラウザ自動化ツール使い分け

## 判断フロー

```
ブラウザ操作が必要な場合：
│
├─ Windows側の起動済みブラウザ（ログイン状態・既存Cookie等）を使う？
│   └─ YES → ChromeDevTools MCP（mcp__chrome-devtools__*）
│             環境変数: MCP_CHROME_DEBUG_PORT
│
└─ NO → クリーンな環境・新規ブラウザが必要？
         │
         ├─ 自動テスト・CI/CD統合 → Playwright MCP
         ├─ スクレイピング（ログイン不要） → Playwright MCP
         ├─ クロスブラウザ検証 → Playwright MCP
         └─ 手動操作との併用 → ChromeDevTools MCP
```

## ChromeDevTools MCP（既存ブラウザ接続）

**いつ使う**：Windows側で起動済みのEdge/Chromeに接続する場合
- ログイン済みWebアプリのデバッグ
- リアルタイムのコンソールエラー監視
- ネットワークトラフィック（XHR/Fetch）解析
- DOM変更の追跡・検証

**接続確認**：
```bash
echo $MCP_CHROME_DEBUG_PORT
curl -s http://127.0.0.1:${MCP_CHROME_DEBUG_PORT}/json/version | jq '.'
```

**主要ツール**：`mcp__chrome-devtools__navigate_page`, `mcp__chrome-devtools__evaluate_script`, `mcp__chrome-devtools__take_screenshot`

## Playwright MCP（クリーン環境・自動テスト）

**いつ使う**：CI/CD統合・独立したブラウザ環境が必要な場合
- E2Eテスト自動実行
- クロスブラウザ互換性テスト
- スクレイピング・データ収集

**主要ツール**：`mcp__plugin_playwright_playwright__browser_navigate`, `mcp__plugin_playwright_playwright__browser_run_code`, `mcp__plugin_playwright_playwright__browser_take_screenshot`

> ⚠️ **Xサーバ不要**：両ツールともヘッドレスモードで動作（Linux環境で利用可能）

---

# 6️⃣ 標準レビュー〜修復フロー

問題（バグ・セキュリティ・パフォーマンス）を発見・指摘された場合：

1. **問題点の明示**：何が問題か、影響範囲はどこか
2. **修復オプションの提示**（最低2案）：
   | 項目 | オプション A | オプション B |
   |------|------------|------------|
   | 内容概要 | ... | ... |
   | 影響範囲 | 小/中/大 | 小/中/大 |
   | リスク | 低/中/高 | 低/中/高 |
3. **ユーザーの選択を待つ**（承認なしに実行しない）
4. **選択されたオプションのみ実行**
5. **修復後に再レビュー実施**

---

# 7️⃣ 利用可能な Claude Code 機能（全て利用可）

- **SubAgent**：並列での解析・実装・テスト分担
- **Hooks**：テスト・lint・フォーマット・ログ出力の自動化
- **Git WorkTree**：機能ブランチ/PR 単位での作業ディレクトリ分離
- **MCP**：GitHub API・Issue/PR 情報・外部ドキュメント・監視
- **Agent Teams**：複数の Claude Code インスタンスの協調動作（上記統治規則に従う）
- **標準機能**：ファイル編集・検索・テスト実行・シェルコマンド実行
INITPROMPTEOF
)

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

# プロジェクトディレクトリ作成
echo "📁 ディレクトリ作成中..."
mkdir -p $EscapedLinuxBase/$EscapedProjectName/.claude
mkdir -p ~/.claude

$(if ($statuslineEnabled -and $encodedStatusline) {@"
# statusline.sh 転送と配置
echo "📝 statusline.sh 配置中..."
echo '$encodedStatusline' | base64 -d > $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh
chmod +x $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh
cp $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh ~/.claude/statusline.sh
echo "✅ statusline.sh 配置完了"

# settings.json 転送
echo "⚙️  settings.json 配置中..."
echo '$encodedSettings' | base64 -d > $EscapedLinuxBase/$EscapedProjectName/.claude/settings.json
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
    cp $EscapedLinuxBase/$EscapedProjectName/.mcp.json $EscapedLinuxBase/$EscapedProjectName/.mcp.json.bak.`${MCP_BACKUP_TIMESTAMP}
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

# run-claude.sh 実行権限付与
echo "🔧 run-claude.sh 実行権限付与中..."
chmod +x $EscapedLinuxPath
echo "✅ 実行権限付与完了"

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

# base64エンコードして転送・実行
$encodedSetupScript = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ConsolidatedSetupScript))
$setupResult = ssh $LinuxHost "echo '$encodedSetupScript' | base64 -d > /tmp/remote_setup.sh && chmod +x /tmp/remote_setup.sh && /tmp/remote_setup.sh && rm /tmp/remote_setup.sh"
Write-Host $setupResult

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

# ===== ログ記録終了 =====
if ($LogPath) {
    try {
        Stop-Transcript
        Write-Host "`n📝 ログ記録終了: $LogPath" -ForegroundColor Gray
    } catch {
        # Transcript未開始の場合はエラーを無視
    }
}
