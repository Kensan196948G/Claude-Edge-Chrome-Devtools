# tmux + Agent Skills 統合設計書

**日付**: 2026-02-22
**アプローチ**: C（拡張版 — WezTerm対応含む）
**ステータス**: 承認済み

---

## 背景・目的

現在、`config.json` に `tmux` セクションが存在しないため、PS1スクリプト内のtmux統合コードが無効化されている。インフラ（scripts, layouts, pane monitors）は完成済みだが、設定の欠落によりすべての tmux 機能が動いていない。

本設計は以下の5要件に対応する：

1. Claude Code の tmux 機能を有効化する
2. tmux 未インストール時の自動インストール・確認を行う
3. `~/.claude/teams/` を自動検出してペイン数を動的調整する（`auto` モード）
4. start.bat のメニューから tmux ON/OFF を選択できるようにする
5. Agent Skills を INIT_PROMPT に組み込み、新規スキル 2 本を追加する

追加機能（アプローチ C）:

- WezTerm からの直接 SSH + tmux アタッチ起動（start.bat 項目 11）

---

## アーキテクチャ概要

```
Windows側 (start.bat)
  ├─ 1. Edge DevTools Setup
  │     └─ "tmux使いますか?(Y/N)" → -TmuxMode スイッチをPS1に渡す
  ├─ 2. Chrome DevTools Setup
  │     └─ "tmux使いますか?(Y/N)" → 同上
  └─ 11. WezTerm + tmux Launch ★新規
        └─ wezterm.exe でSSH + tmux attach を直接起動

Linux側 (run-claude.sh)
  ├─ tmuxインストール確認 → 自動インストール (既存: tmux-install.sh)
  ├─ tmux起動 → tmux-dashboard.sh (既存)
  │     └─ detect_layout() が ~/.claude/teams/ を自動検出
  └─ Claude Code起動 (既存)

.claude/skills/
  ├─ tmux-ops (既存)
  ├─ agent-teams-ops (既存)
  ├─ devops-monitor (既存)
  ├─ session-restore (★新規)
  └─ tmux-layout-sync (★新規)

config.json
  └─ tmux セクション追加 (★新規) ← 全tmux機能の有効化キー
```

---

## 変更ファイル一覧

| ファイル | 変更種別 | 内容 |
|---|---|---|
| `config/config.json` | 修正 | `tmux` セクション追加 |
| `start.bat` | 修正 | 1/2にY/N追加、11番新規追加 |
| `scripts/main/Claude-EdgeDevTools.ps1` | 修正 | `-TmuxMode` パラメータ追加、INIT_PROMPT スキル説明追加 |
| `scripts/main/Claude-ChromeDevTools-Final.ps1` | 修正 | 同上 |
| `.claude/skills/session-restore/SKILL.md` | 新規 | SSH切断後の復帰手順スキル |
| `.claude/skills/tmux-layout-sync/SKILL.md` | 新規 | Agent Teams↔tmuxレイアウト同期スキル |

---

## Section 2: config.json の tmux セクション

追加するJSONブロック:

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
}
```

設定値の意味:

- `enabled: true` — tmux機能を有効化（PS1スクリプトが参照）
- `autoInstall: true` — Linux側でtmux未インストール時に自動インストール
- `defaultLayout: "auto"` — `~/.claude/teams/` を自動検出してレイアウト決定
- `panes.*.enabled/refreshInterval` — 各モニターペインの有効/無効・更新間隔（秒）
- `theme` — tmuxのボーダーカラー・アクティブカラー設定

---

## Section 3: start.bat の変更

### 3-1: 項目1・2 に tmux Y/N プロンプト追加

`setlocal enabledelayedexpansion` を先頭に追加し（変数の遅延展開）、
項目1・2のハンドラに以下を追加：

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

### 3-2: execute_with_flags ラベル追加

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

### 3-3: メニュー表示に項目11追加

```
 [WezTerm]
 11. WezTerm + tmux Launch (SSH直接接続)
