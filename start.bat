@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem If running as admin and not in Windows Terminal, relaunch in Windows Terminal
rem set "isAdmin=0"
rem net session >nul 2>&1 && set "isAdmin=1"
rem if "%isAdmin%"=="1" if not defined WT_SESSION if exist "%LocalAppData%\Microsoft\WindowsApps\wt.exe" (
rem     "%LocalAppData%\Microsoft\WindowsApps\wt.exe" -p "Command Prompt" cmd /k ""%~f0""
rem     exit /b
rem )

:menu
cls
echo.
echo ===============================================
echo  PowerShell Script Launcher Menu
echo ===============================================
echo.
echo  [Claude DevTools Main]
echo  1. Claude Edge DevTools Setup
echo  2. Claude Chrome DevTools Setup
echo.
echo  [Test and Utility]
echo  3. Edge DevTools Connection Test
echo  4. Chrome DevTools Connection Test
echo.
echo  [Windows Terminal Settings]
echo  5. Windows Terminal Setup Guide
echo  6. Auto-Configure Windows Terminal (PowerShell)
echo.
echo  [Diagnostics]
echo  7. MCP Health Check
echo  8. Drive Mapping Diagnostic
echo.
echo  [Batch Operations]
echo  9. Launch Multiple Projects
echo.
echo  [tmux Dashboard]
echo  10. tmux Dashboard Setup / Diagnostics
echo.
echo  [WezTerm]
echo  11. WezTerm + tmux Launch (SSH直接接続)
echo.
echo  0. Exit
echo.
echo ===============================================
echo  Recommended: Use Windows Terminal for better display
echo ===============================================
echo.

set "fast_return=0"
set /p "choice=Enter the number of the script to run: "

if not defined choice (
    goto menu
)

