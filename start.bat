@echo off
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
echo  PowerShell スクリプト ランチャー
echo ===============================================
echo.
echo  [Claude DevTools メイン]
echo  1. Claude Edge DevTools セットアップ
echo  2. Claude Chrome DevTools セットアップ
echo.
echo  [テスト / ユーティリティ]
echo  3. Edge DevTools 接続テスト
echo  4. Chrome DevTools 接続テスト
echo.
echo  [Windows Terminal 設定]
echo  5. Windows Terminal セットアップ ガイド
echo  6. Windows Terminal 自動設定（PowerShell）
echo.
echo  [診断]
echo  7. MCP ヘルスチェック
echo  8. ドライブマッピング診断
echo.
echo  [一括操作]
echo  9. 複数プロジェクト同時起動
echo.
echo  [tmux ダッシュボード]
echo  10. tmux ダッシュボード セットアップ / 診断
echo.
echo  [WezTerm]
echo  11. WezTerm + tmux 起動（SSH 直接接続）
echo.
echo  0. 終了
echo.
echo ===============================================
echo  推奨: 文字化けを防ぐため Windows Terminal をご利用ください
echo ===============================================
echo.

set "fast_return=0"
set "choice="
set /p "choice=番号を入力してください: "

if not defined choice (
    goto menu
)

