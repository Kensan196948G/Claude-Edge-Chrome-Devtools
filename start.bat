@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:menu
cls
echo.
echo ===============================================
echo  PowerShell Script Launcher
echo ===============================================
echo.
echo  [Claude DevTools Launch]
echo  U. Unified DevTools (Edge/Chrome) [v1.4.0 推奨]
echo  1. Claude Edge DevTools Launch [旧版]
echo  2. Claude Chrome DevTools Launch [旧版]
echo.
echo  [Test / Diagnostics]
echo  3. Edge DevTools Connection Test
echo  4. Chrome DevTools Connection Test
echo.
echo  [Windows Terminal Setup]
echo  5. Windows Terminal Setup Guide
echo  6. Windows Terminal Auto Setup
echo.
echo  [Diagnostics]
echo  7. MCP Health Check
echo  8. Drive Mapping Diagnostics
echo.
echo  [Parallel Execution]
echo  9. Multiple Project Launch
echo.
echo  0. Exit
echo.
echo ===============================================
echo  Tip: Recommended to use Windows Terminal
echo ===============================================
echo.

set "fast_return=0"
set "choice="
set /p "choice=Enter number: "

if not defined choice (
    goto menu
)

if /i "%choice%"=="U" (
    set "script_name=scripts\main\Claude-DevTools.ps1"
    set "fast_return=1"
    goto execute_with_flags
)
if "%choice%"=="1" (
    set "script_name=scripts\main\Claude-EdgeDevTools.ps1"
    set "fast_return=1"
    goto execute_with_flags
)
if "%choice%"=="2" (
    set "script_name=scripts\main\Claude-ChromeDevTools-Final.ps1"
    set "fast_return=1"
    goto execute_with_flags
)
if "%choice%"=="3" (
    set "script_name=scripts\test\test-edge.ps1"
    goto execute
)
if "%choice%"=="4" (
    set "script_name=scripts\test\test-chrome.ps1"
    goto execute
)
if "%choice%"=="5" (
    call :setup_wt_info
    goto menu
)
if "%choice%"=="6" (
    call :setup_wt_auto
    goto menu
)
if "%choice%"=="7" (
    call :mcp_health_check
    goto menu
)
if "%choice%"=="8" (
    call :drive_diagnostic
    goto menu
)
if "%choice%"=="9" (
    call :launch_multiple
    goto menu
)
if "%choice%"=="0" (
    goto :eof
)

echo.
echo Invalid number. Try again.
pause
goto menu


:execute_with_flags
cls
echo Running %script_name%...
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0%script_name%"
if !ERRORLEVEL! neq 0 (
    echo.
    echo Error: Script failed.
    pause
) else (
    echo.
    echo Script completed successfully.
)
if "%fast_return%"=="1" (
    goto menu
)
pause
goto menu


:execute
cls
echo Running %script_name%...
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0%script_name%"
if !ERRORLEVEL! neq 0 (
    echo.
    echo Error: Script failed.
    pause
) else (
    echo.
    echo Script completed successfully.
)
if "%fast_return%"=="1" (
    goto menu
)
pause
goto menu


:setup_wt_info
cls
echo.
echo ===============================================
echo  Windows Terminal Setup Guide
echo ===============================================
echo.
echo Windows Terminal is a modern terminal emulator
echo for Windows 10/11 with features like:
echo  - Multiple tabs
echo  - Unicode and UTF-8 support
echo  - Customizable themes and fonts
echo.
echo Recommended settings:
echo  Font: Cascadia Code (Size: 14-16)
echo  Color scheme: One Half Dark or Campbell
echo  Background opacity: 95%% (Acrylic)
echo  Cursor: Block (underline)
echo.
echo Installation:
echo  1. Microsoft Store: Search "Windows Terminal"
echo  2. Or: winget install Microsoft.WindowsTerminal
echo.
echo Useful shortcuts:
echo  Ctrl + +          : Increase font size
echo  Ctrl + -          : Decrease font size
echo  Ctrl + 0          : Reset font size
echo  Ctrl + Shift + ,  : Open settings
echo  Alt + Enter       : Toggle fullscreen
echo.
echo Press any key to return...
pause >nul
goto :eof


:setup_wt_auto
cls
echo.
echo ===============================================
echo  Windows Terminal Auto Setup
echo ===============================================
echo.
echo This will run a PowerShell script to create
echo a customized profile for Claude DevTools.
echo.
echo Settings to be applied:
echo  Profile name: Claude DevTools
echo  Font: Cascadia Code (Size 18)
echo  Color scheme: One Half Light
echo  Background opacity: 95%%
echo  Cursor: Bar (block)
echo.
echo Continue? (Y=Yes / N=No)
set "confirm="
set /p "confirm="

if /i "%confirm%"=="Y" (
    echo.
    echo Running PowerShell script...
    powershell -ExecutionPolicy Bypass -File "%~dp0scripts\setup\setup-windows-terminal.ps1"
    echo.
    if !ERRORLEVEL! neq 0 (
        echo Setup failed. Check the error above.
    ) else (
        echo Setup completed successfully.
    )
    pause
) else (
    echo.
    echo Cancelled.
    pause
)
goto :eof


:mcp_health_check
cls
echo.
echo ===============================================
echo  MCP Health Check
echo ===============================================
echo.
echo Checking MCP servers configured in the project...
echo.
echo Target MCP servers:
echo  - brave-search
echo  - ChromeDevTools
echo  - context7
echo  - github
echo  - memory
echo  - playwright
echo  - sequential-thinking
echo  - plugin:claude-mem:mem-search
echo.
echo Enter project name (or press Enter to skip):
set "project_name="
set /p "project_name="

if defined project_name (
    echo.
    echo Running MCP health check for project: %project_name%...
    echo.
    pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
      "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
      "$h = $config.linuxHost; " ^
      "ssh $h 'cd /mnt/LinuxHDD/%project_name% && if [ -f scripts/health-check/mcp-health.sh ]; then bash scripts/health-check/mcp-health.sh; else echo \"Error: mcp-health.sh not found.\"; fi' 2>&1"
    echo.
) else (
    echo.
    echo Skipped.
)

pause
goto :eof


:drive_diagnostic
cls
echo.
echo ===============================================
echo  Drive Mapping Diagnostics
echo ===============================================
echo.
echo Checking X:\ drive accessibility...
echo.
echo Running diagnostics...
pause >nul

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\test\test-drive-mapping.ps1"

echo.
pause
goto :eof


:launch_multiple
cls
echo.
echo ===============================================
echo  Multiple Project Launch
echo ===============================================
echo.
echo This will launch multiple projects in parallel
echo using Multi-Terminal and port assignments.
echo.
echo Selection method:
echo   Single project: 3
echo   Multiple projects: 1,3,5
echo   Range:           1-3
echo.
echo Press any key to continue...
pause >nul

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\main\Claude-ChromeDevTools-Final.ps1"

echo.
pause
goto :eof
