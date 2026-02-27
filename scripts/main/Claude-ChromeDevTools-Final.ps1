# ============================================================
# Claude-ChromeDevTools-Final.ps1
# プロジェクト選択 + DevToolsポート判別 + run-claude.sh自動生成 + 自動接続
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('edge', 'chrome', '')]
    [string]$Browser = "",           # "" = 対話モード, "edge"/"chrome" = 非対話モード

    [Parameter(Mandatory=$false)]
    [string]$Project = "",           # "" = 対話モード, "project-name" = 非対話モード

    [Parameter(Mandatory=$false)]
    $ProjectsInput = "",             # 複数プロジェクト指定（カンマ区切り: "proj1,proj2,proj3"）※内部で$Projects配列を使うため変数名変更

    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 65535)]
    [int]$Port = 0,                  # 0 = 自動割り当て, 9222-9229 = 指定ポート

    [Parameter(Mandatory=$false)]
    [switch]$NonInteractive,         # 非対話フラグ

    [Parameter(Mandatory=$false)]
    [switch]$SkipBrowser             # CI環境用（ブラウザ起動スキップ）
)

$ErrorActionPreference = "Stop"

# ===== ログ記録開始 =====
$LogPath = $null
$LogTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir = $env:TEMP
$LogPrefix = "claude-devtools-chrome"
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

# config.json 必須フィールド検証
$requiredFields = @('ports', 'zDrive', 'linuxHost', 'linuxBase', 'edgeExe', 'chromeExe')
foreach ($field in $requiredFields) {
    if (-not $Config.$field) {
        Write-Error "❌ config.jsonに必須フィールドが不足しています: $field"
    }
}

