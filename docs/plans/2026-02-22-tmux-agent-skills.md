# tmux + Agent Skills 統合 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `config.json` に tmux セクションを追加して全 tmux 機能を有効化し、start.bat に tmux ON/OFF 選択と WezTerm 直接起動を追加し、新規スキル 2 本を作成する。

**Architecture:** `config.json` の `tmux` セクション欠落が根本原因。PS1 スクリプト・bash スクリプト群は実装済みのため、設定追加とパラメータ追加・INIT_PROMPT 更新のみで全機能が有効化される。

**Tech Stack:** JSON (config), PowerShell (PS1), Batch (start.bat), Markdown (SKILL.md)

---

## Task 1: config/config.json — tmux セクション追加

**Files:**
- Modify: `config/config.json` (line 76, `"recentProjects"` ブロックの前に挿入)

**Step 1: ファイルを確認する**

```powershell
Get-Content config/config.json
```

Expected: 78行のJSON、`"recentProjects"` で終わり、`"tmux"` セクションが存在しないこと。

**Step 2: `"logging"` ブロックの前に `"tmux"` セクションを追加する**

`config/config.json` の line 57（`"logging"` 開始行）の直前、`"autoCleanup": true,` の後に以下を挿入する:

```json
  "tmux": {
    "enabled": true,
    "autoInstall": true,
    "defaultLayout": "auto",
    "panes": {
      "devtools": {
        "enabled": true,
        "refreshInterval": 5
      },
      "agentTeams": {
        "enabled": true,
        "refreshInterval": 5
      },
      "mcpHealth": {
        "enabled": true,
        "refreshInterval": 10
      },
      "gitStatus": {
        "enabled": true,
        "refreshInterval": 10
      },
      "resource": {
        "enabled": true,
        "refreshInterval": 5
      }
    },
    "theme": {
      "borderColor": "colour238",
      "activeColor": "colour75",
      "statusLeft": "Claude"
    }
  },
```

**Step 3: JSON 構文を確認する**

```powershell
Get-Content config/config.json -Raw | ConvertFrom-Json | Select-Object -ExpandProperty tmux
```

Expected:
```
enabled       : True
autoInstall   : True
defaultLayout : auto
panes         : @{devtools=...; agentTeams=...; mcpHealth=...; gitStatus=...; resource=...}
theme         : @{borderColor=colour238; activeColor=colour75; statusLeft=Claude}
```

**Step 4: コミットする**

```bash
git add config/config.json
git commit -m "feat: config.json に tmux セクションを追加して tmux 機能を有効化"
```

---

## Task 2: .claude/skills/session-restore/SKILL.md — 新規作成

**Files:**
- Create: `.claude/skills/session-restore/SKILL.md`

**Step 1: ディレクトリを作成して存在確認する**

```bash
mkdir -p .claude/skills/session-restore
ls .claude/skills/
```

Expected: `agent-teams-ops/`, `devops-monitor/`, `session-restore/`, `tmux-layout-sync/`（まだなし）, `tmux-ops/` が表示される。

**Step 2: SKILL.md を作成する**

以下の内容で `.claude/skills/session-restore/SKILL.md` を作成する:

```markdown
---
name: session-restore
description: SSH切断後のtmuxセッション復元手順。セッション一覧確認、再接続、孤立プロセスクリーンアップ、DevTools接続確認を行う。
---

# Session Restore — SSH切断後のtmuxセッション復元

## 目的

SSH接続が切断された後、実行中の tmux セッションと Claude Code を復元する。

## 手順

### 1. セッション一覧確認

```bash
tmux list-sessions
```

Expected: `claude-{project}-{port}: N windows (created ...)`

セッションが存在しない場合は、`run-claude.sh` から再起動が必要（手順5へ）。

### 2. セッションに再接続

```bash
tmux attach-session -t claude-{project}-{port}
```

- `{project}`: プロジェクト名（例: `my-app`）
- `{port}`: DevTools ポート番号（例: `9222`）

### 3. DevTools 接続確認

```bash
curl -sf http://127.0.0.1:${MCP_CHROME_DEBUG_PORT:-9222}/json/version | jq '.Browser'
```

Expected: `"Chromium/..."` または `"Microsoft Edge/..."` が返る。

接続失敗の場合、SSH ポートフォワードが切断されているため Windows 側で `start.bat` から再起動が必要。

### 4. 孤立プロセス確認とクリーンアップ

```bash
# 孤立した claude プロセスを確認
pgrep -a -f "claude"

