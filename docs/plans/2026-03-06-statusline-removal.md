# Statusline 完全削除 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** このプロジェクトから statusline に関わるすべてのファイル・設定・PowerShellコードを完全削除し、Linux側グローバル設定（`~/.claude/settings.json`）への干渉をゼロにする。

**Architecture:** 削除対象は「ファイル2本」「config.json 1セクション」「Claude-DevTools.ps1 の4箇所」の合計6アクション。削除後は `$statuslineEnabled` 変数・`$encodedStatusline` 変数・`$globalScript` 変数がコードから消え、SSH バッチスクリプトは MCP セットアップのみを行う。

**Tech Stack:** PowerShell 5.1+, bash, jq, Pester (テスト検証用)

---

### Task 1: ファイル削除 — statusline.sh と test-statusline-v2.sh

**Files:**
- Delete: `scripts/statusline.sh`
- Delete: `tests/test-statusline-v2.sh`

**Step 1: ファイルの存在を確認**

Git Bash または PowerShell で実行:
```bash
ls scripts/statusline.sh tests/test-statusline-v2.sh
```
Expected: 両ファイルが存在する

**Step 2: ファイルを削除**

```bash
git rm scripts/statusline.sh tests/test-statusline-v2.sh
```

**Step 3: 削除を確認**

```bash
ls scripts/statusline.sh 2>/dev/null && echo "EXISTS (ERROR)" || echo "DELETED OK"
ls tests/test-statusline-v2.sh 2>/dev/null && echo "EXISTS (ERROR)" || echo "DELETED OK"
```
Expected: 両方とも `DELETED OK`

**Step 4: git status 確認**

```bash
git status
```
Expected: `deleted: scripts/statusline.sh` と `deleted: tests/test-statusline-v2.sh` が表示される

**Step 5: Commit**

```bash
git commit -m "chore: remove statusline.sh and its tests"
```

---

### Task 2: config/config.json — statusline セクション削除

**Files:**
- Modify: `config/config.json:12-20`

**Step 1: 削除箇所の確認**

```bash
grep -n "statusline" config/config.json
```
Expected: 12行目付近に `"statusline": {` が見える

**Step 2: Edit ツールで statusline セクションを削除**

`config/config.json` の以下のブロックを削除する（カンマを含む7行）:

old_string:
```json
  "statusline": {
    "enabled": true,
    "showDirectory": true,
    "showGitBranch": true,
    "showModel": true,
    "showClaudeVersion": true,
    "showOutputStyle": true,
    "showContext": true
  },
```

new_string: `""` (空文字、つまり完全削除)

**Step 3: 削除後の確認**

```bash
grep -n "statusline" config/config.json
```
Expected: 出力なし（ゼロマッチ）

**Step 4: JSON 構文確認**

```bash
python3 -m json.tool config/config.json > /dev/null && echo "JSON OK" || echo "JSON ERROR"
```
または Git Bash では:
```bash
cat config/config.json | python3 -c "import sys,json; json.load(sys.stdin); print('JSON OK')"
```
Expected: `JSON OK`

**Step 5: Commit**

```bash
git add config/config.json
git commit -m "chore: remove statusline config section from config.json"
```

---

### Task 3: Claude-DevTools.ps1 — ステップ説明文の修正 (line 300)

**Files:**
- Modify: `scripts/main/Claude-DevTools.ps1:300`

**Step 1: 対象行を確認**

```bash
grep -n "statusline" scripts/main/Claude-DevTools.ps1 | head -5
```
Expected: `300:  Write-Host "  3. SSH バッチセットアップ (statusline/settings/MCP)"` が見える

**Step 2: Edit ツールで修正**

old_string:
```powershell
    Write-Host "  3. SSH バッチセットアップ (statusline/settings/MCP)"
```

new_string:
```powershell
    Write-Host "  3. SSH バッチセットアップ (MCP)"
```

