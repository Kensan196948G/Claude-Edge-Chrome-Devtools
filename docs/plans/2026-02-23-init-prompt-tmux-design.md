# INIT_PROMPT テンプレート設計書

**作成日**: 2026-02-23
**目的**: 非tmux用プロンプト / tmux用プロンプト の使い分けガイドライン

---

## 1. 概要

このドキュメントは、Claude Code 起動時の INIT_PROMPT を tmux 環境向けと非tmux環境向けで使い分けるための設計指針を提供します。

---

## 2. 環境判定フロー

```
起動時の環境確認
├─ tmux セッション内で実行中？
│   ├─ YES → tmux用プロンプトを使用
│   │         （モニタリングペイン利用可能、セッション永続化あり）
│   │
│   └─ NO  → 非tmux用プロンプトを使用
│             （単一ターミナル、セッション永続化なし）
```

**判定コマンド**:
```bash
if [ -n "$TMUX" ]; then
    echo "tmux environment detected"
else
    echo "non-tmux environment"
fi
```

---

## 3. 非tmux用プロンプト (既存)

### 特徴

- 単一ターミナル環境を前提
- Claude Code セッションはSSH切断で消失
- すべての操作が1つの画面で完結
- シンプルで学習コストが低い

### 適用場面

- クイックな修正・確認作業
- 学習・検証フェーズ
- リソース制約のある環境
- CI/CDパイプライン内での実行

---

## 4. tmux用プロンプト (新規作成)

### 特徴

- マルチペイン環境を前提
- セッション永続化（SSH切断後も維持）
- リアルタイムモニタリングペイン利用可能
- Agent Teams との視覚的連携

### 追加要素

| 要素 | 説明 |
|------|------|
| **セッション管理** | tmux セッションのアタッチ/デタッチ手順 |
| **モニタリングペイン** | DevTools, MCP, Git, Resource のリアルタイム監視 |
| **レイアウトシステム** | default/review-team/fullstack-dev-team/debug-team |
| **Skills 連携** | tmux-ops, session-restore, tmux-layout-sync, devops-monitor |
| **SSH切断対応** | セッション復元手順の明示 |

### 適用場面

- 長時間の開発セッション
- Agent Teams を活用した並列作業
- 複数プロジェクトの同時進行
- DevTools/MCP の状態を常時監視したい場合

---

## 5. tmux用プロンプトのベストプラクティス

### 5.1 セッション永続性の活用

```
利点: SSH切断後も作業継続可能
活用: 長時間のビルド/テスト実行中にネットワーク切断されても問題なし
復元: tmux attach-session -t claude-{project}-{port}
```

### 5.2 モニタリングペインの活用

| ペイン | 更新間隔 | 活用方法 |
|--------|---------|---------|
| DevTools Monitor | 5秒 | ブラウザ接続状態のリアルタイム確認 |
| Agent Teams Monitor | 5秒 | チームメンバーの活動状況可視化 |
| MCP Health Monitor | 10秒 | MCP サーバーの健全性監視 |
| Git Status Monitor | 10秒 | 変更ファイル数・ブランチ状態 |
| Resource Monitor | 5秒 | CPU/メモリ/ディスク使用率 |

### 5.3 レイアウト使い分け

| レイアウト | ペイン数 | 推奨用途 |
|-----------|---------|---------|
| `default` | 2 | 個人作業、軽量タスク |
| `review-team` | 4 | コードレビュー（複数観点） |
| `fullstack-dev-team` | 6 | フルスタック開発（FE/BE並列） |
| `debug-team` | 3 | デバッグ・原因調査 |

### 5.4 Skills 活用フロー

```
タスク開始
├─ tmux-ops: レイアウト切替（必要に応じて）
├─ devops-monitor: 環境健全性確認
├─ agent-teams-ops: チーム作成（必要に応じて）
├─ [作業実行]
├─ tmux-layout-sync: レイアウト同期（Agent Teams 変更時）
└─ session-restore: SSH切断からの復旧（障害時）
```

---

## 6. 新テンプレート構成

### 6.1 テンプレートファイル

| ファイル | 用途 | 行数 |
|---------|------|------|
| `docs/templates/INIT_PROMPT_NON_TMUX_COMPLETE.md` | 単一セッション統治モード | 206行 |
| `docs/templates/INIT_PROMPT_TMUX_6PANE_COMPLETE.md` | 6ペイン固定構成モード | 175行 |

### 6.2 非tmux用プロンプトの特徴

- 🧠 **単一セッション統治モード**
- 絵文字による視覚的整理
- CI整合原則の明確化
- SubAgent / Agent Teams 運用指針
- ブラウザ自動化ツール選択ガイド
- タスク進行プロトコル（8ステップ）

### 6.3 tmux用プロンプトの特徴

- 🎛 **分散並列AI開発統治システム**
- 6ペイン固定構成（変更不可）
- 各ペインに明確な役割と責務

| ペイン | 役割 | 主責務 |
|--------|------|--------|
| Pane1 | @CTO (Lead) | 統治・設計・統合 |
| Pane2 | @DevAPI | バックエンド実装 |
| Pane3 | @DevUI | フロントエンド実装 |
| Pane4 | @QA | レビュー・設計整合 |
| Pane5 | @Tester | テスト設計・検証 |
| Pane6 | @CIManager | CI/CD整合・GitHub管理 |

---

## 7. 実装手順

### 7.1 PowerShell スクリプト更新

`scripts/main/Claude-EdgeDevTools.ps1` および `scripts/main/Claude-ChromeDevTools-Final.ps1` の以下の箇所を更新：

1. **INIT_PROMPT_TMUX** (Edge: lines 801-1228, Chrome: lines 943-1371)
   → `docs/templates/INIT_PROMPT_TMUX_6PANE_COMPLETE.md` の内容に置き換え

2. **INIT_PROMPT_NOTMUX** (Edge: lines 1234-1650, Chrome: lines 1377-1794)
   → `docs/templates/INIT_PROMPT_NON_TMUX_COMPLETE.md` の内容に置き換え

### 7.2 置換コマンド例

```powershell
# テンプレート読み込み
$TemplateNonTmux = Get-Content "docs\templates\INIT_PROMPT_NON_TMUX_COMPLETE.md" -Raw
$TemplateTmux = Get-Content "docs\templates\INIT_PROMPT_TMUX_6PANE_COMPLETE.md" -Raw

# heredoc形式に変換（先頭行を除去）
$ContentNonTmux = $TemplateNonTmux -replace '^#.*\n', ''
$ContentTmux = $TemplateTmux -replace '^#.*\n', ''
```

---

## 8. 比較表

| 項目 | 非tmux用 | tmux 6ペイン用 |
|------|---------|---------------|
| 統治レベル | 中（自律的） | 高（厳格分離） |
| セッション永続化 | なし | あり |
| Agent Teams spawn | 自由 | @CTOのみ |
| モニタリング | 手動確認 | 自動（ペイン） |
| レイアウト切替 | なし | 4種類 |
| 学習コスト | 低 | 中〜高 |
| 適用規模 | 小〜中規模 | 大規模・監査対応 |

---

## 9. 推奨運用

- **新規ユーザー**: 非 tmux 用から開始、慣れたら tmux 用へ移行
- **日常開発**: tmux 用を推奨（セッション永続化のメリット大）
- **CI/CD環境**: 非 tmux 用を使用（ヘッドレス実行）
- **監査対応プロジェクト**: tmux 6ペイン版を推奨（責務分離明確）

---

**最終更新**: 2026-02-23