```

### 3-4: `launch_wezterm` サブルーチン追加

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
  "Write-Host \"Connecting to $h, session: $session\" -ForegroundColor Cyan; " ^
  "$wtExe = 'wezterm'; " ^
  "if (!(Get-Command $wtExe -ErrorAction SilentlyContinue)) { " ^
  "  $wtExe = Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe'; " ^
  "} " ^
  "Start-Process $wtExe -ArgumentList 'ssh', $h, '--', 'bash', '-c', " ^
  "  \"tmux attach-session -t $session 2>/dev/null || echo 'Session $session not found. Start with start.bat option 1 or 2 first.'; exec bash\""
echo.
pause
goto :eof
```

---

## Section 4: PS1スクリプト変更

### 4-1: param() ブロックへの `-TmuxMode` 追加

両スクリプト先頭の `param()` ブロックに追加：

```powershell
param(
    [switch]$TmuxMode = $false   # start.bat から渡されるtmuxフラグ
)
```

### 4-2: `$TmuxEnabled` 決定ロジックの変更

```powershell
# 変更前
$TmuxEnabled = if ($Config.tmux -and $Config.tmux.enabled) { "true" } else { "false" }

# 変更後
$TmuxEnabled = if ($TmuxMode -or ($Config.tmux -and $Config.tmux.enabled)) { "true" } else { "false" }
```

### 4-3: INIT_PROMPT へのスキル説明追加

run-claude.sh テンプレートの INIT_PROMPT セクションに以下を追加：

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

---

## Section 5: 新規スキル設計

### session-restore スキル

**ファイル**: `.claude/skills/session-restore/SKILL.md`

目的:
- SSH接続が切断された後のtmuxセッション復元
- 孤立プロセスのクリーンアップ
- 再接続後のDevTools接続確認

主要コマンド:
- `tmux list-sessions` → セッション一覧確認
- `tmux attach-session -t claude-{project}-{port}` → 再接続
- `curl http://127.0.0.1:PORT/json/version` → DevTools確認
- `pgrep -a -f "claude"` → 孤立プロセス確認
- `tmux kill-session -t SESSION` → セッション強制終了

### tmux-layout-sync スキル

**ファイル**: `.claude/skills/tmux-layout-sync/SKILL.md`

目的:
- TeamCreate / TeamDelete の実行後にtmuxレイアウトを再構成
- 新しいAgent Teamsに対応したペイン数に自動調整

主要手順:
1. 現在のセッション確認: `tmux list-sessions`
2. セッション停止: `tmux kill-session -t SESSION`
3. ダッシュボード再起動: `bash scripts/tmux/tmux-dashboard.sh PROJECT PORT auto "cd $(pwd) && ./run-claude.sh"`
4. 新レイアウト確認: `tmux list-panes -t SESSION`

---

## ベストプラクティスと追加推奨機能

### ベストプラクティス

1. **tmux セッション名の標準化**: `claude-{project}-{port}` パターン（既存）を維持
2. **SSH切断耐性**: tmux内でClaude Codeを実行することで、SSH切断後も処理継続
3. **デタッチ運用**: `Ctrl-b d` でデタッチ → 別端末から再アタッチ可能
4. **auto レイアウト**: `~/.claude/teams/` の変化を5秒ごとにモニタリング（agent-teams-monitor.sh）

### 追加推奨機能（将来拡張）

1. **tmux resurrect 対応** — システム再起動後のセッション自動復元
2. **per-project custom.conf** — プロジェクトルートの `scripts/tmux/layouts/custom.conf` を優先使用
3. **WezTerm multiplexer 統合** — WezTerm のネイティブ分割機能と tmux の併用設定
4. **通知連携** — Agent Teams タスク完了時に tmux visual-bell で通知

---

## 実装順序

1. `config/config.json` — tmux セクション追加（最も影響が小さく他の変更のベース）
2. `.claude/skills/session-restore/SKILL.md` — 新規スキル作成
3. `.claude/skills/tmux-layout-sync/SKILL.md` — 新規スキル作成
4. `scripts/main/Claude-EdgeDevTools.ps1` — param() + TmuxEnabled + INIT_PROMPT 変更
5. `scripts/main/Claude-ChromeDevTools-Final.ps1` — 同上
6. `start.bat` — Y/N プロンプト + WezTerm 項目追加
