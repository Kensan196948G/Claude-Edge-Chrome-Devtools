# 移行ガイド: v1.3.0+ 統合スクリプトへの移行

## 概要

v1.3.0 から、新しい統合スクリプト `Claude-DevTools.ps1` が導入されました。
既存のブラウザ別スクリプトは **非推奨** となりますが、後方互換性のため引き続き利用可能です。

---

## 非推奨スクリプト一覧

| 旧スクリプト | 非推奨バージョン | 代替スクリプト |
|---|---|---|
| `scripts/main/Claude-EdgeDevTools.ps1` | v1.3.0 | `scripts/main/Claude-DevTools.ps1 -Browser edge` |
| `scripts/main/Claude-ChromeDevTools-Final.ps1` | v1.3.0 | `scripts/main/Claude-DevTools.ps1 -Browser chrome` |

---

## 移行手順

### ステップ1: start.bat を使う場合

`start.bat` メニューの選択番号を変更してください：

| 旧 | 新 |
|----|-----|
| `[1]` Edge DevTools Launch | `[U]` Unified DevTools Launch（Edge/Chrome 自動選択） |
| `[2]` Chrome DevTools Launch | `[U]` -Browser chrome オプション指定 |

### ステップ2: PowerShell から直接実行する場合

#### Edge → 統合スクリプト

```powershell
# 旧 (非推奨)
.\scripts\main\Claude-EdgeDevTools.ps1

# 新 (推奨)
.\scripts\main\Claude-DevTools.ps1 -Browser edge
```

#### Chrome → 統合スクリプト

```powershell
# 旧 (非推奨)
.\scripts\main\Claude-ChromeDevTools-Final.ps1

# 新 (推奨)
.\scripts\main\Claude-DevTools.ps1 -Browser chrome
```

### ステップ3: CI/CD スクリプトを更新する場合

非対話モードを使用:

```powershell
# 旧スクリプトには非対話モードなし（手動操作が必要だった）

# 新スクリプト: 完全非対話モード
.\scripts\main\Claude-DevTools.ps1 -Browser edge -Project "my-project" -NonInteractive
```

---

## 新機能一覧（Claude-DevTools.ps1）

### CLI 引数

| 引数 | 説明 | 例 |
|------|------|-----|
| `-Browser` | ブラウザ指定 (`edge`/`chrome`) | `-Browser edge` |
| `-Project` | プロジェクト名指定 | `-Project "my-app"` |
| `-Port` | DevToolsポート番号指定 | `-Port 9222` |
| `-NonInteractive` | 非対話モード（CI/CD用） | `-NonInteractive` |
| `-DryRun` | 実行内容プレビュー（変更なし） | `-DryRun` |
| `-Layout` | tmuxレイアウト指定 | `-Layout review-team` |

### モジュール化アーキテクチャ

`scripts/lib/` の7つの独立モジュールにより保守性が大幅に向上しました：

- `Config.psm1` — 設定読み込み・検証
- `PortManager.psm1` — ポート管理
- `BrowserManager.psm1` — ブラウザ起動・DevTools待機
- `SSHHelper.psm1` — SSH接続・引数エスケープ
- `UI.psm1` — 対話型UI
- `ScriptGenerator.psm1` — run-claude.sh生成・外部INIT_PROMPTテンプレート対応
- `ErrorHandler.psm1` — カテゴリ別エラーハンドリング

### 外部 INIT_PROMPT テンプレート (v1.4.0 新規)

INIT_PROMPT が `scripts/templates/init-prompt-ja.txt` に外部化されました。
カスタマイズが容易になりました。独自テンプレートを使うには:

```powershell
# config/config.json で initPromptFile を設定
{
  "initPromptFile": "scripts/templates/init-prompt-custom.txt"
}
```

または `New-RunClaudeScript` の `-InitPromptFile` パラメータで直接指定可能です。

---

## よくある質問

### Q: 既存スクリプトはいつ削除されますか？

A: v2.0.0 で削除予定です。十分な移行期間（少なくとも2マイナーバージョン）を設けます。

### Q: 機能的な差異はありますか？

A: 主要機能は同等です。統合スクリプトは以下の追加機能を提供します：
- CLI 引数による非対話モード
- DryRun モード
- モジュール化による拡張性

### Q: config.json の設定変更は必要ですか？

A: 不要です。既存の `config.json` をそのまま使用できます。

---

## サポート

問題が発生した場合は GitHub Issues に報告してください：
https://github.com/Kensan196948G/Claude-Edge-Chrome-Devtools/issues
