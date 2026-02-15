# Chrome DevTools Test Script
$ErrorActionPreference = "Continue"

$ChromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"

# ===== ポート自動選択 =====
$AvailablePorts = @(9222, 9223)

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
    exit 1
}
Write-Host "✅ 自動選択されたポート: $DevToolsPort"
$ChromeProfile = "C:\ChromeDevTools-$DevToolsPort"

Write-Host "Chrome DevTools Test Start"
Write-Host "=========================="

# Create profile directory
if (-not (Test-Path $ChromeProfile)) {
    New-Item -ItemType Directory -Path $ChromeProfile -Force | Out-Null
    Write-Host "Profile created: $ChromeProfile"
}

# Create Preferences directory
$PrefsDir = Join-Path $ChromeProfile "Default"
if (-not (Test-Path $PrefsDir)) {
    New-Item -ItemType Directory -Path $PrefsDir -Force | Out-Null
}

# Create DevTools Preferences
$PrefsJson = '{"devtools":{"preferences":{"cacheDisabled":"true","autoOpenDevToolsForPopups":"true","preserveConsoleLog":"true","consoleTimestampsEnabled":"true","network_log.preserve-log":"true"}}}'

$PrefsFile = Join-Path $PrefsDir "Preferences"
Set-Content -Path $PrefsFile -Value $PrefsJson -Encoding ASCII -NoNewline
Write-Host "DevTools settings applied"

# Launch Chrome
Write-Host "Launching Chrome DevTools (port=$DevToolsPort)..."

$chromeArgs = "--remote-debugging-port=$DevToolsPort --user-data-dir=`"$ChromeProfile`" --no-first-run --no-default-browser-check --remote-allow-origins=* --auto-open-devtools-for-tabs about:blank"

Start-Process -FilePath $ChromeExe -ArgumentList $chromeArgs

# Wait for startup
Write-Host "Waiting for startup..."
Start-Sleep -Seconds 5

# Connection test
$response = Invoke-RestMethod -Uri "http://localhost:$DevToolsPort/json/version" -TimeoutSec 5 -ErrorAction SilentlyContinue

if ($response) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "Chrome DevTools Connection SUCCESS!"
    Write-Host "=========================================="
    Write-Host "Browser: $($response.Browser)"
    Write-Host "Protocol: $($response.'Protocol-Version')"
    Write-Host "Port: $DevToolsPort"
    Write-Host "=========================================="
} else {
    Write-Host "Connection test FAILED"
}
