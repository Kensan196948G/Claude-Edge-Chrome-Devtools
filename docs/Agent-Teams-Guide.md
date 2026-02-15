# Agent Teams 使い方ガイド

## 概要

Agent Teams は、複数の Claude Code インスタンスをチームとして協調動作させる機能です。独立したコンテキストを持つエージェントが並列で作業し、結果を統合することで、複雑なタスクを効率的に実行できます。

## 基本概念

### Team Lead（リード）
- 全体統括・タスク割り当て・結果統合を担当
- ユーザーと直接対話
- TeamCreate でチームを作成

### Teammate（チームメイト）
- 個別タスクを実行
- 独立したコンテキストウィンドウを持つ
- Task で起動・TaskUpdate でタスク割り当て

### Task List
- チーム全体で共有するタスク管理
- TaskCreate でタスク作成
- TaskUpdate でステータス更新（pending → in_progress → completed）

### Mailbox（メールボックス）
- チームメイト間のメッセージング
- SendMessage でメッセージ送信
- 発見事項・ブロッカー・完了報告に使用

## このプロジェクトで利用可能なテンプレート

### 1. マルチ観点レビューチーム（review-team.json）

**用途**: PR やコード変更を、セキュリティ・パフォーマンス・テストの3観点で並列レビュー

**チーム構成**:
- **security-reviewer**: コマンドインジェクション、機密情報漏洩、SSH セキュリティ
- **performance-reviewer**: SSH 接続回数、HTTP ポーリング、Base64 処理効率
- **test-reviewer**: テストカバレッジ、エッジケース、異常系テスト

**使用例**:

#### ステップ1: ユーザーが指示
```
ユーザー: 「このPRをレビューしてください」
```

#### ステップ2: Claude がチーム作成
```
Claude: "Agent Teams でマルチ観点レビューを実行します。"

TeamCreate(
  team_name="review-pr-123",
  description="PR #123 のセキュリティ・パフォーマンス・テスト観点レビュー"
)
```

#### ステップ3: チームメイト起動（並列）
```
# 3名のレビュアーを並列起動
Task(
  subagent_type="Explore",
  team_name="review-pr-123",
  name="security-reviewer",
  prompt="(review-team.json の initialPrompt を使用)"
)

Task(
  subagent_type="Explore",
  team_name="review-pr-123",
  name="performance-reviewer",
  prompt="(同上)"
)

Task(
  subagent_type="Explore",
  team_name="review-pr-123",
  name="test-reviewer",
  prompt="(同上)"
)
```

#### ステップ4: チームメイトが並列分析
```
security-reviewer   → コードスキャン → 発見事項を Memory MCP に保存 → リードに報告
performance-reviewer → ボトルネック分析 → 発見事項を Memory MCP に保存 → リードに報告
test-reviewer       → テストギャップ分析 → 発見事項を Memory MCP に保存 → リードに報告
```

#### ステップ5: リードが統合レポート作成
```
Claude（リード）:
「3名のレビュアーから報告を受け取りました。統合レポートを作成します。

【セキュリティ観点】
- 🔴 高: Escape-SSHArgument が変数 $BraveApiKey に適用されていない（L790）
- 🟡 中: config.json の githubToken が Base64 のみ（AES-256 推奨）

【パフォーマンス観点】
- 🟡 中: SSH 接続を2回実行（事前確認 + リモート実行）→ 1回に統合可能
- 🟢 低: Base64 エンコード処理は最適（改善不要）

【テストカバレッジ観点】
- 🔴 高: ポート競合時のテストが不足
- 🟡 中: UNC パスフォールバックのテストが不足

【推奨アクション】
1. 最優先: Escape-SSHArgument を $BraveApiKey に適用
2. 次: ポート競合テストを scripts/test/ に追加
3. 長期: SSH 接続プーリング実装
」
```

#### ステップ6: チーム shutdown
```
SendMessage(
  type="shutdown_request",
  recipient="security-reviewer",
  content="レビュー完了、お疲れ様でした"
)

# 同様に performance-reviewer, test-reviewer にも shutdown_request

TeamDelete()  # チーム削除
```

**期待される効果**:
- レビュー時間: 30分/観点 × 3観点 = 90分（逐次） → 10分/観点（並列） = **70% 削減**
- 網羅性: 単一レビュアーより多角的な視点で見落とし削減

---

### 2. フルスタック開発チーム（fullstack-dev-team.json）※Phase 2

**用途**: バックエンド・フロントエンド・テスト・インフラを並列開発

