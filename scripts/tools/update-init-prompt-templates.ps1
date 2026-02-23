#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    INIT_PROMPT テンプレートを PowerShell スクリプトに適用するマイグレーションスクリプト

.DESCRIPTION
    docs/templates/ 内のテンプレートファイルを読み込み、
    scripts/main/ 内の PowerShell スクリプトの INIT_PROMPT セクションを更新します。

.PARAMETER DryRun
    実際に変更せず、変更内容をプレビューのみ表示

.PARAMETER ScriptPath
    更新対象のスクリプトパス (デフォルト: Edge版)

.EXAMPLE
    .\scripts\tools\update-init-prompt-templates.ps1 -DryRun
    変更内容をプレビュー

.EXAMPLE
    .\scripts\tools\update-init-prompt-templates.ps1
    Edge版を更新

.EXAMPLE
    .\scripts\tools\update-init-prompt-templates.ps1 -ScriptPath "scripts\main\Claude-ChromeDevTools-Final.ps1"
    Chrome版を更新
#>

param(
    [switch]$DryRun,
    [string]$ScriptPath = "scripts\main\Claude-EdgeDevTools.ps1"
)

$ErrorActionPreference = "Stop"

# テンプレートファイルパス
$TemplateDir = "docs\templates"
$TemplateNonTmux = Join-Path $TemplateDir "INIT_PROMPT_NON_TMUX_COMPLETE.md"
$TemplateTmux = Join-Path $TemplateDir "INIT_PROMPT_TMUX_6PANE_COMPLETE.md"

# テンプレート存在確認
if (-not (Test-Path $TemplateNonTmux)) {
    throw "テンプレートファイルが見つかりません: $TemplateNonTmux"
}
if (-not (Test-Path $TemplateTmux)) {
    throw "テンプレートファイルが見つかりません: $TemplateTmux"
}

# スクリプト存在確認
if (-not (Test-Path $ScriptPath)) {
    throw "スクリプトファイルが見つかりません: $ScriptPath"
}

Write-Host "📝 テンプレート読み込み中..." -ForegroundColor Cyan

# テンプレート読み込み（先頭のタイトル行を除去）
$NonTmuxLines = Get-Content $TemplateNonTmux -Encoding UTF8
$TmuxLines = Get-Content $TemplateTmux -Encoding UTF8

# 先頭のタイトル行（# で始まる最初の行）を除去
if ($NonTmuxLines[0] -match '^#') { $NonTmuxLines = $NonTmuxLines[1..($NonTmuxLines.Count-1)] }
if ($TmuxLines[0] -match '^#') { $TmuxLines = $TmuxLines[1..($TmuxLines.Count-1)] }

Write-Host "✅ テンプレート読み込み完了" -ForegroundColor Green
Write-Host "   - 非 tmux 用: $($NonTmuxLines.Count) 行" -ForegroundColor Gray
Write-Host "   - tmux 用: $($TmuxLines.Count) 行" -ForegroundColor Gray

# スクリプト読み込み
Write-Host "`n📄 スクリプト読み込み中: $ScriptPath" -ForegroundColor Cyan
$ScriptLines = Get-Content $ScriptPath -Encoding UTF8

# INIT_PROMPT セクションの範囲を特定
$TmuxStartMarker = "INIT_PROMPT_TMUX=`$(cat << 'INITPROMPTEOF_TMUX'"
$TmuxEndMarker = "INITPROMPTEOF_TMUX"
$NonTmuxStartMarker = "INIT_PROMPT_NOTMUX=`$(cat << 'INITPROMPTEOF_NOTMUX'"
$NonTmuxEndMarker = "INITPROMPTEOF_NOTMUX"

$TmuxStartLine = -1
$TmuxEndLine = -1
$NonTmuxStartLine = -1
$NonTmuxEndLine = -1

for ($i = 0; $i -lt $ScriptLines.Count; $i++) {
    if ($ScriptLines[$i] -match [regex]::Escape($TmuxStartMarker)) {
        $TmuxStartLine = $i
    }
    if ($TmuxStartLine -ge 0 -and $TmuxEndLine -lt 0 -and $ScriptLines[$i] -eq $TmuxEndMarker) {
        $TmuxEndLine = $i
    }
    if ($ScriptLines[$i] -match [regex]::Escape($NonTmuxStartMarker)) {
        $NonTmuxStartLine = $i
    }
    if ($NonTmuxStartLine -ge 0 -and $NonTmuxEndLine -lt 0 -and $ScriptLines[$i] -eq $NonTmuxEndMarker) {
        $NonTmuxEndLine = $i
    }
}