if "%choice%"=="1" (
    set "script_name=scripts\main\Claude-EdgeDevTools.ps1"
    set "fast_return=1"
    echo.
    echo  tmux ダッシュボードを使用しますか? Y/N [Y]
    set /p "use_tmux="
    if /i "!use_tmux!"=="N" (
        set "tmux_flag="
    ) else (
        set "tmux_flag=-TmuxMode"
    )
    goto execute_with_flags
)
if "%choice%"=="2" (
    set "script_name=scripts\main\Claude-ChromeDevTools-Final.ps1"
    set "fast_return=1"
    echo.
    echo  tmux ダッシュボードを使用しますか? Y/N [Y]
    set /p "use_tmux="
    if /i "!use_tmux!"=="N" (
        set "tmux_flag="
    ) else (
        set "tmux_flag=-TmuxMode"
    )
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
if "%choice%"=="10" (
    call :tmux_dashboard
    goto menu
)
if "%choice%"=="11" (
    call :launch_wezterm
    goto menu
)
if "%choice%"=="0" (
    goto :eof
)

echo.
echo Invalid number. Please try again.
pause
goto menu


:execute_with_flags
cls
echo Running %script_name%...
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0%script_name%" %tmux_flag%
if %ERRORLEVEL% neq 0 (
    echo.
    echo Warning: An error occurred.
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
if %ERRORLEVEL% neq 0 (
    echo.
    echo Warning: An error occurred.
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
echo What is Windows Terminal?
echo  A modern terminal application for Windows 10/11.
echo  Provides better fonts, color themes, tabs, etc.
echo.
echo Recommended Settings:
echo  Font: Cascadia Code (Size: 14-16)
echo  Color Theme: One Half Dark or Campbell
echo  Background Opacity: 95%% (Acrylic effect)
echo  Cursor: Bar (vertical line)
echo.
echo Installation:
echo  1. Search "Windows Terminal" in Microsoft Store
echo  2. Or run: winget install Microsoft.WindowsTerminal
echo.
echo Useful Shortcuts:
echo  Ctrl + +        : Increase font size
echo  Ctrl + -        : Decrease font size
echo  Ctrl + 0        : Reset font size
echo  Ctrl + Shift + , : Open settings
echo  Alt + Enter     : Toggle fullscreen
echo.
echo Press any key to return to menu...
pause >nul
goto :eof


:setup_wt_auto
cls
echo.
echo ===============================================
echo  Windows Terminal Auto-Configuration
echo ===============================================
echo.
echo This will run a PowerShell script to create
echo an optimized profile for Claude DevTools.
echo.
echo Settings to be created:
echo  Profile Name: Claude DevTools
echo  Font: Cascadia Code (Size 18)
echo  Color Theme: One Half Light (Bright)
echo  Background Opacity: 95%%
echo  Cursor: Bar (white)
echo.
echo Execute? (Y/N)
set /p "confirm="

if /i "%confirm%"=="Y" (
    echo.
    echo Running PowerShell script...
    powershell -ExecutionPolicy Bypass -File "%~dp0scripts\setup\setup-windows-terminal.ps1"
    echo.
    if %ERRORLEVEL% neq 0 (
        echo Configuration failed. Please check the error above.
    ) else (
        echo Configuration completed.
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
===============================================
echo.
echo This will check the connection status of all
echo 8 MCP servers configured in your project.
echo.
echo Available MCP Servers:
echo  - brave-search
echo  - ChromeDevTools
echo  - context7
echo  - github
echo  - memory
echo  - playwright
echo  - sequential-thinking
echo  - plugin:claude-mem:mem-search
echo.
echo Project? (Enter project name or press Enter to skip)
set /p "project_name="

if defined project_name (
    echo.
    echo Running MCP health check for project: %project_name%...
    echo.
    pwsh -NoProfile -ExecutionPolicy Bypass -Command "ssh kensan1969 'cd /mnt/LinuxHDD/%project_name% && if [ -f scripts/health-check/mcp-health.sh ]; then bash scripts/health-check/mcp-health.sh; else echo \"Error: mcp-health.sh not found. Please run from the main Claude-EdgeChromeDevTools directory or ensure the project has the health check script.\"; fi' 2>&1"
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
echo  Drive Mapping Diagnostic
===============================================
echo.
echo This will diagnose X:\ drive accessibility
echo and show all available detection methods.
echo.
echo Press any key to run diagnostic...
pause >nul

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\test\test-drive-mapping.ps1"

echo.
pause
goto :eof


:launch_multiple
cls
echo.
echo ===============================================
echo  Launch Multiple Projects
===============================================
echo.
echo This will allow you to select and launch
echo multiple projects simultaneously with
echo dedicated browser profiles and ports.
echo.
echo How to select:
echo   Single project: 3
echo   Multiple projects: 1,3,5
echo   Range selection: 1-3
echo.
echo Press any key to continue...
pause >nul

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\main\Claude-ChromeDevTools-Final.ps1"

echo.
pause
goto :eof


:tmux_dashboard
cls
echo.
echo ===============================================
echo  tmux Dashboard Setup / Diagnostics
echo ===============================================
echo.
echo  1. Check tmux installation status (remote)
echo  2. Install/update tmux (remote)
echo  3. Test dashboard layout (remote)
echo  4. Show tmux configuration
echo.
echo  0. Return to main menu
echo.
echo ===============================================
set /p "tmux_choice=Enter number: "

if "%tmux_choice%"=="1" (
    call :tmux_check
    goto :tmux_dashboard
)
if "%tmux_choice%"=="2" (
    call :tmux_install
    goto :tmux_dashboard
)
if "%tmux_choice%"=="3" (
    call :tmux_layout_test
    goto :tmux_dashboard
)
if "%tmux_choice%"=="4" (
    call :tmux_show_config
    goto :tmux_dashboard
)
if "%tmux_choice%"=="0" (
    goto :eof
)
echo.
echo Invalid number.
pause
goto :tmux_dashboard


:tmux_check
cls
echo.
echo ===============================================
echo  tmux Installation Status
echo ===============================================
echo.
echo Checking remote Linux host...
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$host_name = $config.linuxHost; " ^
  "Write-Host \"Host: $host_name\" -ForegroundColor Cyan; " ^
  "ssh $host_name 'echo \"=== tmux version ===\"; tmux -V 2>/dev/null || echo \"tmux is NOT installed\"; echo \"\"; echo \"=== tmux sessions ===\"; tmux list-sessions 2>/dev/null || echo \"No active sessions\"; echo \"\"; echo \"=== tmux install path ===\"; which tmux 2>/dev/null || echo \"Not found in PATH\"'"

echo.
pause
goto :eof


:tmux_install
cls
echo.
echo ===============================================
echo  tmux Install / Update
echo ===============================================
echo.
echo This will install or update tmux on the
echo remote Linux host using the auto-install script.
echo.
echo Execute? (Y/N)
set /p "tmux_confirm="

if /i "%tmux_confirm%"=="Y" (
    echo.
    echo Running tmux-install.sh on remote host...
    echo.
    pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
      "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
      "$host_name = $config.linuxHost; " ^
      "$scriptPath = '%~dp0scripts\tmux\tmux-install.sh'; " ^
      "$content = Get-Content $scriptPath -Raw; " ^
      "$content = $content -replace \"`r`n\", \"`n\"; " ^
      "$encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content)); " ^
      "ssh $host_name \"echo '$encoded' | base64 -d > /tmp/tmux-install.sh && chmod +x /tmp/tmux-install.sh && /tmp/tmux-install.sh\""
    echo.
) else (
    echo.
    echo Cancelled.
)

pause
goto :eof


:tmux_layout_test
cls
echo.
echo ===============================================
echo  tmux Dashboard Layout Test
echo ===============================================
echo.
echo Available layouts:
echo  1. default       (2 side panes)
echo  2. review-team   (4 side panes, 2x2)
echo  3. fullstack-dev (6 side panes, 3x2)
echo  4. debug-team    (3 side panes)
echo.
set /p "layout_choice=Select layout (1-4): "

set "layout_name=default"
if "%layout_choice%"=="1" set "layout_name=default"
if "%layout_choice%"=="2" set "layout_name=review-team"
if "%layout_choice%"=="3" set "layout_name=fullstack-dev-team"
if "%layout_choice%"=="4" set "layout_name=debug-team"

echo.
echo Testing layout: %layout_name%
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$host_name = $config.linuxHost; " ^
  "Write-Host 'Layout file content:' -ForegroundColor Cyan; " ^
  "Get-Content '%~dp0scripts\tmux\layouts\%layout_name%.conf' | Write-Host"

echo.
pause
goto :eof


:tmux_show_config
cls
echo.
echo ===============================================
echo  tmux Configuration
echo ===============================================
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "if ($config.tmux) { " ^
  "  Write-Host 'tmux settings:' -ForegroundColor Cyan; " ^
  "  Write-Host \"  Enabled:      $($config.tmux.enabled)\"; " ^
  "  Write-Host \"  Auto Install: $($config.tmux.autoInstall)\"; " ^
  "  Write-Host \"  Layout:       $($config.tmux.defaultLayout)\"; " ^
  "  Write-Host ''; " ^
  "  Write-Host 'Pane settings:' -ForegroundColor Cyan; " ^
  "  $config.tmux.panes.PSObject.Properties | ForEach-Object { " ^
  "    Write-Host \"  $($_.Name): enabled=$($_.Value.enabled), interval=$($_.Value.refreshInterval)s\" " ^
  "  }; " ^
  "  Write-Host ''; " ^
  "  Write-Host 'Theme:' -ForegroundColor Cyan; " ^
  "  $config.tmux.theme.PSObject.Properties | ForEach-Object { " ^
  "    Write-Host \"  $($_.Name): $($_.Value)\" " ^
  "  } " ^
  "} else { " ^
  "  Write-Host 'tmux section not found in config.json' -ForegroundColor Yellow " ^
  "}"

echo.
pause
goto :eof


:launch_wezterm
cls
echo.
echo ===============================================
echo  WezTerm + tmux Launch
echo ===============================================
echo.
echo リモートホストに WezTerm で SSH 接続し、
echo tmux セッションに直接アタッチします。
echo.
echo プロジェクト名を入力してください:
set /p "wt_project="
if not defined wt_project (
    echo プロジェクト名が入力されていません。
    pause
    goto :eof
)
echo.
echo ポート番号 (デフォルト: 9222):
set /p "wt_port="
if not defined wt_port set "wt_port=9222"

echo.
echo 接続中...
pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$h = $config.linuxHost; " ^
  "$session = 'claude-!wt_project!-!wt_port!'; " ^
  "Write-Host \"Connecting to $h, session: $session\" -ForegroundColor Cyan; " ^
  "$wtExe = 'wezterm'; " ^
  "if (-not (Get-Command $wtExe -ErrorAction SilentlyContinue)) { " ^
  "  $wtExe = Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe'; " ^
  "} " ^
  "Start-Process $wtExe -ArgumentList 'ssh', $h, '--', 'bash', '-c', " ^
  "  \"tmux attach-session -t $session 2>/dev/null || echo 'Session $session not found. Start with start.bat option 1 or 2 first.'; exec bash\""
echo.
pause
goto :eof