**チーム構成** (4名 + リード):
- backend-dev（feature/backend WorkTree）
- frontend-dev（feature/frontend WorkTree）
- test-dev（feature/tests WorkTree）
- infra-dev（feature/infra WorkTree）

**使用シーン**: 新機能の大規模実装時に各レイヤーを並列開発

---

### 3. バグ調査チーム（debug-team.json）※Phase 2

**用途**: 複数仮説を並列検証してバグの根本原因を特定

**チーム構成** (3名):
- hypothesis-1-investigator（仮説A検証）
- hypothesis-2-investigator（仮説B検証）
- hypothesis-3-investigator（仮説C検証）

**使用シーン**: 原因不明のバグ調査時に複数の可能性を同時検証

---

## Agent Teams 運用ルール（INIT_PROMPT より）

### 使うべき場面

✅ **リサーチ・レビュー系**: 複数観点の同時分析
✅ **新規モジュール開発**: 独立したレイヤーの並列開発
✅ **デバッグ・原因調査**: 複数仮説の並列検証
✅ **クロスレイヤー協調**: API・DB・UI 設計の相互影響確認

### 使わない場面

❌ **単純な定型タスク**: lint 修正、フォーマット適用
❌ **順序依存の強い逐次作業**
❌ **トークンコスト抑制が必要なルーチン作業**

### チーム編成の流れ

1. **提案**: チーム構成（役割・人数・タスク分担）を提案 → ユーザー承認
2. **spawn**: TeamCreate + Task で各メンバーを起動
3. **作業**: 各メンバーは独立した WorkTree/ブランチで作業
4. **報告**: 発見事項・ブロッカー・完了報告を SendMessage で送信
5. **統合**: リードが結果を統合・コンフリクト解決
6. **shutdown**: リードが全メンバーに shutdown_request → TeamDelete

### コミュニケーション方針

- チームメイト間は「発見事項・ブロッカー・完了報告」に限定
- 設計判断が必要な場合はリード（メインエージェント）に escalate
- Git commit/push は確認を求めてから実行（CLAUDE.md ルール遵守）

## Memory MCP との統合

Agent Teams と Memory MCP を組み合わせることで、チーム内の知識共有が可能です。

### 発見事項の保存

```bash
# security-reviewer が発見事項を Memory MCP に保存
mcp__memory__save \
  --key "security-findings" \
  --value '{"issue": "SSH引数エスケープ漏れ", "location": "L790", "severity": "high"}'
```

### 他のメンバーが参照

```bash
# performance-reviewer が security-reviewer の発見事項を参照
mcp__memory__get --key "security-findings"
```

### リードが統合

```bash
# リードが全メンバーの発見事項を統合
mcp__memory__list --prefix "findings-"
```

## トラブルシューティング

### Agent Teams が起動しない

**原因**: 環境変数 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` が設定されていない

**確認方法**:
```bash
echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
# "1" と表示されるべき
```

**解決策**: `config.json` の `claudeCode.env` セクションを確認し、設定を追加

---

### チームメイトが応答しない

**原因**: Task の prompt が不明瞭、または agentType が不適切

**解決策**:
- prompt を具体的に記述（調査対象・重点項目・出力形式を明記）
- agentType を適切に選択（Explore = リサーチ, general = 実装）

---

### Memory MCP に保存できない

**原因**: Memory MCP が設定されていない、または .mcp.json に未登録

**確認方法**:
```bash
jq '.mcpServers.memory' .mcp.json
```

**解決策**: `scripts/mcp/setup-mcp.sh` を実行して Memory MCP を自動追加

---

## ベストプラクティス

1. **チームサイズ**: 3-5名が最適（多すぎるとコスト増、少なすぎると並列効果薄い）
2. **タスク粒度**: 各メンバーが30分-1時間で完了できる粒度に分割
3. **WorkTree 活用**: 各メンバーは独立したブランチ/WorkTree で作業（ファイル競合回避）
4. **Memory MCP 活用**: 発見事項は Memory MCP に保存してチーム内共有
5. **定期報告**: 各メンバーは進捗を15分ごとにリードに報告
6. **早期 shutdown**: タスク完了後は即座に shutdown してリソース解放

---

## 参考リンク

- [Claude Code Agent Teams ドキュメント](https://docs.anthropic.com/claude/docs/agent-teams)
- [Task Management API](https://docs.anthropic.com/claude/docs/task-api)
- [Memory MCP Server](https://github.com/modelcontextprotocol/servers/tree/main/src/memory)