# 孤立プロセスを強制終了（必要な場合のみ）
pkill -f "claude --dangerously-skip-permissions"

# セッション強制終了（再起動する場合）
tmux kill-session -t claude-{project}-{port}
```

### 5. セッション再起動（セッションが存在しない場合）

Windows 側から `start.bat` → 項目1または2 を選択して再起動する。

または Linux 側で直接起動:

```bash
cd /mnt/LinuxHDD/{project}
./run-claude.sh
```

## トラブルシューティング

| 症状 | 原因 | 対処 |
|------|------|------|
| `tmux: no server running` | tmux サーバー未起動 | `run-claude.sh` から再起動 |
| `no current client` | セッション名が違う | `tmux list-sessions` で名前確認 |
| DevTools DISCONNECTED | SSHトンネル切断 | `start.bat` から再接続 |
| `claude` プロセスがゾンビ | 異常終了 | `pkill -f claude` 後に再起動 |
```

**Step 3: ファイルの存在を確認する**

```bash
cat .claude/skills/session-restore/SKILL.md | head -5
```

Expected: `---`, `name: session-restore` が表示される。

**Step 4: コミットする**

```bash
git add .claude/skills/session-restore/SKILL.md
git commit -m "feat: session-restore スキルを新規追加（SSH切断後のtmuxセッション復元）"
```

---

## Task 3: .claude/skills/tmux-layout-sync/SKILL.md — 新規作成

**Files:**
- Create: `.claude/skills/tmux-layout-sync/SKILL.md`

**Step 1: ディレクトリを作成して存在確認する**

```bash
mkdir -p .claude/skills/tmux-layout-sync
ls .claude/skills/
```

Expected: `session-restore/` と `tmux-layout-sync/` が新たに追加されている。

**Step 2: SKILL.md を作成する**

以下の内容で `.claude/skills/tmux-layout-sync/SKILL.md` を作成する:

```markdown
---
name: tmux-layout-sync
description: TeamCreate/TeamDelete の実行後に tmux レイアウトを自動再構成する。Agent Teams のペイン数に合わせてダッシュボードを再起動する。
---

# tmux Layout Sync — Agent Teams ↔ tmux レイアウト同期

## 目的

`TeamCreate` または `TeamDelete` の実行後、`~/.claude/teams/` の変化に対応して tmux レイアウトを再構成する。

## 前提

- tmux セッション名: `claude-{project}-{port}`
- ダッシュボードスクリプト: `scripts/tmux/tmux-dashboard.sh`
- `auto` レイアウト: `~/.claude/teams/` のチーム数を自動検出

## 手順

### 1. 現在のセッション状態を確認する

```bash
# セッション一覧
tmux list-sessions

# 現在のペイン数
tmux list-panes -t claude-{project}-{port}
```

### 2. 現在のチーム数を確認する

```bash
ls ~/.claude/teams/ 2>/dev/null | wc -l
```

チーム数に応じた期待レイアウト:
- 0チーム → `default` (2ペイン)
- 1チーム → `review-team` (4ペイン)
- 2チーム → `fullstack-dev-team` (6ペイン)
- 3チーム以上 → `fullstack-dev-team` (6ペイン、最大)

### 3. セッションを停止して再起動する

```bash
# プロジェクト変数をセット
PROJECT=$(basename $(pwd))
PORT=${MCP_CHROME_DEBUG_PORT:-9222}

# セッション停止
tmux kill-session -t "claude-${PROJECT}-${PORT}"

# ダッシュボード再起動（auto レイアウトで自動検出）
bash scripts/tmux/tmux-dashboard.sh "${PROJECT}" "${PORT}" "auto" "cd $(pwd) && ./run-claude.sh"
```

### 4. 新しいレイアウトを確認する

```bash
# セッション確認
tmux list-sessions

# ペイン数確認
tmux list-panes -t "claude-${PROJECT}-${PORT}"
```

Expected: チーム数に応じたペイン数が表示される。

## 自動同期について

`tmux-dashboard.sh` の `agent-teams-monitor.sh` ペインは 5 秒ごとに `~/.claude/teams/` を監視している。ただし、レイアウト自体（ペイン数・分割）の変更は自動では行われないため、大幅なチーム数変化時は本スキルの手順3を手動実行すること。

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| セッション再起動後もペイン数が変わらない | `~/.claude/teams/` の内容を確認、`detect_layout()` のログを確認 |
| ダッシュボードスクリプトが見つからない | `ls scripts/tmux/` で確認、プロジェクトルートから実行しているか確認 |
```