**Step 3: 確認**

```bash
grep -n "statusline/settings/MCP" scripts/main/Claude-DevTools.ps1
```
Expected: 出力なし

---

### Task 4: Claude-DevTools.ps1 — statusline変数・エンコード・globalScript ブロック削除 (lines 406-450)

**Files:**
- Modify: `scripts/main/Claude-DevTools.ps1:406-450`

**Step 1: 削除範囲の確認**

```bash
grep -n "StatuslineSource\|statuslineEnabled\|encodedStatusline\|encodedSettings\|encodedGlobalScript\|globalScript\|statusline.sh" scripts/main/Claude-DevTools.ps1
```
Expected: 406行目付近から複数ヒット

**Step 2: Edit ツールで削除**

old_string（`# statusline.sh 読み込み` から閉じ括弧まで、空行含む）:
```powershell
# statusline.sh 読み込み
$StatuslineSource = Join-Path (Split-Path $PSScriptRoot -Parent) "statusline.sh"
$statuslineEnabled = $Config.statusline -and $Config.statusline.enabled -and (Test-Path $StatuslineSource)
$encodedStatusline = ""
$encodedSettings   = ""
$encodedGlobalScript = ""

if ($statuslineEnabled) {
    $statuslineContent = Get-Content $StatuslineSource -Raw
    $statuslineContent = $statuslineContent -replace "`r`n", "`n" -replace "`r", "`n"
    $encodedStatusline = ConvertTo-Base64Utf8 -Content $statuslineContent

    # settings.json 生成
    $settingsObj = @{
        statusLine = @{
            type    = "command"
            command = "$LinuxBase/$ProjectName/.claude/statusline.sh"
            padding = 0
        }
    }
    $settingsJson = $settingsObj | ConvertTo-Json -Depth 3 -Compress
    $encodedSettings = ConvertTo-Base64Utf8 -Content $settingsJson

    # グローバル設定更新スクリプト生成
    $jsonParts = Build-ClaudeCodeJsonFromConfig -ClaudeEnv $Config.claudeCode.env -ClaudeSettings $Config.claudeCode.settings
    $globalScript = @"
#!/bin/bash
SETTINGS_FILE="`$HOME/.claude/settings.json"
mkdir -p "`$HOME/.claude"

