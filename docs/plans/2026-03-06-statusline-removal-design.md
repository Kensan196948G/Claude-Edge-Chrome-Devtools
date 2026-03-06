# Statusline 完全削除 設計書

**日付:** 2026-03-06
**ステータス:** ユーザー承認済み（Approach A）

---

## 目的

このプロジェクト（Claude-EdgeChromeDevTools）から statusline に関わる
すべての設定・スクリプト・テスト・展開ロジックを完全削除する。

Linux側の既存グローバル設定（`~/.claude/settings.json`）への干渉を一切やめ、
Claude Code のグローバル設定管理を Linux 側に完全委任する。

---

## 承認済みアプローチ: Approach A（完全委任）

| 項目 | 内容 |
|------|------|
| statusline.sh | 削除（リポジトリから完全除去） |
| tests/test-statusline-v2.sh | 削除（リポジトリから完全除去） |
| config.json statusline セクション | 削除 |
| Claude-DevTools.ps1 statusline ロジック | 削除 |
| `~/.claude/settings.json` マージ処理 | 削除（`$globalScript` ブロック含む） |

**影響なし**: Linux 側既存の `~/.claude/settings.json` は変更しない。

---

## 削除対象ファイル

| ファイル | 種別 |
|--------|------|
| `scripts/statusline.sh` | **完全削除** |
| `tests/test-statusline-v2.sh` | **完全削除** |

---

## 変更対象ファイル

### 1. `config/config.json`

**削除箇所** (lines 12-20):
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

### 2. `scripts/main/Claude-DevTools.ps1`

**変更箇所 A** (line 300):
```
変更前: "  3. SSH バッチセットアップ (statusline/settings/MCP)"
変更後: "  3. SSH バッチセットアップ (MCP)"
```

**削除箇所 B** (lines 406-450): statusline 変数宣言・エンコード・`$globalScript` 生成ブロック全体
```powershell
# statusline.sh 読み込み
$StatuslineSource = ...
$statuslineEnabled = ...
$encodedStatusline = ""
$encodedSettings   = ""
$encodedGlobalScript = ""

if ($statuslineEnabled) {
    ...（$globalScript 生成含む）...
}
```

**削除箇所 C** (lines 492-506): SSHバッチ内のstatusline展開ブロック
```powershell
$(if ($statuslineEnabled -and $encodedStatusline) {
"echo '📝 statusline.sh 配置中...'
..."
} else { "echo 'ℹ️  Statusline 無効'" })
```
→ 行ごと削除（空行またはコメントを残さない）

**削除箇所 D** (lines 543-548): 完了メッセージブロック
```powershell
if ($statuslineEnabled) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" ...
    Write-Host "  Statusline 反映: ..."
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" ...
}
```

---

## 除外事項

- `claudeCode.env` / `claudeCode.settings` の config.json 設定は **保持**
  （これらは statusline が消えても有意義な設定）
- `ScriptGenerator.psm1` は変更不要（statusline 固有ロジックなし）
- `CLAUDE.md` の statusline 記述は更新推奨（別タスク）

---

## テスト方針

1. `scripts/statusline.sh` と `tests/test-statusline-v2.sh` の削除を確認
2. `config/config.json` に `statusline` キーが残っていないことを確認
3. `Claude-DevTools.ps1` に `statuslineEnabled`/`encodedStatusline`/`globalScript` 変数が残っていないことを確認
4. `Claude-DevTools.ps1` に `echo 'ℹ️  Statusline 無効'` の文字列が残っていないことを確認
5. 既存の Pester テスト (`tests/ScriptGenerator.Tests.ps1` 等) が引き続きパスすること
