@echo off
setlocal enabledelayedexpansion

rem ============================================
rem Windows Terminal Setup Guide for Claude DevTools
rem ============================================

rem Check Windows Terminal settings path
set "WT_SETTINGS_PATH=%LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json"
set "WT_SETTINGS_PATH_OLD=%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

if exist "%WT_SETTINGS_PATH%" (
    echo [INFO] Windows Terminal settings found: %WT_SETTINGS_PATH%
) else if exist "%WT_SETTINGS_PATH_OLD%" (
    set "WT_SETTINGS_PATH=%WT_SETTINGS_PATH_OLD%"
    echo [INFO] Windows Terminal settings found: %WT_SETTINGS_PATH%
) else (
    echo [WARNING] Windows Terminal settings not found
    echo [INFO] Please install Windows Terminal and launch it once
)

echo.
echo ============================================
echo Windows Terminal Settings for Claude DevTools
echo ============================================
echo.
echo Recommended Settings:
echo   Font Size: 18px (easy to read)
echo   Font: Cascadia Code, Consolas, or MS Gothic
echo   Color Theme: One Half Light (Bright Theme)
echo   Background Opacity: 95%% (slightly transparent)
echo   Cursor Style: Bar (vertical line)
echo.
echo ============================================
echo Configuration Methods
echo ============================================
echo.
echo [Method 1: Manual Configuration]
echo 1. Open Windows Terminal
echo 2. Press Ctrl + Shift + , (comma) to open settings
echo 3. Add the following profile:
echo.
echo {
echo   "name": "Claude DevTools",
echo   "commandline": "powershell.exe",
echo   "font": {
echo     "face": "Cascadia Code",
echo     "size": 18,
echo     "weight": "normal"
echo   },
echo   "colorScheme": "One Half Light",
echo   "opacity": 95,
echo   "useAcrylic": true,
echo   "cursorShape": "bar",
echo   "padding": "8"
echo }
echo.
echo [Method 2: Auto-Setup Script]
echo Run PowerShell as Administrator and execute:
echo.
echo   .\setup-windows-terminal.ps1
echo.
echo ============================================
echo Useful Shortcut Keys
echo ============================================
echo.
echo Ctrl + +        : Increase font size
echo Ctrl + -        : Decrease font size
echo Ctrl + 0        : Reset font size
echo Ctrl + Shift + , : Open settings
echo Ctrl + Shift + p : Command palette
echo Alt + Enter     : Toggle fullscreen
echo.
echo ============================================

pause