if [ -f "`$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
    jq '. + $($jsonParts.SettingsJson) + {
      "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}
    } | .env = ((.env // {}) + $($jsonParts.EnvJson))' "`$SETTINGS_FILE" > "`$SETTINGS_FILE.tmp" && mv "`$SETTINGS_FILE.tmp" "`$SETTINGS_FILE"
    echo "✅ グローバル設定をマージ更新しました"
else
    cat > "`$SETTINGS_FILE" << 'SETTINGSEOF'
$($jsonParts.FullJson)
SETTINGSEOF
    echo "✅ グローバル設定を新規作成しました"
fi
"@
    $globalScript = $globalScript -replace "`r`n", "`n" -replace "`r", "`n"
    $encodedGlobalScript = ConvertTo-Base64Utf8 -Content $globalScript
}

```

new_string: `""` (空文字、完全削除)

**Step 3: 変数残存確認**

```bash
grep -n "statuslineEnabled\|encodedStatusline\|encodedSettings\|encodedGlobalScript\|globalScript" scripts/main/Claude-DevTools.ps1
```
Expected: 出力なし（Task 4,5 完了後）

---

### Task 5: Claude-DevTools.ps1 — SSHバッチ内 statusline 展開ブロック削除 (lines 492-506)

**Files:**
- Modify: `scripts/main/Claude-DevTools.ps1:492-506`

**Step 1: 削除範囲の確認**

```bash
grep -n "statusline\|Statusline" scripts/main/Claude-DevTools.ps1
```
Expected: SSHバッチ内の `$(if ($statuslineEnabled` ブロックが見える

**Step 2: Edit ツールで削除**

old_string（PowerShellヒアストリング内の条件ブロック。前後の空行含む）:
```
$(if ($statuslineEnabled -and $encodedStatusline) {
"echo '📝 statusline.sh 配置中...'
echo '$encodedStatusline' | base64 -d > $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh
chmod +x $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh
cp $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh ~/.claude/statusline.sh

echo '⚙️  settings.json 配置中...'
echo '$encodedSettings' | base64 -d > $EscapedLinuxBase/$EscapedProjectName/.claude/settings.json

echo '🔄 グローバル設定更新中...'
echo '$encodedGlobalScript' | base64 -d > /tmp/update_global_settings.sh
chmod +x /tmp/update_global_settings.sh
/tmp/update_global_settings.sh
rm /tmp/update_global_settings.sh"
} else { "echo 'ℹ️  Statusline 無効'" })

```

new_string: `""` (空文字、完全削除)

**Step 3: 残存確認**

```bash
grep -n "statusline\|Statusline" scripts/main/Claude-DevTools.ps1
```
Expected: Task 6 (完了メッセージ) の行のみ残る状態

---

### Task 6: Claude-DevTools.ps1 — 完了メッセージブロック削除 (lines 543-548)

**Files:**
- Modify: `scripts/main/Claude-DevTools.ps1:543-548`

**Step 1: 削除範囲の確認**

```bash
grep -n "statuslineEnabled\|Statusline 反映" scripts/main/Claude-DevTools.ps1
```
Expected: `if ($statuslineEnabled)` ブロックが見える

**Step 2: Edit ツールで削除**

old_string:
```powershell
if ($statuslineEnabled) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  Statusline 反映: Claude Code で /statusline を実行" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

```

new_string: `""` (空文字、完全削除)

**Step 3: 完全クリーン確認**

```bash
grep -in "statusline" scripts/main/Claude-DevTools.ps1
```
Expected: **出力なし** (ゼロマッチ)

---

### Task 7: 検証 & 最終コミット

**Step 1: 全体クリーン確認**

```bash
grep -rn "statusline" scripts/ config/ tests/ 2>/dev/null
```
Expected: 出力なし（ゼロマッチ）

**Step 2: config.json JSON 構文確認**

```bash
python3 -c "import json; json.load(open('config/config.json')); print('JSON OK')"
```
Expected: `JSON OK`

**Step 3: PowerShell 構文確認 (Windows)**

```powershell
# Git Bash → PowerShell 経由
powershell.exe -Command "
\$ErrorActionPreference='Stop'
\$null = [System.Management.Automation.Language.Parser]::ParseFile(
    '\$PWD/scripts/main/Claude-DevTools.ps1',
    [ref]\$null,
    [ref]\$null
)
Write-Host 'PowerShell syntax OK'
"
```
Expected: `PowerShell syntax OK`

**Step 4: 既存 Pester テストが引き続きパスすること**

```powershell
powershell.exe -Command "
Invoke-Pester tests/ScriptGenerator.Tests.ps1 -Output Normal
"
```
Expected: `Tests Passed: N, Failed: 0, Skipped: 0`

**Step 5: git status 確認**

```bash
git status
git diff --stat HEAD
```
Expected: Task 1-6 の変更がすべて表示される（既にコミット済みのものはHEAD以降として表示されない）

**Step 6: 最終コミット（Tasks 3-6 分）**

```bash
git add scripts/main/Claude-DevTools.ps1
git commit -m "chore: remove statusline code from Claude-DevTools.ps1

- Remove statusline variable declarations and globalScript block
- Remove statusline SSH batch embedding block
- Remove statusline completion message block
- Fix step description to remove statusline reference"
```

**Step 7: プッシュ**

```bash
git log --oneline origin/main..HEAD
```
Expected: Task 1, Task 2, Task 7 の3コミットが表示される

```bash
git push origin main
```
