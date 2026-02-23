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
echo  PowerShell �X�N���v�g �����`���[
echo ===============================================
echo.
echo  [Claude DevTools ���C��]
echo  1. Claude Edge DevTools �Z�b�g�A�b�v
echo  2. Claude Chrome DevTools �Z�b�g�A�b�v
echo.
echo  [�e�X�g / ���[�e�B���e�B]
echo  3. Edge DevTools �ڑ��e�X�g
echo  4. Chrome DevTools �ڑ��e�X�g
echo.
echo  [Windows Terminal �ݒ�]
echo  5. Windows Terminal �Z�b�g�A�b�v �K�C�h
echo  6. Windows Terminal �����ݒ�iPowerShell�j
echo.
echo  [�f�f]
echo  7. MCP �w���X�`�F�b�N
echo  8. �h���C�u�}�b�s���O�f�f
echo.
echo  [�ꊇ����]
echo  9. �����v���W�F�N�g�����N��
echo.
echo  [tmux �_�b�V���{�[�h]
echo  10. tmux �_�b�V���{�[�h �Z�b�g�A�b�v / �f�f
echo.
echo  [WezTerm]
echo  11. WezTerm + tmux �N���iSSH ���ڐڑ��j
echo.
echo  0. �I��
echo.
echo ===============================================
echo  ����: ����������h������ Windows Terminal �������p��������
echo ===============================================
echo.

set "fast_return=0"
set "choice="
set /p "choice=�ԍ�����͂��Ă�������: "

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
echo �����Ȕԍ��ł��B������x���͂��Ă��������B
pause
goto menu


:execute_with_flags
cls
echo %script_name% �����s���Ă��܂�...
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0%script_name%" %tmux_flag%
if !ERRORLEVEL! neq 0 (
    echo.
    echo �x��: �G���[���������܂����B
    pause
) else (
    echo.
    echo �X�N���v�g������Ɋ������܂����B
)
if "%fast_return%"=="1" (
    goto menu
)
pause
goto menu


:execute
cls
echo %script_name% �����s���Ă��܂�...
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0%script_name%"
if !ERRORLEVEL! neq 0 (
    echo.
    echo �x��: �G���[���������܂����B
    pause
) else (
    echo.
    echo �X�N���v�g������Ɋ������܂����B
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
echo  Windows Terminal �Z�b�g�A�b�v �K�C�h
echo ===============================================
echo.
echo Windows Terminal �Ƃ́H
echo  Windows 10/11 �����̃��_���ȃ^�[�~�i���A�v���ł��B
echo  �D�ꂽ�t�H���g�A�J���[�e�[�}�A�^�u�@�\�Ȃǂ�񋟂��܂��B
echo.
echo �����ݒ�:
echo  �t�H���g: Cascadia Code�i�T�C�Y: 14-16�j
echo  �J���[�e�[�}: One Half Dark �܂��� Campbell
echo  �w�i�̕s�����x: 95%%�i�A�N�������ʁj
echo  �J�[�\��: �o�[�i�c�_�j
echo.
echo �C���X�g�[�����@:
echo  1. Microsoft Store �� "Windows Terminal" ������
echo  2. �܂���: winget install Microsoft.WindowsTerminal
echo.
echo �֗��ȃV���[�g�J�b�g:
echo  Ctrl + +          : �t�H���g�T�C�Y��傫��
echo  Ctrl + -          : �t�H���g�T�C�Y��������
echo  Ctrl + 0          : �t�H���g�T�C�Y�����Z�b�g
echo  Ctrl + Shift + ,  : �ݒ���J��
echo  Alt + Enter       : �t���X�N���[���ؑ�
echo.
echo �C�ӂ̃L�[�������ă��j���[�֖߂�܂�...
pause >nul
goto :eof


:setup_wt_auto
cls
echo.
echo ===============================================
echo  Windows Terminal �����ݒ�
echo ===============================================
echo.
echo PowerShell �X�N���v�g�����s����
echo Claude DevTools �����œK���v���t�@�C�����쐬���܂��B
echo.
echo �쐬�����ݒ�:
echo  �v���t�@�C����: Claude DevTools
echo  �t�H���g: Cascadia Code�i�T�C�Y 18�j
echo  �J���[�e�[�}: One Half Light�i���邢�j
echo  �w�i�̕s�����x: 95%%
echo  �J�[�\��: �o�[�i���j
echo.
echo ���s���܂����H (Y=���s / N=�߂�)
set "confirm="
set /p "confirm="

if /i "%confirm%"=="Y" (
    echo.
    echo PowerShell �X�N���v�g�����s���Ă��܂�...
    powershell -ExecutionPolicy Bypass -File "%~dp0scripts\setup\setup-windows-terminal.ps1"
    echo.
    if !ERRORLEVEL! neq 0 (
        echo �ݒ�Ɏ��s���܂����B��L�̃G���[���m�F���Ă��������B
    ) else (
        echo �ݒ肪�������܂����B
    )
    pause
) else (
    echo.
    echo �L�����Z�����܂����B
    pause
)
goto :eof


:mcp_health_check
cls
echo.
echo ===============================================
echo  MCP �w���X�`�F�b�N
echo ===============================================
echo.
echo �v���W�F�N�g�ɐݒ肳��Ă��� 8 �� MCP �T�[�o�[��
echo �ڑ���Ԃ��m�F���܂��B
echo.
echo �Ώ� MCP �T�[�o�[:
echo  - brave-search
echo  - ChromeDevTools
echo  - context7
echo  - github
echo  - memory
echo  - playwright
echo  - sequential-thinking
echo  - plugin:claude-mem:mem-search
echo.
echo �v���W�F�N�g������͂��Ă��������i�X�L�b�v�� Enter�j:
set "project_name="
set /p "project_name="

if defined project_name (
    echo.
    echo �v���W�F�N�g: %project_name% �� MCP �w���X�`�F�b�N�����s���Ă��܂�...
    echo.
    pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
      "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
      "$h = $config.linuxHost; " ^
      "ssh $h 'cd /mnt/LinuxHDD/%project_name% && if [ -f scripts/health-check/mcp-health.sh ]; then bash scripts/health-check/mcp-health.sh; else echo \"Error: mcp-health.sh not found.\"; fi' 2>&1"
    echo.
) else (
    echo.
    echo �X�L�b�v���܂����B
)

pause
goto :eof


:drive_diagnostic
cls
echo.
echo ===============================================
echo  �h���C�u�}�b�s���O�f�f
echo ===============================================
echo.
echo X:\ �h���C�u�̃A�N�Z�X�\����f�f���A
echo ���p�\�Ȃ��ׂĂ̌��o���@��\�����܂��B
echo.
echo �C�ӂ̃L�[�������Đf�f���J�n���܂�...
pause >nul

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\test\test-drive-mapping.ps1"

echo.
pause
goto :eof


:launch_multiple
cls
echo.
echo ===============================================
echo  �����v���W�F�N�g�����N��
echo ===============================================
echo.
echo ��p�u���E�U�v���t�@�C���ƃ|�[�g�����蓖�Ă�
echo �����̃v���W�F�N�g�𓯎��ɋN���ł��܂��B
echo.
echo �I����@:
echo   �P��v���W�F�N�g: 3
echo   �����v���W�F�N�g: 1,3,5
echo   �͈͎w��:         1-3
echo.
echo �C�ӂ̃L�[�������đ��s���܂�...
pause >nul

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\main\Claude-ChromeDevTools-Final.ps1"

echo.
pause
goto :eof


:tmux_dashboard
cls
echo.
echo ===============================================
echo  tmux �_�b�V���{�[�h �Z�b�g�A�b�v / �f�f
echo ===============================================
echo.
echo  1. tmux �C���X�g�[����Ԋm�F�i�����[�g�j
echo  2. tmux �C���X�g�[�� / �X�V�i�����[�g�j
echo  3. �_�b�V���{�[�h ���C�A�E�g�e�X�g
echo  4. tmux �ݒ��\��
echo.
echo  0. ���C�����j���[�֖߂�
echo.
echo ===============================================
set "tmux_choice="
set /p "tmux_choice=�ԍ�����͂��Ă�������: "

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
echo �����Ȕԍ��ł��B������x���͂��Ă��������B
pause
goto :tmux_dashboard


:tmux_check
cls
echo.
echo ===============================================
echo  tmux �C���X�g�[����Ԋm�F
echo ===============================================
echo.
echo �����[�g Linux �z�X�g���m�F���Ă��܂�...
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$host_name = $config.linuxHost; " ^
  "Write-Host \"�z�X�g: $host_name\" -ForegroundColor Cyan; " ^
  "ssh $host_name 'echo \"=== tmux �o�[�W���� ===\"; tmux -V 2>/dev/null || echo \"tmux �̓C���X�g�[������Ă��܂���\"; echo \"\"; echo \"=== �A�N�e�B�u�Z�b�V���� ===\"; tmux list-sessions 2>/dev/null || echo \"�A�N�e�B�u�ȃZ�b�V�����͂���܂���\"; echo \"\"; echo \"=== tmux �C���X�g�[���p�X ===\"; which tmux 2>/dev/null || echo \"PATH �Ɍ�����܂���\"'"

echo.
pause
goto :eof


:tmux_install
cls
echo.
echo ===============================================
echo  tmux �C���X�g�[�� / �X�V
echo ===============================================
echo.
echo �����[�g Linux �z�X�g�� tmux ��
echo �����C���X�g�[���X�N���v�g�ŃC���X�g�[���^�X�V���܂��B
echo.
echo ���s���܂����H (Y=���s / N=�߂�)
set "tmux_confirm="
set /p "tmux_confirm="

if /i not "%tmux_confirm%"=="Y" (
    echo.
    echo �L�����Z�����܂����B
    pause
    goto :eof
)

echo.
echo �����[�g�z�X�g�� tmux-install.sh �����s���Ă��܂�...
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
echo  tmux �_�b�V���{�[�h ���C�A�E�g�e�X�g
echo ===============================================
echo.
echo ���p�\�ȃ��C�A�E�g:
echo  1. default        �i�T�C�h�y�C�� 2 ���j
echo  2. review-team    �i�T�C�h�y�C�� 4 ���A2x2�j
echo  3. fullstack-dev  �i�T�C�h�y�C�� 6 ���A3x2�j
echo  4. debug-team     �i�T�C�h�y�C�� 3 ���j
echo  0. �߂�
echo.
set "layout_choice="
set /p "layout_choice=���C�A�E�g��I�����Ă������� (0-4): "

if "!layout_choice!"=="0" goto :eof
if "!layout_choice!"=="" goto :eof

set "layout_name=default"
if "%layout_choice%"=="1" set "layout_name=default"
if "%layout_choice%"=="2" set "layout_name=review-team"
if "%layout_choice%"=="3" set "layout_name=fullstack-dev-team"
if "%layout_choice%"=="4" set "layout_name=debug-team"

echo.
echo ���C�A�E�g "%layout_name%" ���m�F���Ă��܂�...
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$host_name = $config.linuxHost; " ^
  "Write-Host '���C�A�E�g�t�@�C���̓��e:' -ForegroundColor Cyan; " ^
  "Get-Content '%~dp0scripts\tmux\layouts\%layout_name%.conf' | Write-Host"

echo.
pause
goto :eof


:tmux_show_config
cls
echo.
echo ===============================================
echo  tmux �ݒ�\��
echo ===============================================
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "if ($config.tmux) { " ^
  "  Write-Host 'tmux �ݒ�:' -ForegroundColor Cyan; " ^
  "  Write-Host \"  �L��:           $($config.tmux.enabled)\"; " ^
  "  Write-Host \"  �����C���X�g�[��: $($config.tmux.autoInstall)\"; " ^
  "  Write-Host \"  ���C�A�E�g:     $($config.tmux.defaultLayout)\"; " ^
  "  Write-Host ''; " ^
  "  Write-Host '�y�C���ݒ�:' -ForegroundColor Cyan; " ^
  "  $config.tmux.panes.PSObject.Properties | ForEach-Object { " ^
  "    Write-Host \"  $($_.Name): enabled=$($_.Value.enabled), interval=$($_.Value.refreshInterval)s\" " ^
  "  }; " ^
  "  Write-Host ''; " ^
  "  Write-Host '�e�[�}:' -ForegroundColor Cyan; " ^
  "  $config.tmux.theme.PSObject.Properties | ForEach-Object { " ^
  "    Write-Host \"  $($_.Name): $($_.Value)\" " ^
  "  } " ^
  "} else { " ^
  "  Write-Host 'config.json �� tmux �Z�N�V������������܂���' -ForegroundColor Yellow " ^
  "}"

echo.
pause
goto :eof


:launch_wezterm
cls
echo.
echo ===============================================
echo  WezTerm + tmux �N��
echo ===============================================
echo.
echo �����[�g�z�X�g�� WezTerm �� SSH �ڑ����A
echo tmux �Z�b�V�����ɒ��ڃA�^�b�`���܂��B
echo.
echo �v���W�F�N�g������͂��Ă�������:
set "wt_project="
set /p "wt_project="
if not defined wt_project (
    echo �v���W�F�N�g�������͂���Ă��܂���B
    pause
    goto :eof
)
echo.
echo �|�[�g�ԍ��i�f�t�H���g: 9222�j:
set "wt_port="
set /p "wt_port="
if not defined wt_port set "wt_port=9222"

echo.
echo �ڑ����Ă��܂�...
pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
  "$config = Get-Content '%~dp0config\config.json' -Raw | ConvertFrom-Json; " ^
  "$h = $config.linuxHost; " ^
  "$session = 'claude-!wt_project!-!wt_port!'; " ^
  "Write-Host \"�ڑ���: $h  �Z�b�V����: $session\" -ForegroundColor Cyan; " ^
  "$wtExe = 'wezterm'; " ^
  "if (-not (Get-Command $wtExe -ErrorAction SilentlyContinue)) { " ^
  "  $wtExe = Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe'; " ^
  "} " ^
  "Start-Process $wtExe -ArgumentList 'ssh', $h, '--', 'bash', '-c', " ^
  "  \"tmux attach-session -t $session 2>/dev/null || echo '�Z�b�V���� $session ��������܂���B��ɑI���� 1 �� 2 �ŋN�����Ă��������B'; exec bash\""
echo.
pause
goto :eof


:tmux_layout_select
echo.
echo -----------------------------------------------
echo  tmux ���C�A�E�g��I�����Ă�������
echo -----------------------------------------------
echo    0. �Ȃ��i�ʏ�N���Etmux ���g�p���Ȃ��j
echo    1. auto�iAgent Teams �\�����������o�j[�f�t�H���g]
echo    2. default�i2�y�C��: Claude + ���j�^�����O�j
echo    3. review-team�i4�y�C��: ���r���[�`�[���j
echo    4. fullstack-dev-team�i6�y�C��: �t���X�^�b�N�J���`�[���j
echo    5. debug-team�i3�y�C��: �f�o�b�O�`�[���j
echo    9. �߂�i���C�����j���[�ցj
echo.
set "layout_choice="
set "tmux_flag="
set "tmux_back=0"
set /p "layout_choice=�I�� [0-5, 9]�i�f�t�H���g: 1�j: "
if "!layout_choice!"=="9" (
    set "tmux_back=1"
    goto :eof
)
if "!layout_choice!"=="0" (
    set "tmux_flag=-Layout none"
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