**Step 3: ファイルの存在を確認する**

```bash
cat .claude/skills/tmux-layout-sync/SKILL.md | head -5
```

Expected: `---`, `name: tmux-layout-sync` が表示される。

**Step 4: コミットする**

```bash
git add .claude/skills/tmux-layout-sync/SKILL.md
git commit -m "feat: tmux-layout-sync スキルを新規追加（Agent Teams↔tmuxレイアウト同期）"
```

---

## Task 4: Claude-EdgeDevTools.ps1 — param() + TmuxEnabled + INIT_PROMPT 変更

**Files:**
- Modify: `scripts/main/Claude-EdgeDevTools.ps1`
  - 変更箇所1: line 7 前に `param()` ブロック追加
  - 変更箇所2: line 1360 の `$TmuxEnabled` 決定ロジック変更 (`param()` 追加後は +3行ずつずれることに注意)
  - 変更箇所3: `INITPROMPTEOF` の直前にスキル説明セクション追加

**Step 1: 変更前の状態を確認する**

```powershell
Get-Content scripts/main/Claude-EdgeDevTools.ps1 -TotalCount 10
```

Expected: `$ErrorActionPreference = "Stop"` が最初の実行行であること（`param()` がないこと）。

**Step 2: `param()` ブロックを先頭に追加する**

`scripts/main/Claude-EdgeDevTools.ps1` の `$ErrorActionPreference = "Stop"` の直前（line 7）に以下を挿入する:

```powershell
param(
    [switch]$TmuxMode = $false   # start.bat から渡される tmux フラグ
)

```

**Step 3: `$TmuxEnabled` 決定ロジックを変更する**

変更前（追加後のライン番号は +4 ずれるが、grep で特定すること）:

```powershell
$TmuxEnabled = if ($Config.tmux -and $Config.tmux.enabled) { "true" } else { "false" }
```

変更後:

```powershell
$TmuxEnabled = if ($TmuxMode -or ($Config.tmux -and $Config.tmux.enabled)) { "true" } else { "false" }
```

**Step 4: INIT_PROMPT にスキル説明セクションを追加する**

`INITPROMPTEOF` の直前（`* CI失敗は学習対象とせよ` の直後）に以下を挿入する:

```bash

## 利用可能な Agent Skills (.claude/skills/)

以下のスキルが利用可能です。`Skill` ツールまたは `/skill-name` で呼び出せます。

| スキル名 | 用途 |
|---------|------|
| `tmux-ops` | tmuxレイアウト切替・ペイン操作・セッション管理 |
| `agent-teams-ops` | Agent Teamsチーム作成・監視・シャットダウン |
| `devops-monitor` | DevTools/MCP診断・リソース確認・ネットワーク診断 |
| `session-restore` | SSH切断後のtmuxセッション復元手順 |
| `tmux-layout-sync` | Agent Teams起動/停止時のtmuxレイアウト同期 |
```

**Step 5: 変更を確認する**

```powershell
# param() ブロック確認
Get-Content scripts/main/Claude-EdgeDevTools.ps1 -TotalCount 8

# TmuxEnabled ロジック確認
Select-String -Path scripts/main/Claude-EdgeDevTools.ps1 -Pattern "TmuxEnabled"

# スキル説明セクション確認
Select-String -Path scripts/main/Claude-EdgeDevTools.ps1 -Pattern "session-restore"
```

Expected:
- `param(` が 1行目付近に存在する
- `$TmuxEnabled = if ($TmuxMode -or` が表示される
- `session-restore` が INIT_PROMPT 内で見つかる

**Step 6: コミットする**

```bash
git add scripts/main/Claude-EdgeDevTools.ps1
git commit -m "feat: Claude-EdgeDevTools.ps1 に -TmuxMode フラグと INIT_PROMPT スキル説明を追加"
```

---

## Task 5: Claude-ChromeDevTools-Final.ps1 — 同様の変更

**Files:**
- Modify: `scripts/main/Claude-ChromeDevTools-Final.ps1`
  - 変更箇所1: 既存 `param()` ブロック（line 7-35付近）に `-TmuxMode` パラメータ追加
  - 変更箇所2: line 1503 の `$TmuxEnabled` 決定ロジック変更
  - 変更箇所3: `INITPROMPTEOF` の直前にスキル説明セクション追加

**Step 1: 変更前の param() ブロックを確認する**