# ポート番号の妥当性検証
foreach ($port in $Config.ports) {
    if ($port -lt 1024 -or $port -gt 65535) {
        Write-Error "❌ 無効なポート番号: $port (有効範囲: 1024-65535)"
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

# ===== 非対話モード処理 =====
if ($NonInteractive) {
    Write-Host "`nℹ️  非対話モード" -ForegroundColor Cyan

    # 必須パラメータチェック
    if (-not $Browser) {
        Write-Error "❌ 非対話モードでは -Browser パラメータが必須です (edge または chrome)"
    }
    if (-not $Project) {
        Write-Error "❌ 非対話モードでは -Project パラメータが必須です"
    }

    # ポート指定がある場合は上書き
    if ($Port -gt 0) {
        if ($Port -notin $AvailablePorts) {
            Write-Warning "指定されたポート $Port は config.json の ports 配列にありません"
        }
        $DevToolsPort = $Port
        $Global:DevToolsPort = $Port
    }

    # ブラウザ選択を自動化
    $BrowserChoice = if ($Browser -eq "edge") { "1" } else { "2" }

    Write-Host "  ブラウザ: $Browser"
    Write-Host "  プロジェクト: $Project"
    Write-Host "  ポート: $DevToolsPort"
    if ($SkipBrowser) {
        Write-Host "  ブラウザ起動: スキップ" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ===== ブラウザ自動選択UI =====
if (-not $NonInteractive) {
    Write-Host "`n🌐 ブラウザを選択してください:`n"
    Write-Host "[1] Microsoft Edge"
    Write-Host "[2] Google Chrome"
    Write-Host ""
}

# 入力検証付きブラウザ選択（対話モードのみ）
if (-not $NonInteractive) {
    do {
        $BrowserChoice = Read-Host "番号を入力 (1-2, デフォルト: 2)"

    # 空入力はデフォルト
    if ([string]::IsNullOrWhiteSpace($BrowserChoice)) {
        $BrowserChoice = "2"
        break
    }

    # 有効な選択肢のみ受付
    if ($BrowserChoice -in @("1", "2")) {
        break
    }

    Write-Host "❌ 無効な入力です。1 または 2 を入力してください。" -ForegroundColor Red
} while ($true)
}

if ($BrowserChoice -eq "1") {
    $SelectedBrowser = "edge"
    $BrowserExe = $EdgeExe
    $BrowserName = "Microsoft Edge"
} else {
    $SelectedBrowser = "chrome"
    $BrowserExe = $ChromeExe
    $BrowserName = "Google Chrome"
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

# プロジェクト一覧取得（ディレクトリのみ）
# 注意: パラメータの [string]$Projects との型衝突を避けるため、変数名は $Projects（配列）を使用
$RawItems = @(Get-ChildItem -Path $ProjectRootPath -ErrorAction Stop)
$Projects = @($RawItems |
    Where-Object { $_.PSIsContainer -eq $true } |
    Where-Object { ![string]::IsNullOrEmpty($_.Name) } |
    Sort-Object { $_.Name })

if ($Projects.Count -eq 0) {
    Write-Error "❌ プロジェクトルート ($ProjectRootPath) にプロジェクトが見つかりません"
}

# 非対話モード: プロジェクト名から自動選択
# 非対話モード: 複数プロジェクト指定対応
if ($NonInteractive -and ($Project -or $ProjectsInput)) {
    $SelectedProjects = @()

    if ($ProjectsInput) {
        # 複数プロジェクト指定（カンマ区切り）
        $ProjectNames = $ProjectsInput -split ',' | ForEach-Object { $_.Trim() }

        foreach ($projName in $ProjectNames) {
            $proj = $Projects | Where-Object { $_.Name -eq $projName }
            if (-not $proj) {
                Write-Error "❌ プロジェクト '$projName' が見つかりません。利用可能: $($Projects.Name -join ', ')"
            }
            $SelectedProjects += $proj
        }

        Write-Host "📦 選択プロジェクト ($($SelectedProjects.Count)件): $($SelectedProjects.Name -join ', ') (非対話モード)`n" -ForegroundColor Cyan
    } else {
        # 単一プロジェクト指定
        $SelectedProject = $Projects | Where-Object { $_.Name -eq $Project }

        if (-not $SelectedProject) {
            Write-Error "❌ プロジェクト '$Project' が見つかりません。利用可能: $($Projects.Name -join ', ')"
        }

        $SelectedProjects = @($SelectedProject)
        Write-Host "📦 プロジェクト: $($SelectedProject.Name) (非対話モード)`n" -ForegroundColor Cyan
    }

    $ProjectName = $SelectedProjects[0].Name
    $ProjectRoot = $SelectedProjects[0].FullName
} else {
    # 対話モード: ユーザーに選択を促す
    Write-Host "📦 プロジェクトを選択してください (複数選択可能)`n"

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

    Write-Host "`nヒント:"
    Write-Host "  単一選択: 3"
    Write-Host "  複数選択: 1,3,5"
    Write-Host "  範囲選択: 1-3 (プロジェクト1,2,3)"
    Write-Host ""

    # 複数選択対応の入力検証
    do {
        $IndexInput = Read-Host "番号を入力 (1-$($Projects.Count))"
        $SelectedProjects = @()
        $inputValid = $true

        try {
            if ($IndexInput -match '-') {
                # 範囲指定 (例: 1-3)
                $rangeParts = $IndexInput -split '-'
                if ($rangeParts.Count -ne 2) {
                    throw "無効な範囲指定です"
                }
                $start = [int]$rangeParts[0]
                $end = [int]$rangeParts[1]

                if ($start -lt 1 -or $end -gt $Projects.Count -or $start -gt $end) {
                    throw "無効な範囲です: $start-$end"
                }

                for ($i = $start; $i -le $end; $i++) {
                    $SelectedProjects += $Projects[$i - 1]
                }
            } elseif ($IndexInput -match ',') {
                # カンマ区切り (例: 1,3,5)
                $indices = $IndexInput -split ',' | ForEach-Object { $_.Trim() }

                foreach ($idxStr in $indices) {
                    if ($idxStr -notmatch '^\d+$') {
                        throw "無効な数値: $idxStr"
                    }
                    $idx = [int]$idxStr
                    if ($idx -lt 1 -or $idx -gt $Projects.Count) {
                        throw "範囲外のインデックス: $idx"
                    }
                    $SelectedProjects += $Projects[$idx - 1]
                }
            } else {
                # 単一選択
                if ($IndexInput -notmatch '^\d+$') {
                    throw "数字を入力してください"
                }
                $idx = [int]$IndexInput
                if ($idx -lt 1 -or $idx -gt $Projects.Count) {
                    throw "1から$($Projects.Count)の範囲で入力してください"
                }
                $SelectedProjects += $Projects[$idx - 1]
            }
            break
        } catch {
            Write-Host "❌ $_" -ForegroundColor Red
            continue
        }
    } while ($true)

    # 単一プロジェクト用の変数も設定（後方互換性）
    $ProjectName = $SelectedProjects[0].Name
    $ProjectRoot = $SelectedProjects[0].FullName
}

# プロジェクト確認
if (-not $ProjectName -or -not $ProjectRoot) {
    Write-Error "❌ プロジェクトが正しく選択されていません"
}

# 選択プロジェクト確認表示（単数/複数対応）
if ($SelectedProjects.Count -eq 1) {
    Write-Host "`n✅ 選択プロジェクト: $ProjectName"
} else {
    Write-Host "`n✅ 選択プロジェクト ($($SelectedProjects.Count)件): $($SelectedProjects.Name -join ', ')" -ForegroundColor Green
}

# 履歴更新（複数プロジェクト対応）
if ($HistoryEnabled) {
    try {
        foreach ($proj in $SelectedProjects) {
            Update-RecentProjects -ProjectName $proj.Name -HistoryPath $HistoryPath -MaxHistory $Config.recentProjects.maxHistory
        }
        if ($SelectedProjects.Count -eq 1) {
            Write-Host "📝 最近使用プロジェクトに記録しました" -ForegroundColor Gray
        } else {
            Write-Host "📝 $($SelectedProjects.Count)件のプロジェクトを履歴に記録しました" -ForegroundColor Gray
        }
    } catch {
        Write-Warning "履歴更新に失敗しましたが続行します: $_"
    }
}

# ポート自動割り当て（複数プロジェクト対応）
$ProjectPortMap = @{}
$AssignedPorts = @()

if ($SelectedProjects.Count -gt 1) {
    # 複数プロジェクト: 各プロジェクトにポート割り当て
    Write-Host "`n📌 ポート割り当て:" -ForegroundColor Cyan

    if ($SelectedProjects.Count -gt $AvailablePorts.Count) {
        Write-Error "❌ 利用可能なポート不足: 必要 $($SelectedProjects.Count)件, 利用可能 $($AvailablePorts.Count)件"
    }

    foreach ($proj in $SelectedProjects) {
        $port = Get-AvailablePort -Ports ($AvailablePorts | Where-Object { $_ -notin $AssignedPorts })

        if (-not $port) {
            Write-Error "❌ ポート割り当て失敗: $($proj.Name)"
        }

        $ProjectPortMap[$proj.Name] = $port
        $AssignedPorts += $port
        Write-Host "  $($proj.Name) → ポート $port"
    }
    Write-Host ""
} else {
    # 単一プロジェクト: 既存の$DevToolsPort使用
    $ProjectPortMap[$ProjectName] = $DevToolsPort
    $AssignedPorts += $DevToolsPort
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
# ④ ブラウザ DevTools 起動（専用プロファイル）
# ============================================================

if ($SkipBrowser) {
    Write-Host "`nℹ️  ブラウザ起動をスキップします（-SkipBrowser フラグ）" -ForegroundColor Yellow
    Write-Host "   DevTools は既に起動済みであることを前提とします`n"
} else {
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

Write-Host "🌐 $BrowserName DevTools 起動中..."

# ブラウザ を起動（明示的なオプション付き + localhost URL）
$StartUrl = "http://localhost:$DevToolsPort"

$browserArgs = @(
    "--remote-debugging-port=$DevToolsPort",
    "--user-data-dir=`"$BrowserProfile`"",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-allow-origins=*",
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

    # バージョン情報を表示 ($versionInfo は接続確認時に既に取得済み)
    Write-Host "📋 $BrowserName 情報:"
    Write-Host "   - Browser: $($versionInfo.Browser)"
    Write-Host "   - Protocol: $($versionInfo.'Protocol-Version')"
    Write-Host "   - V8: $($versionInfo.'V8-Version')"
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
}  # End of SkipBrowser conditional

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

trap 'echo "🛑 Ctrl+C で終了"; exit 0' INT

echo "🔍 DevTools 応答確認..."
echo "PORT=${PORT}"
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

# Agent Teams オーケストレーション有効化
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# on-startup hook 実行（環境変数設定後）
if [ -f ".claude/hooks/on-startup.sh" ]; then
    bash .claude/hooks/on-startup.sh
fi

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

echo ""
echo "🚀 Claude 起動 (port=${PORT})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 初期プロンプトを自動入力します..."
echo ""

while true; do
  # 初期プロンプトをパイプで自動入力
  echo "$INIT_PROMPT" | claude --dangerously-skip-permissions
  EXIT_CODE=$?

  [ "$EXIT_CODE" -eq 0 ] && break

  echo ""
  echo "🔄 Claude 再起動 (${RESTART_DELAY}秒後)..."
  sleep $RESTART_DELAY
done

echo "👋 終了しました"
'@

# ポート番号を置換
$RunClaude = $RunClaude -replace '__DEVTOOLS_PORT__', $DevToolsPort

# CRLF を LF に変換
$RunClaude = $RunClaude -replace "`r`n", "`n"
$RunClaude = $RunClaude -replace "`r", "`n"

# UTF-8 No BOM で書き込み
[System.IO.File]::WriteAllText($RunClaudePath, $RunClaude, [System.Text.UTF8Encoding]::new($false))

Write-Host "✅ run-claude.sh 生成完了"

# ============================================================
# ⑤-b リモートセットアップ統合スクリプト
# ============================================================
Write-Host "🔧 リモートセットアップを実行中..."

# SSH引数をエスケープ
$EscapedProjectName = Escape-SSHArgument $ProjectName
$EscapedLinuxBase = Escape-SSHArgument $LinuxBase
$EscapedLinuxPath = Escape-SSHArgument $LinuxPath
$EscapedDevToolsPort = Escape-SSHArgument $DevToolsPort

# Statusline設定の準備
$StatuslineSource = Join-Path (Split-Path $PSScriptRoot -Parent) "statusline.sh"
$StatuslineEnabled = $Config.statusline.enabled -and (Test-Path $StatuslineSource)

if ($StatuslineEnabled) {
    # statusline.sh をBase64エンコード
    $statuslineContent = Get-Content $StatuslineSource -Raw
    $statuslineContent = $statuslineContent -replace "`r`n", "`n"
    $statuslineContent = $statuslineContent -replace "`r", "`n"
    $EncodedStatusline = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($statuslineContent))

    # settings.json を生成
    $SettingsJson = @{
        statusLine = @{
            type = "command"
            command = "$LinuxBase/$ProjectName/.claude/statusline.sh"
            padding = 0
        }
    } | ConvertTo-Json -Depth 3 -Compress
    $EncodedSettings = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($SettingsJson))

    # config.jsonのclaudeCodeセクションから設定を読み取る
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
    $settingsJsonStr = "{$($settingsEntries -join ', ')}"
}

# .mcp.json バックアップのタイムスタンプ
$McpBackupTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# Hooks スクリプトの準備
$HooksDir = Join-Path (Split-Path $PSScriptRoot -Parent) "hooks"
$HooksEnabled = (Test-Path $HooksDir)
$EncodedOnStartup = ""
$EncodedPreCommit = ""
$EncodedPostCheckout = ""
$EncodedContextLoader = ""

if ($HooksEnabled) {
    # on-startup.sh をBase64エンコード
    $onStartupPath = Join-Path $HooksDir "on-startup.sh"
    if (Test-Path $onStartupPath) {
        $content = Get-Content $onStartupPath -Raw
        $content = $content -replace "`r`n", "`n" -replace "`r", "`n"
        $EncodedOnStartup = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    }

    # pre-commit.sh をBase64エンコード
    $preCommitPath = Join-Path $HooksDir "pre-commit.sh"
    if (Test-Path $preCommitPath) {
        $content = Get-Content $preCommitPath -Raw
        $content = $content -replace "`r`n", "`n" -replace "`r", "`n"
        $EncodedPreCommit = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    }

    # post-checkout.sh をBase64エンコード
    $postCheckoutPath = Join-Path $HooksDir "post-checkout.sh"
    if (Test-Path $postCheckoutPath) {
        $content = Get-Content $postCheckoutPath -Raw
        $content = $content -replace "`r`n", "`n" -replace "`r", "`n"
        $EncodedPostCheckout = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    }

    # context-loader.sh をBase64エンコード
    $contextLoaderPath = Join-Path $HooksDir "lib\context-loader.sh"
    if (Test-Path $contextLoaderPath) {
        $content = Get-Content $contextLoaderPath -Raw
        $content = $content -replace "`r`n", "`n" -replace "`r", "`n"
        $EncodedContextLoader = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
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

# 統合リモートセットアップスクリプト
$RemoteSetupScript = @"
#!/bin/bash
set -e

# 変数定義
PROJECT_NAME=$EscapedProjectName
LINUX_BASE=$EscapedLinuxBase
LINUX_PATH=$EscapedLinuxPath
DEVTOOLS_PORT=$EscapedDevToolsPort
STATUSLINE_ENABLED=$($StatuslineEnabled.ToString().ToLower())
MCP_ENABLED=$($McpEnabled.ToString().ToLower())
MCP_BACKUP_TIMESTAMP='$McpBackupTimestamp'

PROJECT_DIR="`${LINUX_BASE}/`${PROJECT_NAME}"
CLAUDE_DIR="`${PROJECT_DIR}/.claude"
MCP_PATH="`${PROJECT_DIR}/.mcp.json"
MCP_BACKUP="`${PROJECT_DIR}/.mcp.json.bak.`${MCP_BACKUP_TIMESTAMP}"

echo "🔧 リモートセットアップ開始..."

# ============================================================
# 1. jq インストール確認
# ============================================================
if ! command -v jq &>/dev/null; then
    echo "⚠️  jq がインストールされていません。インストール中..."
    if apt-get update && apt-get install -y jq 2>/dev/null; then
        echo "✅ jq インストール完了 (apt-get)"
    elif yum install -y jq 2>/dev/null; then
        echo "✅ jq インストール完了 (yum)"
    else
        echo "❌ jq インストールに失敗しました。手動でインストールしてください: apt-get install jq または yum install jq"
    fi
fi

# ============================================================
# 2. .claude ディレクトリ作成
# ============================================================
mkdir -p "`${CLAUDE_DIR}"
mkdir -p "`$HOME/.claude"

# ============================================================
# 3. Statusline設定（有効な場合）
# ============================================================
if [ "`$STATUSLINE_ENABLED" = "true" ]; then
    echo "🎨 Statusline 設定中..."

    # statusline.sh をデコードして配置
    STATUSLINE_DEST="`${CLAUDE_DIR}/statusline.sh"
    echo '$EncodedStatusline' | base64 -d > "`${STATUSLINE_DEST}"
    chmod +x "`${STATUSLINE_DEST}"

    # settings.json をデコードして配置
    SETTINGS_DEST="`${CLAUDE_DIR}/settings.json"
    echo '$EncodedSettings' | base64 -d > "`${SETTINGS_DEST}"

    # グローバルディレクトリにコピー
    cp "`${STATUSLINE_DEST}" ~/.claude/statusline.sh
    chmod +x ~/.claude/statusline.sh

    # グローバルsettings.json更新
    GLOBAL_SETTINGS="`$HOME/.claude/settings.json"
    if [ -f "`${GLOBAL_SETTINGS}" ] && command -v jq &>/dev/null; then
        # 既存設定とマージ
        jq -n --argjson settings '$settingsJsonStr' --argjson env '$envJson' \
          --slurpfile current "`${GLOBAL_SETTINGS}" \
          '`$current[0] + `$settings + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}} | .env = ((.env // {}) + `$env)' \
          > "`${GLOBAL_SETTINGS}.tmp" && mv "`${GLOBAL_SETTINGS}.tmp" "`${GLOBAL_SETTINGS}"
        echo "✅ グローバル設定をマージ更新しました"
    else
        # 新規作成
        cat > "`${GLOBAL_SETTINGS}" << 'SETTINGSEOF'
{
  "env": $envJson,
  $($settingsEntries -join ',
  '),
  "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}
}
SETTINGSEOF
        echo "✅ グローバル設定を新規作成しました"
    fi

    echo "✅ Statusline 設定完了"
fi

# ============================================================
# 3-b. Hooks 設定（別SSHコマンドで転送予定のため、ここではディレクトリ作成のみ）
# ============================================================
echo ""
echo "🪝 Hooks ディレクトリ作成中..."
mkdir -p "`${CLAUDE_DIR}/hooks/lib"
echo "✅ Hooks ディレクトリ作成完了"

# ============================================================
# 4. .mcp.json バックアップ
# ============================================================
if [ -f "`${MCP_PATH}" ]; then
    cp "`${MCP_PATH}" "`${MCP_BACKUP}"
    echo "✅ .mcp.json バックアップ完了: `${MCP_BACKUP}"
else
    echo "ℹ️  .mcp.json が見つかりません"
fi

# ============================================================
# 4-b. MCP 自動セットアップ
# ============================================================
if [ "`$MCP_ENABLED" = "true" ]; then
    echo ""
    echo "🔌 MCP 自動セットアップ開始..."

    # setup-mcp.sh をデコードして実行
    MCP_SETUP_SCRIPT="/tmp/setup-mcp-`${MCP_BACKUP_TIMESTAMP}.sh"
    echo '$EncodedMcpScript' | base64 -d > "`${MCP_SETUP_SCRIPT}"
    chmod +x "`${MCP_SETUP_SCRIPT}"

    # MCP セットアップ実行 (プロジェクトディレクトリ、GitHub Token、Brave API Keyを渡す)
    "`${MCP_SETUP_SCRIPT}" "`${PROJECT_DIR}" '$GithubTokenB64' '$BraveApiKey' || echo "⚠️  MCP セットアップでエラーが発生しましたが続行します"

    # 一時ファイル削除
    rm -f "`${MCP_SETUP_SCRIPT}"

    echo ""
fi

# ============================================================
# 5. chmod +x run-claude.sh
# ============================================================
chmod +x "`${LINUX_PATH}"
echo "✅ 実行権限付与完了: `${LINUX_PATH}"

# ============================================================
# 6. ポートクリーンアップ
# ============================================================
fuser -k "`${DEVTOOLS_PORT}/tcp" 2>/dev/null || true
echo "✅ ポート `${DEVTOOLS_PORT} クリーンアップ完了"

echo "✅ リモートセットアップ完了"
"@

# 改行を正規化
$RemoteSetupScript = $RemoteSetupScript -replace "`r`n", "`n"
$RemoteSetupScript = $RemoteSetupScript -replace "`r", "`n"

# Base64エンコード
$EncodedRemoteScript = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RemoteSetupScript))

# 単一SSH呼び出しで実行
ssh $LinuxHost "echo '$EncodedRemoteScript' | base64 -d > /tmp/remote_setup.sh && chmod +x /tmp/remote_setup.sh && /tmp/remote_setup.sh && rm /tmp/remote_setup.sh"

# Hooks ファイルを個別転送（コマンドライン長制限回避）
if ($HooksEnabled) {
    Write-Host "🪝 Hooks ファイル転送中..."

    $EscapedLinuxHooksDir = Escape-SSHArgument "$LinuxBase/$ProjectName/.claude/hooks"

    # on-startup.sh 転送
    if ($EncodedOnStartup) {
        ssh $LinuxHost "echo '$EncodedOnStartup' | base64 -d > $EscapedLinuxHooksDir/on-startup.sh && chmod +x $EscapedLinuxHooksDir/on-startup.sh"
        Write-Host "  ✅ on-startup.sh 転送完了"
    }

    # pre-commit.sh 転送
    if ($EncodedPreCommit) {
        ssh $LinuxHost "echo '$EncodedPreCommit' | base64 -d > $EscapedLinuxHooksDir/pre-commit.sh && chmod +x $EscapedLinuxHooksDir/pre-commit.sh"
        Write-Host "  ✅ pre-commit.sh 転送完了"

        # Git hooks シンボリックリンク作成
        ssh $LinuxHost "cd $EscapedLinuxBase/$EscapedProjectName && [ -d .git/hooks ] && ln -sf ../../.claude/hooks/pre-commit.sh .git/hooks/pre-commit || true" 2>$null
        Write-Host "  ✅ Git pre-commit hook 登録完了"
    }

    # post-checkout.sh 転送
    if ($EncodedPostCheckout) {
        ssh $LinuxHost "echo '$EncodedPostCheckout' | base64 -d > $EscapedLinuxHooksDir/post-checkout.sh && chmod +x $EscapedLinuxHooksDir/post-checkout.sh"
        Write-Host "  ✅ post-checkout.sh 転送完了"

        # Git hooks シンボリックリンク作成
        ssh $LinuxHost "cd $EscapedLinuxBase/$EscapedProjectName && [ -d .git/hooks ] && ln -sf ../../.claude/hooks/post-checkout.sh .git/hooks/post-checkout || true" 2>$null
        Write-Host "  ✅ Git post-checkout hook 登録完了"
    }

    # context-loader.sh 転送
    if ($EncodedContextLoader) {
        ssh $LinuxHost "echo '$EncodedContextLoader' | base64 -d > $EscapedLinuxHooksDir/lib/context-loader.sh && chmod +x $EscapedLinuxHooksDir/lib/context-loader.sh"
        Write-Host "  ✅ context-loader.sh 転送完了"
    }

    Write-Host "✅ Hooks 設定完了`n"
}

if ($StatuslineEnabled) {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              Statusline 設定完了！                           ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📋 Statusline を即座に反映する方法:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  【方法1】即座に反映（推奨）" -ForegroundColor Green
    Write-Host "     Claude Code 内で以下のコマンドを実行:" -ForegroundColor White
    Write-Host "     /statusline" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host ""
    Write-Host "  【方法2】確実に反映" -ForegroundColor Green
    Write-Host "     Claude Code を終了して再起動" -ForegroundColor White
    Write-Host ""
    Write-Host "  プロジェクト: $ProjectName" -ForegroundColor White
}

Write-Host "✅ リモートセットアップ完了"

# ============================================================
# ⑨ SSH接続 + run-claude.sh 自動実行
# ============================================================
Write-Host "`n🎉 セットアップ完了"
Write-Host ""

# ============================================================
# 単一 vs 複数プロジェクト起動分岐
# ============================================================
if ($SelectedProjects.Count -gt 1) {
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 複数プロジェクト並列起動
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "🚀 複数プロジェクト並列起動開始 ($($SelectedProjects.Count)件)" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""

    $Jobs = @()
    $BrowserProcesses = @()

    foreach ($proj in $SelectedProjects) {
        $ProjName = $proj.Name
        $ProjRoot = $proj.FullName
        $AssignedPort = $ProjectPortMap[$ProjName]

        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        Write-Host "📦 起動中: $ProjName (ポート: $AssignedPort)"

        # ブラウザ起動（プロジェクト専用プロファイル）
        if (-not $SkipBrowser) {
            $ProfileBaseDir = $ExecutionContext.InvokeCommand.ExpandString($Config.browserProfileDir)
            if (-not $ProfileBaseDir -or $ProfileBaseDir -eq "") { $ProfileBaseDir = "C:\" }
            $BrowserProfile = Join-Path $ProfileBaseDir "DevTools-$SelectedBrowser-$AssignedPort"
            $StartUrl = "http://localhost:$AssignedPort"

            $browserArgs = @(
                "--remote-debugging-port=$AssignedPort",
                "--user-data-dir=`"$BrowserProfile`"",
                "--no-first-run",
                "--no-default-browser-check",
                "--remote-allow-origins=*",
                $StartUrl
            )

            $browserProc = Start-Process -FilePath $BrowserExe -ArgumentList $browserArgs -PassThru
            $BrowserProcesses += $browserProc
            Write-Host "✅ ブラウザ起動: PID $($browserProc.Id)"
        } else {
            Write-Host "  ブラウザ起動: スキップ (CI モード)" -ForegroundColor Yellow
        }

        # SSH接続（バックグラウンドジョブ）
        $EscapedProjName = Escape-SSHArgument $ProjName
        $EscapedLinuxBase = Escape-SSHArgument $LinuxBase

        $Job = Start-Job -ScriptBlock {
            param($LinuxHost, $ProjectName, $LinuxBase, $Port)
            ssh -t -o ControlMaster=no -o ControlPath=none -R "${Port}:127.0.0.1:${Port}" $LinuxHost "cd '${LinuxBase}/${ProjectName}' && ./run-claude.sh"
        } -ArgumentList $LinuxHost, $ProjName, $LinuxBase, $AssignedPort

        $Jobs += @{
            Job = $Job
            ProjectName = $ProjName
            Port = $AssignedPort
        }

        Write-Host "✅ SSHジョブ開始: Job ID $($Job.Id)"
        Write-Host ""

        Start-Sleep -Milliseconds 500  # 起動間隔
    }

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "✅ すべてのプロジェクトを起動しました ($($SelectedProjects.Count)件)" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "起動中のプロジェクト:"
    foreach ($jobInfo in $Jobs) {
        Write-Host "  - $($jobInfo.ProjectName) (ポート: $($jobInfo.Port), Job ID: $($jobInfo.Job.Id))"
    }

    Write-Host "`nジョブ管理コマンド:"
    Write-Host "  Get-Job              : ジョブ一覧表示"
    Write-Host "  Receive-Job -Id X    : ジョブ出力確認"
    Write-Host "  Stop-Job -Id X       : ジョブ停止"
    Write-Host "  Remove-Job -Id X     : ジョブ削除"
    Write-Host ""
    Write-Host "Ctrl+C を押すとすべてのジョブを停止します..."
    Write-Host ""

    # ジョブ終了待機（Ctrl+Cでクリーンアップ）
    try {
        Wait-Job -Job ($Jobs | ForEach-Object { $_.Job }) -Timeout 86400  # 24時間
    } finally {
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
        Write-Host "🛑 すべてのジョブを停止中..." -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow

        $Jobs | ForEach-Object { Stop-Job -Job $_.Job -ErrorAction SilentlyContinue }
        $Jobs | ForEach-Object { Remove-Job -Job $_.Job -Force -ErrorAction SilentlyContinue }

        Write-Host "✅ ジョブクリーンアップ完了"
    }
} else {
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # 単一プロジェクト起動（従来の動作）
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "🚀 Claudeを起動します..."
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""

    # SSH接続してrun-claude.shを実行（-t でpseudo-ttyを割り当て）
    $EscapedProjectName = Escape-SSHArgument $ProjectName
    $EscapedLinuxBase = Escape-SSHArgument $LinuxBase
    ssh -t -o ControlMaster=no -o ControlPath=none -R "${DevToolsPort}:127.0.0.1:${DevToolsPort}" $LinuxHost "cd $EscapedLinuxBase/$EscapedProjectName && ./run-claude.sh"
}

# ===== ログ記録終了 =====
if ($LogPath) {
    try {
        Stop-Transcript
        Write-Host "`n📝 ログ記録終了: $LogPath" -ForegroundColor Gray
    } catch {
        # Transcript未開始の場合はエラーを無視
    }
}
