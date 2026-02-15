# Windows Terminal Auto-Configuration Script
# Creates optimized profile for Claude DevTools

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Windows Terminal Setup Tool" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Find Windows Terminal settings path
$wtPaths = @(
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
)

$settingsPath = $null
foreach ($path in $wtPaths) {
    if (Test-Path $path) {
        $settingsPath = $path
        break
    }
}

if (-not $settingsPath) {
    Write-Host "ERROR: Windows Terminal settings not found" -ForegroundColor Red
    Write-Host "`nPlease install Windows Terminal and launch it once.`n" -ForegroundColor Yellow
    Write-Host "Installation:" -ForegroundColor Cyan
    Write-Host "  Search 'Windows Terminal' in Microsoft Store" -ForegroundColor White
    Write-Host "  Or run: winget install Microsoft.WindowsTerminal" -ForegroundColor White
    exit 1
}

Write-Host "OK: Settings found: $settingsPath`n" -ForegroundColor Green

# Load settings
try {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
} catch {
    Write-Host "ERROR: Failed to load settings" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

# Define Claude DevTools profile
$claudeProfile = @{
    name = "Claude DevTools"
    guid = "{$([guid]::NewGuid().ToString())}"
    commandline = "powershell.exe -NoExit"
    startingDirectory = "%USERPROFILE%"
    icon = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
    font = @{
        face = "Cascadia Code"
        size = 18
        weight = "normal"
    }
    colorScheme = "One Half Light"
    opacity = 95
    useAcrylic = $true
    cursorShape = "bar"
    cursorColor = "#FFFFFF"
    padding = "8"
    antialiasingMode = "cleartype"
    closeOnExit = "graceful"
    historySize = 9001
    snapOnInput = $true
    altGrAliasing = $true
}

# Check existing profile
$existingProfile = $settings.profiles.list | Where-Object { $_.name -eq "Claude DevTools" }

if ($existingProfile) {
    Write-Host "WARNING: 'Claude DevTools' profile already exists" -ForegroundColor Yellow
    Write-Host "Overwrite? (Y/N): " -ForegroundColor Cyan -NoNewline
    $response = Read-Host
    
    if ($response -eq "Y" -or $response -eq "y") {
        $index = $settings.profiles.list.IndexOf($existingProfile)
        $settings.profiles.list[$index] = $claudeProfile
        Write-Host "OK: Profile updated`n" -ForegroundColor Green
    } else {
        Write-Host "Cancelled. Keeping existing settings.`n" -ForegroundColor Yellow
        exit 0
    }
} else {
    if (-not $settings.profiles.list) {
        $settings.profiles.list = @()
    }
    $settings.profiles.list += $claudeProfile
    Write-Host "OK: 'Claude DevTools' profile added`n" -ForegroundColor Green
}

# Add color scheme
if (-not $settings.schemes) {
    $settings.schemes = @()
}

# Add One Half Light color scheme (bright theme)
$oneHalfLight = $settings.schemes | Where-Object { $_.name -eq "One Half Light" }
if (-not $oneHalfLight) {
    $oneHalfLightScheme = @{
        name = "One Half Light"
        background = "#FAFAFA"
        foreground = "#383A42"
        cursorColor = "#528BFF"
        selectionBackground = "#4F525D"
        black = "#383A42"
        red = "#E45649"
        green = "#50A14F"
        yellow = "#C18401"
        blue = "#0184BC"
        purple = "#A626A4"
        cyan = "#0997B3"
        white = "#FAFAFA"
        brightBlack = "#4F525D"
        brightRed = "#E45649"
        brightGreen = "#50A14F"
        brightYellow = "#C18401"
        brightBlue = "#0184BC"
        brightPurple = "#A626A4"
        brightCyan = "#0997B3"
        brightWhite = "#FFFFFF"
    }
    $settings.schemes += $oneHalfLightScheme
    Write-Host "OK: 'One Half Light' color scheme added`n" -ForegroundColor Green
}

# Save settings
try {
    $settingsJson = $settings | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($settingsPath, $settingsJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host "OK: Settings saved: $settingsPath`n" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to save settings" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

# Completion message
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "[Settings]" -ForegroundColor Yellow
Write-Host "  Profile: Claude DevTools" -ForegroundColor White
Write-Host "  Font: Cascadia Code (Size: 14)" -ForegroundColor White
Write-Host "  Color: One Half Light (Bright Theme)" -ForegroundColor White
Write-Host "  Opacity: 95% (Acrylic)" -ForegroundColor White
Write-Host "  Cursor: Bar (White)" -ForegroundColor White
Write-Host "  Padding: 8px" -ForegroundColor White
Write-Host "  Antialiasing: ClearType`n" -ForegroundColor White

Write-Host "[Next Steps]" -ForegroundColor Yellow
Write-Host "  1. Open Windows Terminal" -ForegroundColor White
Write-Host "  2. Press Ctrl + Shift + Space to select profile" -ForegroundColor White
Write-Host "  3. Select 'Claude DevTools'" -ForegroundColor White
Write-Host "  Or: Select from tab dropdown`n" -ForegroundColor White

Write-Host "[Shortcuts]" -ForegroundColor Yellow
Write-Host "  Ctrl + +        : Increase font size" -ForegroundColor White
Write-Host "  Ctrl + -        : Decrease font size" -ForegroundColor White
Write-Host "  Ctrl + 0        : Reset font size" -ForegroundColor White
Write-Host "  Ctrl + Shift + , : Open settings" -ForegroundColor White
Write-Host "  Alt + Enter     : Toggle fullscreen`n" -ForegroundColor White

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Press Enter to exit" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Read-Host