```powershell
Get-Content scripts/main/Claude-ChromeDevTools-Final.ps1 -TotalCount 40
```

Expected: `[CmdletBinding()]` と `param(` ブロックが存在し、`$Browser`, `$Project`, `$ProjectsInput`, `$Port` などのパラメータが定義されていること。

**Step 2: `param()` ブロックの末尾に `-TmuxMode` パラメータを追加する**

既存の `param()` ブロック内の最後のパラメータの後、`)` の前に以下を追加する:

```powershell

    [Parameter(Mandatory=$false)]
    [switch]$TmuxMode = $false           # start.bat から渡される tmux フラグ
```

**Step 3: `$TmuxEnabled` 決定ロジックを変更する**

変更前:

```powershell
$TmuxEnabled = if ($Config.tmux -and $Config.tmux.enabled) { "true" } else { "false" }
```

変更後:

```powershell
$TmuxEnabled = if ($TmuxMode -or ($Config.tmux -and $Config.tmux.enabled)) { "true" } else { "false" }
```

**Step 4: INIT_PROMPT にスキル説明セクションを追加する**

`INITPROMPTEOF` の直前（`* CI失敗は学習対象とせよ` の直後）に以下を挿入する（Task 4 と同一内容）:

```bash

## 利用可能な Agent Skills (.claude/skills/)

以下のスキルが利用可能です。`Skill` ツールまたは `/skill-name` で呼び出せます。

| スキル名 | 用途 |
|---------|------|
| `tmux-ops` | tmuxレイアウト切替・ペイン操作・セッション管理 |
| `agent-teams-ops` | Agent Teamsチーム作成・監視・シャットダウン |
| `devops-monitor` | DevTools/MCP診断・リソース確認・ネットワーク診断 |
| `session-restore` | SSH切断後のtmuxセッション復元手順 |
| `tmux-layout-sync` | Agent Teams起動/停止時のtmuxレイアウト同期 |
```

**Step 5: 変更を確認する**

```powershell
# TmuxMode パラメータ確認
Select-String -Path scripts/main/Claude-ChromeDevTools-Final.ps1 -Pattern "TmuxMode"

# TmuxEnabled ロジック確認
Select-String -Path scripts/main/Claude-ChromeDevTools-Final.ps1 -Pattern "TmuxEnabled"

# スキル説明セクション確認
Select-String -Path scripts/main/Claude-ChromeDevTools-Final.ps1 -Pattern "session-restore"
```

Expected: それぞれ 1件以上ヒット。

**Step 6: コミットする**

```bash
git add scripts/main/Claude-ChromeDevTools-Final.ps1
git commit -m "feat: Claude-ChromeDevTools-Final.ps1 に -TmuxMode フラグと INIT_PROMPT スキル説明を追加"
```

---

## Task 6: start.bat — Y/N プロンプト + WezTerm 項目追加

**Files:**
- Modify: `start.bat`
  - 変更箇所1: line 2 の `setlocal` を `setlocal enabledelayedexpansion` に変更
  - 変更箇所2: メニュー表示に `[WezTerm]` セクションと項目11を追加
  - 変更箇所3: 項目1・2のハンドラを `execute_with_flags` フロー向けに変更
  - 変更箇所4: `execute_with_flags` ラベルを追加
  - 変更箇所5: `choice == "11"` ハンドラを追加
  - 変更箇所6: `launch_wezterm` サブルーチンを追加

**Step 1: 変更前の状態を確認する**

```cmd
type start.bat | more
```

Expected: `setlocal` が 2行目、items 1-10 が定義済み、`:execute` ラベルが存在すること。

**Step 2: `setlocal` を `setlocal enabledelayedexpansion` に変更する**

変更前:
```batch
@echo off
setlocal
```

変更後:
```batch
@echo off
setlocal enabledelayedexpansion
```

**Step 3: メニュー表示に `[WezTerm]` セクションと項目11を追加する**

以下の行:
```batch
echo  [tmux Dashboard]
echo  10. tmux Dashboard Setup / Diagnostics
echo.
echo  0. Exit
```

を以下に変更する:
```batch
echo  [tmux Dashboard]
echo  10. tmux Dashboard Setup / Diagnostics
echo.
echo  [WezTerm]
echo  11. WezTerm + tmux Launch (SSH直接接続)
echo.
echo  0. Exit
```

**Step 4: 項目1のハンドラを tmux Y/N プロンプト付きに変更する**

