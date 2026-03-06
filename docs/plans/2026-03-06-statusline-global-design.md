# Statusline グローバル再設定 設計書

**日付:** 2026-03-06
**参照:** https://github.com/loadbalance-sudachi-kun/claude-code-statusline
**ステータス:** 設計承認済み → 実装計画へ

---

## 目的

Claude Code の Statusline を GitHub 参照リポジトリにインスパイアされた形式に全面改訂し、
`~/.claude/settings.json` のグローバル設定として配置する。

---

## 表示フォーマット（承認済み）

```
🤖 Opus 4.6 │ 📊 25% │ ✏️  +5/-1 │ 🔀 main
⏱ 5h  ▰▰▰▱▱▱▱▱▱▱  28%  Resets 9pm (Asia/Tokyo)
📅 7d  ▰▰▰▰▰▰▱▱▱▱  59%  Resets Mar 6 at 1pm (Asia/Tokyo)
```

| 行 | 内容 |
|----|------|
| Line 1 | モデル名 / コンテキスト使用率% / セッション編集量 / Gitブランチ |
| Line 2 | 5時間ウィンドウ レート制限プログレスバー + リセット時刻 (Asia/Tokyo) |
| Line 3 | 7日間ウィンドウ レート制限プログレスバー + リセット時刻 (Asia/Tokyo) |

---

## アーキテクチャ

### グローバル配置フロー

```
Windows側                              Linux側
───────────────────────────────       ─────────────────────────────
scripts/statusline.sh (改訂版)   →    ~/.claude/statusline.sh
scripts/lib/ScriptGenerator.psm1 →   ~/.claude/settings.json
  ├── base64エンコード                  └── {
  ├── SSH転送 (既存機構)                      "statusLine": {
  └── jqマージ更新                               "type": "command",
                                                "command": "bash ~/.claude/statusline.sh"
                                             }
                                         }
```

### レート制限取得: Haiku Probe方式

- **方式:** `ANTHROPIC_API_KEY` を使用してclaude-haiku-4-5にminimalリクエスト
- **キャッシュ:** `/tmp/.claude-statusline-cache` (6分TTL)
- **対応OS:** Linux (macOS Keychain不使用)
- **取得ヘッダ:**
  - `anthropic-ratelimit-requests-remaining`
  - `anthropic-ratelimit-requests-reset`
  - `anthropic-ratelimit-tokens-remaining`
  - `anthropic-ratelimit-tokens-reset`

### プログレスバー形式

```bash
# 10段階のブロック文字
FILLED="▰"   # 使用済み
EMPTY="▱"    # 残り
# 例: 28% → ▰▰▱▱▱▱▱▱▱▱
```

### リセット時刻フォーマット

- 当日リセット: `Resets 9pm (Asia/Tokyo)`
- 翌日以降: `Resets Mar 6 at 1pm (Asia/Tokyo)`
- TZ=Asia/Tokyo で date コマンド使用

---

## 変更ファイル

| ファイル | 種別 | 変更内容 |
|--------|------|---------|
| `scripts/statusline.sh` | **改修** | GitHub参照フォーマットに全面改訂。Haiku Probe実装。 |
| `scripts/lib/ScriptGenerator.psm1` | **改修** | グローバルsettings.jsonに `statusLine.command` を追加するjqマージコマンドを追記 |

---

## 技術仕様

### statusline.sh 入力 (stdin JSON from Claude Code)

```json
{
  "model": "claude-opus-4-6",
  "context": { "percent": 25 },
  "session": { "lines_added": 5, "lines_removed": 1 }
}
```

### Haiku Probe APIリクエスト

```bash
curl -s -I -X POST "https://api.anthropic.com/v1/messages" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'
```

### グローバル settings.json マージ (ScriptGenerator.psm1)

```bash
jq '. + {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline.sh"}}' \
  ~/.claude/settings.json > /tmp/settings.tmp && mv /tmp/settings.tmp ~/.claude/settings.json
```

---

## 制約・注意事項

- `ANTHROPIC_API_KEY` 環境変数が必須 (未設定時はLine 2/3をスキップ)
- Haiku Probeは1リクエスト/6分 — コスト: 約$0.000025/回
- macOS非対応 (Keychain不使用のLinux専用実装)
- `jq`, `curl`, `date`, `git` が依存コマンド

---

## 除外事項 (YAGNI)

- ccusage連携 (レート制限表示で不要になったため)
- config.json の showX フラグ実装 (今回スコープ外)
- Windows側 statusline.sh の変更 (Linux専用スクリプト)
