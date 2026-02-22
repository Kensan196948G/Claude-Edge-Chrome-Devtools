# tmux Agent Teams 並列テスト設計書

**日付**: 2026-02-23
**アプローチ**: Option 2 — 複数プロジェクト並列検証（Agent Teams）
**ステータス**: 承認済み（ユーザー承認: 「その設計でOKです。承認します。」）

---

## 背景・目的

前セッション（コミット `c853774`）で `tmux-dashboard.sh` に以下の3機能を実装した：

1. **ペインボーダーラベル**（アイコン + 役割名）— `pane-border-status top` + `pane-border-format` + `select-pane -T`
2. **マウスリサイズ** — `mouse on` でペイン境界ドラッグリサイズ・クリック選択
3. **pane 0 識別** — `🤖 Claude Code [PROJECT_NAME]` タイトル設定

本設計は、これら3機能の Linux 実環境での動作確認を含む、**10カテゴリの包括的 Agent Teams tmux モードテスト検証**を行う。

---

## テスト対象プロジェクト（5件）

| # | プロジェクト名 | パス | サイズ |
|---|---|---|---|
| 1 | Linux-Management-Systm | `/mnt/LinuxHDD/Linux-Management-Systm` | 67MB |
| 2 | ITSM-ITManagementSystem | `/mnt/LinuxHDD/ITSM-ITManagementSystem` | 276KB |
| 3 | Enterprise-AI-HelpDesk-System | `/mnt/LinuxHDD/Enterprise-AI-HelpDesk-System` | 179MB |
| 4 | Mirai-IT-Knowledge-System | `/mnt/LinuxHDD/Mirai-IT-Knowledge-System` | 24MB |
| 5 | ITSM-System | `/mnt/LinuxHDD/ITSM-System` | 814MB |

**Linux ホスト**: `kensan@kensan1969`（実IP: `192.168.0.185`）
**tmux バージョン**: 3.4（全機能サポート確認済み）

---

## テスト 10カテゴリ

| Cat | 検証項目 | 合否判定基準 |
|-----|---------|------------|
| C1 | tmux セッション作成・管理 | `tmux list-sessions` でセッション確認 |
| C2 | ペインボーダーラベル（アイコン+役割名） | `tmux show-options -p pane-border-status` = top |
| C3 | マウスリサイズ設定 | `tmux show-options mouse` = on |
| C4 | pane 0 識別ラベル | `tmux display-message -p "#{pane_title}"` に 🤖 含む |
| C5 | レイアウト自動検出（auto mode） | `detect_layout()` が teams ディレクトリを正しく読む |
| C6 | モニタリングペイン起動 | 各スクリプトが exit せずに実行中 |
| C7 | ペインボーダーフォーマット条件分岐 | アクティブ/非アクティブで色が変わる |
| C8 | SSH切断耐性（セッション保持） | デタッチ後に `tmux attach` で復帰可能 |
| C9 | 環境変数伝播 | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` がセッション内で有効 |
| C10 | run-claude.sh との連携 | tmux-dashboard.sh が pane 0 で claude を起動する流れ確認 |

---

## アーキテクチャ設計

```
Orchestrator（本セッション: D:\Claude-EdgeChromeDevTools）
  │
  ├─ TeamCreate: "tmux-test-team"
  │
  ├─ Project Agent 1 (Linux-Management-Systm)
  │     └─ SSH kensan@kensan1969 → 10カテゴリ検証
  ├─ Project Agent 2 (ITSM-ITManagementSystem)
  │     └─ SSH kensan@kensan1969 → 10カテゴリ検証
  ├─ Project Agent 3 (Enterprise-AI-HelpDesk-System)
  │     └─ SSH kensan@kensan1969 → 10カテゴリ検証
  ├─ Project Agent 4 (Mirai-IT-Knowledge-System)
  │     └─ SSH kensan@kensan1969 → 10カテゴリ検証
  ├─ Project Agent 5 (ITSM-System)
  │     └─ SSH kensan@kensan1969 → 10カテゴリ検証
  │
  ├─ Repair Agent
  │     └─ 失敗カテゴリを分析 → tmux-dashboard.sh 修正 → commit
  │
  └─ Report Agent
        └─ 全結果集約 → テストレポート + プレイブック生成
```

### 結果集約方法

- Memory MCP: `entity: "tmux-test-results"` にプロジェクト別結果を記録
- 各 Project Agent がテスト完了後に Orchestrator へ SendMessage で報告

### 自動修復ループ

```
while (any FAIL) and (repair_count < 5):
    Repair Agent が失敗カテゴリを分析
    tmux-dashboard.sh を修正（Edit）
    git commit -m "fix: ..."
    全5プロジェクトで再テスト
    repair_count++
```

---

## 成果物

1. **テストレポート**: `docs/plans/2026-02-23-tmux-agent-teams-test-report.md`
   - プロジェクト×カテゴリのマトリクス（PASS/FAIL/SKIP）
   - 修復履歴（git diff ログ）

2. **運用プレイブック**: `docs/plans/2026-02-23-agent-teams-playbook.md`
   - Agent Teams + tmux の起動・監視・修復手順
   - トラブルシューティング FAQ

3. **修復コミット**: `git log` で確認可能な修復履歴

---

## 前提条件

- Linux ホスト `kensan@kensan1969` へ SSH 鍵認証で接続可能
- `/mnt/LinuxHDD/` に5プロジェクト存在確認済み
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` が `~/.claude/settings.json` に設定済み
- `skipDangerousModePermissionPrompt: true` で dangerously-skip-permissions 有効
- tmux 3.4 インストール済み
- claude-mem plugin 有効（`thedotmack`）

---

## 実装フロー → 実装計画ファイルへ

詳細実装計画: `docs/plans/2026-02-23-tmux-agent-teams-test.md`