変更前:
```batch
if "%choice%"=="1" (
    set "script_name=scripts\main\Claude-EdgeDevTools.ps1"
    set "fast_return=1"
    goto execute
)
```

変更後:
```batch
if "%choice%"=="1" (
    set "script_name=scripts\main\Claude-EdgeDevTools.ps1"
    set "fast_return=1"
    echo.
    echo  tmux ダッシュボードを使用しますか? (Y/N) [Y]
    set /p "use_tmux="
    if /i "!use_tmux!"=="N" (
        set "tmux_flag="
    ) else (
        set "tmux_flag=-TmuxMode"
    )
    goto execute_with_flags
)
```

**Step 5: 項目2のハンドラを同様に変更する**

変更前:
```batch
if "%choice%"=="2" (
    set "script_name=scripts\main\Claude-ChromeDevTools-Final.ps1"
    set "fast_return=1"
    goto execute
)
```

変更後:
```batch
if "%choice%"=="2" (
    set "script_name=scripts\main\Claude-ChromeDevTools-Final.ps1"
    set "fast_return=1"
    echo.
    echo  tmux ダッシュボードを使用しますか? (Y/N) [Y]
    set /p "use_tmux="
    if /i "!use_tmux!"=="N" (
        set "tmux_flag="
    ) else (
        set "tmux_flag=-TmuxMode"
    )
    goto execute_with_flags
)
```

**Step 6: 項目11のハンドラを追加する**

`if "%choice%"=="10" (` ブロックの後（`if "%choice%"=="0"` の前）に追加:

```batch
if "%choice%"=="11" (
    call :launch_wezterm
    goto menu
)
```

**Step 7: `:execute` ラベルの後に `:execute_with_flags` ラベルを追加する**

`:execute` ラベルとその実装は既存のまま残す。その前（または別の場所）に以下の `execute_with_flags` ラベルを追加する。

既存の `:execute` ラベルの前に以下を追加（`:execute` の直前の空行の位置）:

```batch
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

```

**Step 8: `:launch_wezterm` サブルーチンを追加する**

ファイル末尾（`:tmux_show_config` サブルーチンの後）に以下を追加:

```batch

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
  "$session = 'claude-' + '!wt_project!' + '-' + '!wt_port!'; " ^
  "Write-Host ""Connecting to $h, session: $session"" -ForegroundColor Cyan; " ^
  "$wtExe = 'wezterm'; " ^
  "if (!(Get-Command $wtExe -ErrorAction SilentlyContinue)) { " ^
  "  $wtExe = Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe'; " ^
  "} " ^
  "Start-Process $wtExe -ArgumentList 'ssh', $h, '--', 'bash', '-c', " ^
  "  ""tmux attach-session -t $session 2>/dev/null || echo 'Session $session not found. Start with start.bat option 1 or 2 first.'; exec bash"""
echo.
pause
goto :eof
```

**Step 9: 変更を確認する**

```cmd
findstr /n "enabledelayedexpansion\|execute_with_flags\|launch_wezterm\|WezTerm\|TmuxMode\|tmux_flag" start.bat
```

Expected: それぞれのキーワードが 1件以上ヒット。

**Step 10: コミットする**

```bash
git add start.bat
git commit -m "feat: start.bat に tmux Y/N プロンプトと WezTerm 直接起動（項目11）を追加"
```

---

## 最終確認

全タスク完了後、以下で全変更を確認する:

```bash
git log --oneline -6
```

Expected:
```
<hash> feat: start.bat に tmux Y/N プロンプトと WezTerm 直接起動（項目11）を追加
<hash> feat: Claude-ChromeDevTools-Final.ps1 に -TmuxMode フラグと INIT_PROMPT スキル説明を追加
<hash> feat: Claude-EdgeDevTools.ps1 に -TmuxMode フラグと INIT_PROMPT スキル説明を追加
<hash> feat: tmux-layout-sync スキルを新規追加（Agent Teams↔tmuxレイアウト同期）
<hash> feat: session-restore スキルを新規追加（SSH切断後のtmuxセッション復元）
<hash> feat: config.json に tmux セクションを追加して tmux 機能を有効化
```

```powershell
# config.json の tmux セクション確認
Get-Content config/config.json -Raw | ConvertFrom-Json | Select-Object -ExpandProperty tmux | ConvertTo-Json

# 新規スキル確認
Get-ChildItem .claude/skills/ -Directory | Select-Object Name

# PS1 スクリプトの TmuxMode 確認
Select-String -Path scripts/main/*.ps1 -Pattern "TmuxMode"
```