if "%choice%"=="1" (
    set "script_name=scripts\main\Claude-EdgeDevTools.ps1"
    set "fast_return=1"
    call :tmux_layout_select
    if "!tmux_back!"=="1" goto menu
    goto execute_with_flags
)
if "%choice%"=="2" (
    set "script_name=scripts\main\Claude-ChromeDevTools-Final.ps1"
    set "fast_return=1"
    call :tmux_layout_select
    if "!tmux_back!"=="1" goto menu
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
echo 無効な番号です。もう一度入力してください。
pause
goto menu


:execute_with_flags
cls
echo %script_name% を実行しています...
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0%script_name%" %tmux_flag%
if !ERRORLEVEL! neq 0 (
    echo.
    echo 警告: エラーが発生しました。
    pause
) else (
    echo.
    echo スクリプトが正常に完了しました。
)
if "%fast_return%"=="1" (
    goto menu
)
pause
goto menu


:execute
cls
echo %script_name% を実行しています...
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0%script_name%"
if !ERRORLEVEL! neq 0 (
    echo.
    echo 警告: エラーが発生しました。
    pause
) else (
    echo.
    echo スクリプトが正常に完了しました。
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
echo  Windows Terminal セットアップ ガイド
echo ===============================================
echo.
echo Windows Terminal とは？
echo  Windows 10/11 向けのモダンなターミナルアプリです。
echo  優れたフォント、カラーテーマ、タブ機能などを提供します。
echo.
echo 推奨設定:
echo  フォント: Cascadia Code（サイズ: 14-16）
echo  カラーテーマ: One Half Dark または Campbell
echo  背景の不透明度: 95%%（アクリル効果）
echo  カーソル: バー（縦棒）
echo.
echo インストール方法:
echo  1. Microsoft Store で "Windows Terminal" を検索
echo  2. または: winget install Microsoft.WindowsTerminal
echo.
echo 便利なショートカット:
echo  Ctrl + +          : フォントサイズを大きく
echo  Ctrl + -          : フォントサイズを小さく
echo  Ctrl + 0          : フォントサイズをリセット
echo  Ctrl + Shift + ,  : 設定を開く
echo  Alt + Enter       : フルスクリーン切替
echo.
echo 任意のキーを押してメニューへ戻ります...
pause >nul
goto :eof


:setup_wt_auto
cls
echo.
echo ===============================================
echo  Windows Terminal 自動設定
echo ===============================================
echo.
echo PowerShell スクリプトを実行して
echo Claude DevTools 向け最適化プロファイルを作成します。
echo.
echo 作成される設定:
echo  プロファイル名: Claude DevTools
echo  フォント: Cascadia Code（サイズ 18）
echo  カラーテーマ: One Half Light（明るい）
echo  背景の不透明度: 95%%
echo  カーソル: バー（白）
echo.
echo 実行しますか？ (Y=実行 / N=戻る)
set "confirm="
set /p "confirm="

if /i "%confirm%"=="Y" (
    echo.
    echo PowerShell スクリプトを実行しています...
    powershell -ExecutionPolicy Bypass -File "%~dp0scripts\setup\setup-windows-terminal.ps1"
    echo.
    if !ERRORLEVEL! neq 0 (
        echo 設定に失敗しました。上記のエラーを確認してください。
    ) else (
        echo 設定が完了しました。
    )
    pause
) else (
    echo.
    echo キャンセルしました。
    pause
)
goto :eof


:mcp_health_check
cls
echo.
echo ===============================================
echo  MCP ヘルスチェック
echo ===============================================
echo.
echo プロジェクトに設定されている 8 つの MCP サーバーの
echo 接続状態を確認します。
echo.
echo 対象 MCP サーバー:
echo  - brave-search
echo  - ChromeDevTools
echo  - context7
echo  - github
echo  - memory
echo  - playwright
echo  - sequential-thinking
echo  - plugin:claude-mem:mem-search
echo.
echo プロジェクト名を入力してください（スキップは Enter）:
set "project_name="
set /p "project_name="

if defined project_name (
    echo.
    echo プロジェクト: %project_name% の MCP ヘルスチェックを実行しています...
    echo.
    pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
      "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
      "$h = $config.linuxHost; " ^
      "ssh $h 'cd /mnt/LinuxHDD/%project_name% && if [ -f scripts/health-check/mcp-health.sh ]; then bash scripts/health-check/mcp-health.sh; else echo \"Error: mcp-health.sh not found.\"; fi' 2>&1"
    echo.
) else (
    echo.
    echo スキップしました。
)

pause
goto :eof


:drive_diagnostic
cls
echo.
echo ===============================================
echo  ドライブマッピング診断
echo ===============================================
echo.
echo X:\ ドライブのアクセス可能性を診断し、
echo 利用可能なすべての検出方法を表示します。
echo.
echo 任意のキーを押して診断を開始します...
pause >nul

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\test\test-drive-mapping.ps1"

echo.
pause
goto :eof


:launch_multiple
cls
echo.
echo ===============================================
echo  複数プロジェクト同時起動
echo ===============================================
echo.
echo 専用ブラウザプロファイルとポートを割り当てて
echo 複数のプロジェクトを同時に起動できます。
echo.
echo 選択方法:
echo   単一プロジェクト: 3
echo   複数プロジェクト: 1,3,5
echo   範囲指定:         1-3
echo.
echo 任意のキーを押して続行します...
pause >nul

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\main\Claude-ChromeDevTools-Final.ps1"

echo.
pause
goto :eof


:tmux_dashboard
cls
echo.
echo ===============================================
echo  tmux ダッシュボード セットアップ / 診断
echo ===============================================
echo.
echo  1. tmux インストール状態確認（リモート）
echo  2. tmux インストール / 更新（リモート）
echo  3. ダッシュボード レイアウトテスト
echo  4. tmux 設定を表示
echo.
echo  0. メインメニューへ戻る
echo.
echo ===============================================
set "tmux_choice="
set /p "tmux_choice=番号を入力してください: "

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
echo 無効な番号です。もう一度入力してください。
pause
goto :tmux_dashboard


:tmux_check
cls
echo.
echo ===============================================
echo  tmux インストール状態確認
echo ===============================================
echo.
echo リモート Linux ホストを確認しています...
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$host_name = $config.linuxHost; " ^
  "Write-Host \"ホスト: $host_name\" -ForegroundColor Cyan; " ^
  "ssh $host_name 'echo \"=== tmux バージョン ===\"; tmux -V 2>/dev/null || echo \"tmux はインストールされていません\"; echo \"\"; echo \"=== アクティブセッション ===\"; tmux list-sessions 2>/dev/null || echo \"アクティブなセッションはありません\"; echo \"\"; echo \"=== tmux インストールパス ===\"; which tmux 2>/dev/null || echo \"PATH に見つかりません\"'"

echo.
pause
goto :eof


:tmux_install
cls
echo.
echo ===============================================
echo  tmux インストール / 更新
echo ===============================================
echo.
echo リモート Linux ホストに tmux を
echo 自動インストールスクリプトでインストール／更新します。
echo.
echo 実行しますか？ (Y=実行 / N=戻る)
set "tmux_confirm="
set /p "tmux_confirm="

if /i not "%tmux_confirm%"=="Y" (
    echo.
    echo キャンセルしました。
    pause
    goto :eof
)

echo.
echo リモートホストで tmux-install.sh を実行しています...
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$host_name = $config.linuxHost; " ^
  "$scriptPath = '%~dp0scripts\tmux\tmux-install.sh'; " ^
  "$content = Get-Content $scriptPath -Raw; " ^
  "$content = $content -replace ""`r`n"", ""`n""; " ^
  "$encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content)); " ^
  "ssh $host_name ""echo '$encoded' | base64 -d > /tmp/tmux-install.sh && chmod +x /tmp/tmux-install.sh && /tmp/tmux-install.sh"""

echo.
pause
goto :eof


:tmux_layout_test
cls
echo.
echo ===============================================
echo  tmux ダッシュボード レイアウトテスト
echo ===============================================
echo.
echo 利用可能なレイアウト:
echo  1. default        （サイドペイン 2 枚）
echo  2. review-team    （サイドペイン 4 枚、2x2）
echo  3. fullstack-dev  （サイドペイン 6 枚、3x2）
echo  4. debug-team     （サイドペイン 3 枚）
echo  0. 戻る
echo.
set "layout_choice="
set /p "layout_choice=レイアウトを選択してください (0-4): "

if "!layout_choice!"=="0" goto :eof
if "!layout_choice!"=="" goto :eof

set "layout_name=default"
if "%layout_choice%"=="1" set "layout_name=default"
if "%layout_choice%"=="2" set "layout_name=review-team"
if "%layout_choice%"=="3" set "layout_name=fullstack-dev-team"
if "%layout_choice%"=="4" set "layout_name=debug-team"

echo.
echo レイアウト "%layout_name%" を確認しています...
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$host_name = $config.linuxHost; " ^
  "Write-Host 'レイアウトファイルの内容:' -ForegroundColor Cyan; " ^
  "Get-Content '%~dp0scripts\tmux\layouts\%layout_name%.conf' | Write-Host"

echo.
pause
goto :eof


:tmux_show_config
cls
echo.
echo ===============================================
echo  tmux 設定表示
echo ===============================================
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "if ($config.tmux) { " ^
  "  Write-Host 'tmux 設定:' -ForegroundColor Cyan; " ^
  "  Write-Host \"  有効:           $($config.tmux.enabled)\"; " ^
  "  Write-Host \"  自動インストール: $($config.tmux.autoInstall)\"; " ^
  "  Write-Host \"  レイアウト:     $($config.tmux.defaultLayout)\"; " ^
  "  Write-Host ''; " ^
  "  Write-Host 'ペイン設定:' -ForegroundColor Cyan; " ^
  "  $config.tmux.panes.PSObject.Properties | ForEach-Object { " ^
  "    Write-Host \"  $($_.Name): enabled=$($_.Value.enabled), interval=$($_.Value.refreshInterval)s\" " ^
  "  }; " ^
  "  Write-Host ''; " ^
  "  Write-Host 'テーマ:' -ForegroundColor Cyan; " ^
  "  $config.tmux.theme.PSObject.Properties | ForEach-Object { " ^
  "    Write-Host \"  $($_.Name): $($_.Value)\" " ^
  "  } " ^
  "} else { " ^
  "  Write-Host 'config.json に tmux セクションが見つかりません' -ForegroundColor Yellow " ^
  "}"

echo.
pause
goto :eof


:launch_wezterm
cls
echo.
echo ===============================================
echo  WezTerm + tmux 起動
echo ===============================================
echo.
echo リモートホストに WezTerm で SSH 接続し、
echo tmux セッションに直接アタッチします。
echo.
echo プロジェクト名を入力してください:
set "wt_project="
set /p "wt_project="
if not defined wt_project (
    echo プロジェクト名が入力されていません。
    pause
    goto :eof
)
echo.
echo ポート番号（デフォルト: 9222）:
set "wt_port="
set /p "wt_port="
if not defined wt_port set "wt_port=9222"

echo.
echo 接続しています...
pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$h = $config.linuxHost; " ^
  "$session = 'claude-!wt_project!-!wt_port!'; " ^
  "Write-Host \"接続先: $h  セッション: $session\" -ForegroundColor Cyan; " ^
  "$wtExe = 'wezterm'; " ^
  "if (-not (Get-Command $wtExe -ErrorAction SilentlyContinue)) { " ^
  "  $wtExe = Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe'; " ^
  "} " ^
  "Start-Process $wtExe -ArgumentList 'ssh', $h, '--', 'bash', '-c', " ^
  "  \"tmux attach-session -t $session 2>/dev/null || echo 'セッション $session が見つかりません。先に選択肢 1 か 2 で起動してください。'; exec bash\""
echo.
pause
goto :eof


:tmux_layout_select
echo.
echo -----------------------------------------------
echo  tmux レイアウトを選択してください
echo -----------------------------------------------
echo    0. なし（通常起動・tmux を使用しない）
echo    1. auto（Agent Teams 構成を自動検出）[デフォルト]
echo    2. default（2ペイン: Claude + モニタリング）
echo    3. review-team（4ペイン: レビューチーム）
echo    4. fullstack-dev-team（6ペイン: フルスタック開発チーム）
echo    5. debug-team（3ペイン: デバッグチーム）
echo    9. 戻る（メインメニューへ）
echo.
set "layout_choice="
set "tmux_flag="
set "tmux_back=0"
set /p "layout_choice=選択 [0-5, 9]（デフォルト: 1）: "
if "!layout_choice!"=="9" (
    set "tmux_back=1"
    goto :eof
)
if "!layout_choice!"=="0" (
    set "tmux_flag="
) else if "!layout_choice!"=="2" (
    set "tmux_flag=-TmuxMode -Layout default"
) else if "!layout_choice!"=="3" (
    set "tmux_flag=-TmuxMode -Layout review-team"
) else if "!layout_choice!"=="4" (
    set "tmux_flag=-TmuxMode -Layout fullstack-dev-team"
) else if "!layout_choice!"=="5" (
    set "tmux_flag=-TmuxMode -Layout debug-team"
) else (
    set "tmux_flag=-TmuxMode -Layout auto"
)
goto :eof
