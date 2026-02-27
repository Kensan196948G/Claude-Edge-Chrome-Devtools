# ============================================================
# BrowserManager.psm1 - ブラウザ管理モジュール
# Claude-EdgeChromeDevTools v1.3.0
# ============================================================

<#
.SYNOPSIS
    ブラウザをDevToolsモードで起動

.DESCRIPTION
    指定されたブラウザを専用プロファイルとリモートデバッグポートを有効にして起動する。
    起動されたプロセスオブジェクトを返す。

.PARAMETER BrowserExe
    ブラウザの実行ファイルパス

.PARAMETER BrowserName
    表示用ブラウザ名（例: "Edge", "Chrome"）

.PARAMETER BrowserProfile
    ブラウザプロファイルディレクトリのパス

.PARAMETER DevToolsPort
    リモートデバッグポート番号

.PARAMETER StartUrl
    起動時に開くURL（デフォルト: about:blank）

.EXAMPLE
    $proc = Start-DevToolsBrowser -BrowserExe "C:\...\msedge.exe" -BrowserName "Edge" `
                                   -BrowserProfile "C:\DevTools-edge-9222" -DevToolsPort 9222
#>
function Start-DevToolsBrowser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BrowserExe,

        [Parameter(Mandatory=$true)]
        [string]$BrowserName,

        [Parameter(Mandatory=$true)]
        [string]$BrowserProfile,

        [Parameter(Mandatory=$true)]
        [int]$DevToolsPort,

        [Parameter(Mandatory=$false)]
        [string]$StartUrl = "about:blank"
    )

    if (-not (Test-Path $BrowserExe)) {
        throw "ブラウザが見つかりません: $BrowserExe"
    }

    # プロファイルディレクトリ作成
    if (-not (Test-Path $BrowserProfile)) {
        New-Item -ItemType Directory -Path $BrowserProfile -Force | Out-Null
        Write-Host "📁 ブラウザプロファイル作成: $BrowserProfile" -ForegroundColor Cyan
    }

    $browserArgs = @(
        "--remote-debugging-port=$DevToolsPort",
        "--user-data-dir=$BrowserProfile",
        "--no-first-run",
        "--no-default-browser-check",
        "--remote-allow-origins=*",
        "--auto-open-devtools-for-tabs",
        "--disable-background-timer-throttling",
        "--disable-backgrounding-occluded-windows",
        "--disable-renderer-backgrounding",
        $StartUrl
    )

    try {
        Write-Host "🚀 $BrowserName 起動中 (ポート: $DevToolsPort)..." -ForegroundColor Cyan
        $process = Start-Process -FilePath $BrowserExe -ArgumentList $browserArgs -PassThru

        if ($null -eq $process) {
            throw "ブラウザプロセスの起動に失敗しました"
        }

        Write-Host "✅ $BrowserName 起動完了 (PID: $($process.Id))" -ForegroundColor Green
        return $process
    }
    catch {
        throw "ブラウザ起動中にエラーが発生しました: $_"
    }
}

<#
.SYNOPSIS
    ブラウザプロセスを安全に終了

.DESCRIPTION
    指定されたブラウザプロセスをグレースフルに終了する。
    タイムアウト後はKillを使用して強制終了する。

.PARAMETER Process
    終了するプロセスオブジェクト

.EXAMPLE
    Stop-DevToolsBrowser -Process $browserProcess
#>
function Stop-DevToolsBrowser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process]$Process
    )

    if ($null -eq $Process) {
        return
    }

    try {
        if ($Process.HasExited) {
            Write-Host "ℹ️  ブラウザは既に終了しています (PID: $($Process.Id))" -ForegroundColor DarkGray
            return
        }

        Write-Host "🛑 ブラウザを終了します (PID: $($Process.Id))..." -ForegroundColor Yellow

        # グレースフルシャットダウン
        $Process.CloseMainWindow() | Out-Null

        # 最大5秒待機
        if (-not $Process.WaitForExit(5000)) {
            Write-Warning "タイムアウト: ブラウザを強制終了します"
            $Process.Kill()
        }

        Write-Host "✅ ブラウザ終了完了" -ForegroundColor Green
    }
    catch {
        Write-Warning "ブラウザ終了中にエラーが発生しました: $_"
    }
}

<#
.SYNOPSIS
    DevToolsが応答するまで待機

.DESCRIPTION
    指定されたポートのDevToolsエンドポイントが応答するまで待機する。
    成功した場合はバージョン情報オブジェクトを返す。失敗時はnullを返す。

.PARAMETER Port
    DevToolsポート番号

.PARAMETER MaxWaitSeconds
    最大待機秒数（デフォルト: 15）

.EXAMPLE
    $version = Wait-DevToolsReady -Port 9222
    if ($version) { Write-Host "Browser: $($version.Browser)" }
#>
function Wait-DevToolsReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port,

        [Parameter(Mandatory=$false)]
        [int]$MaxWaitSeconds = 15
    )

    $url = "http://127.0.0.1:$Port/json/version"
    $elapsed = 0
    $interval = 1

    Write-Host "⏳ DevTools応答待機中 (ポート: $Port, 最大 ${MaxWaitSeconds}秒)..." -ForegroundColor Cyan

    while ($elapsed -lt $MaxWaitSeconds) {
        try {
            $response = Invoke-RestMethod -Uri $url -TimeoutSec 2 -ErrorAction Stop
            Write-Host "✅ DevTools応答確認 (${elapsed}秒後)" -ForegroundColor Green
            Write-Host "   ブラウザ: $($response.Browser)" -ForegroundColor DarkGray
            return $response
        }
        catch {
            # 接続失敗は想定内 - 待機中
        }

        Start-Sleep -Seconds $interval
        $elapsed += $interval

        if ($elapsed % 5 -eq 0) {
            Write-Host "   ... ${elapsed}秒経過" -ForegroundColor DarkGray
        }
    }

    Write-Warning "❌ DevToolsが ${MaxWaitSeconds}秒以内に応答しませんでした (ポート: $Port)"
    return $null
}

<#
.SYNOPSIS
    DevTools設定ファイルを生成（Edge用）

.DESCRIPTION
    Edge/Chrome用のDevTools最適化Preferences設定ファイルを生成する。
    キャッシュ無効化、ログ保持などのDevTools設定を含む。

.PARAMETER BrowserProfile
    ブラウザプロファイルディレクトリのパス

.EXAMPLE
    Set-BrowserDevToolsPreferences -BrowserProfile "C:\DevTools-edge-9222"
#>
function Set-BrowserDevToolsPreferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BrowserProfile
    )

    # プロファイルディレクトリ確認・作成
    if (-not (Test-Path $BrowserProfile)) {
        New-Item -ItemType Directory -Path $BrowserProfile -Force | Out-Null
    }

    # DefaultディレクトリにPreferencesを配置（Chromeプロファイル構造）
    $defaultDir = Join-Path $BrowserProfile "Default"
    if (-not (Test-Path $defaultDir)) {
        New-Item -ItemType Directory -Path $defaultDir -Force | Out-Null
    }

    $prefsPath = Join-Path $defaultDir "Preferences"

    # DevTools最適化設定
    $preferences = @{
        devtools = @{
            preferences = @{
                # ネットワークログを保持（ページ遷移後も）
                preserveLog           = "true"
                # キャッシュを無効化（DevTools起動時）
                cacheDisabled         = "true"
                # コンソールを保持
                consoleTimestampsEnabled = "true"
                # ソースマップを有効化
                sourceMapsEnabled     = "true"
                # パネルレイアウト
                currentDockState      = '"bottom"'
                # ネットワークパネルをデフォルト表示
                selectedPanel         = '"network"'
            }
        }
    }

    try {
        # 既存のPreferencesとマージ
        $existingPrefs = @{}
        if (Test-Path $prefsPath) {
            try {
                $existing = Get-Content -Path $prefsPath -Raw -Encoding UTF8
                $existingPrefs = $existing | ConvertFrom-Json -AsHashtable
            }
            catch {
                Write-Warning "既存のPreferencesの読み込みに失敗しました（新規作成）: $_"
            }
        }

        # devtoolsセクションをマージ
        if (-not $existingPrefs.ContainsKey('devtools')) {
            $existingPrefs['devtools'] = @{}
        }
        if (-not $existingPrefs['devtools'].ContainsKey('preferences')) {
            $existingPrefs['devtools']['preferences'] = @{}
        }

        foreach ($key in $preferences.devtools.preferences.Keys) {
            $existingPrefs['devtools']['preferences'][$key] = $preferences.devtools.preferences[$key]
        }

        $json = $existingPrefs | ConvertTo-Json -Depth 10
        Set-Content -Path $prefsPath -Value $json -Encoding UTF8
        Write-Host "⚙️  DevTools Preferences設定完了: $prefsPath" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "DevTools Preferences設定中にエラーが発生しました: $_"
    }
}

<#
.SYNOPSIS
    同ポートの既存ブラウザプロセスを終了

.DESCRIPTION
    指定されたブラウザタイプとポートに関連する既存プロセスを検索し終了する。
    プロファイルディレクトリを参照しているプロセスのみを対象とする。

.PARAMETER ProcessName
    プロセス名のパターン（例: "msedge", "chrome"）

.PARAMETER BrowserType
    ブラウザタイプ（"edge" または "chrome"）

.PARAMETER Port
    DevToolsポート番号

.EXAMPLE
    Remove-ExistingBrowserProfiles -ProcessName "msedge" -BrowserType "edge" -Port 9222
#>
function Remove-ExistingBrowserProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProcessName,

        [Parameter(Mandatory=$true)]
        [string]$BrowserType,

        [Parameter(Mandatory=$true)]
        [int]$Port
    )

    try {
        # ポートをリッスンしているプロセスを確認
        $listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($listening) {
            foreach ($conn in $listening) {
                $pid = $conn.OwningProcess
                $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($proc -and $proc.Name -match $ProcessName) {
                    Write-Host "🔄 既存ブラウザプロセス終了 (PID: $pid, ポート: $Port)..." -ForegroundColor Yellow
                    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                    Write-Host "✅ プロセス終了完了 (PID: $pid)" -ForegroundColor Green
                }
            }
        }

        # プロファイルディレクトリ名でプロセスを特定（フォールバック）
        $profilePattern = "DevTools-$BrowserType-$Port"
        $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($processes) {
            foreach ($proc in $processes) {
                try {
                    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
                    if ($cmdLine -match [regex]::Escape($profilePattern)) {
                        Write-Host "🔄 プロファイル一致プロセス終了 (PID: $($proc.Id))..." -ForegroundColor Yellow
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    # コマンドライン取得失敗は無視
                }
            }
        }

        # 終了完了まで少し待機
        Start-Sleep -Milliseconds 500
    }
    catch {
        Write-Warning "既存ブラウザプロセス終了中にエラーが発生しました: $_"
    }
}

# モジュールのエクスポート
Export-ModuleMember -Function @(
    'Start-DevToolsBrowser',
    'Stop-DevToolsBrowser',
    'Wait-DevToolsReady',
    'Set-BrowserDevToolsPreferences',
    'Remove-ExistingBrowserProfiles'
)