# 範囲確認
if ($TmuxStartLine -lt 0) { throw "INIT_PROMPT_TMUX 開始行が見つかりません" }
if ($TmuxEndLine -lt 0) { throw "INIT_PROMPT_TMUX 終了行が見つかりません" }
if ($NonTmuxStartLine -lt 0) { throw "INIT_PROMPT_NOTMUX 開始行が見つかりません" }
if ($NonTmuxEndLine -lt 0) { throw "INIT_PROMPT_NOTMUX 終了行が見つかりません" }

Write-Host "`n📍 セクション位置:" -ForegroundColor Cyan
Write-Host "   - INIT_PROMPT_TMUX: 行 $($TmuxStartLine+1) ～ $($TmuxEndLine+1) ($($TmuxEndLine - $TmuxStartLine - 1) 行)" -ForegroundColor Gray
Write-Host "   - INIT_PROMPT_NOTMUX: 行 $($NonTmuxStartLine+1) ～ $($NonTmuxEndLine+1) ($($NonTmuxEndLine - $NonTmuxStartLine - 1) 行)" -ForegroundColor Gray

# 新しいスクリプト内容を構築
$NewLines = [System.Collections.ArrayList]::new()

# TMUX セクションより前
for ($i = 0; $i -le $TmuxStartLine; $i++) {
    [void]$NewLines.Add($ScriptLines[$i])
}

# 新しい TMUX テンプレート
foreach ($line in $TmuxLines) {
    [void]$NewLines.Add($line)
}
[void]$NewLines.Add($TmuxEndMarker)

# TMUX 終了から NOTMUX 開始まで
for ($i = $TmuxEndLine + 1; $i -le $NonTmuxStartLine; $i++) {
    [void]$NewLines.Add($ScriptLines[$i])
}

# 新しい NOTMUX テンプレート
foreach ($line in $NonTmuxLines) {
    [void]$NewLines.Add($line)
}
[void]$NewLines.Add($NonTmuxEndMarker)

# NOTMUX 終了以降
for ($i = $NonTmuxEndLine + 1; $i -lt $ScriptLines.Count; $i++) {
    [void]$NewLines.Add($ScriptLines[$i])
}

# 変更統計
$OldLines = $ScriptLines.Count
$NewLineCount = $NewLines.Count
$Diff = $NewLineCount - $OldLines

Write-Host "`n📊 変更統計:" -ForegroundColor Cyan
Write-Host "   - 変更前行数: $OldLines" -ForegroundColor Gray
Write-Host "   - 変更後行数: $NewLineCount" -ForegroundColor Gray
$DiffSign = if ($Diff -ge 0) { "+" } else { "" }
Write-Host "   - 差分: $DiffSign$Diff 行" -ForegroundColor $(if ($Diff -lt 0) { "Green" } else { "Yellow" })

if ($DryRun) {
    Write-Host "`n🔍 [DRY RUN] 変更内容は保存されません" -ForegroundColor Yellow
    Write-Host "   実際に適用するには -DryRun を外して再実行してください" -ForegroundColor Gray
    
    # 変更箇所のプレビュー（最初の30行）
    Write-Host "`n📋 プレビュー (INIT_PROMPT_TMUX 開始部分):" -ForegroundColor Cyan
    $PreviewStart = $TmuxStartLine + 1
    $PreviewEnd = [Math]::Min($PreviewStart + 30, $NewLines.Count)
    for ($i = $PreviewStart; $i -lt $PreviewEnd; $i++) {
        Write-Host "$('{0,4}' -f ($i+1)): $($NewLines[$i])" -ForegroundColor Gray
    }
} else {
    # バックアップ作成
    $BackupPath = "$ScriptPath.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "`n💾 バックアップ作成中: $BackupPath" -ForegroundColor Cyan
    Copy-Item $ScriptPath $BackupPath
    
    # 変更を保存（UTF8 BOMなし）
    Write-Host "📝 変更を保存中: $ScriptPath" -ForegroundColor Cyan
    $Utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($ScriptPath, $NewLines, $Utf8NoBom)
    
    Write-Host "`n✅ 更新完了" -ForegroundColor Green
    Write-Host "   - バックアップ: $BackupPath" -ForegroundColor Gray
}

Write-Host "`n🏁 処理完了" -ForegroundColor Green
