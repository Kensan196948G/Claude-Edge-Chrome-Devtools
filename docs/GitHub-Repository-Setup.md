# GitHub リポジトリセットアップガイド

## 概要

このドキュメントは、Claude-EdgeChromeDevTools プロジェクトを GitHub リポジトリとして公開するための手順を説明します。

---

## ステップ1: .gitignore 確認

`.gitignore` ファイルが作成済みであることを確認してください。

**重要**: 以下が `.gitignore` に含まれているか確認：
- `config/config.json` の **Token・API Key** がコミットされないようにする場合は、`config/config.json` を追加
- または、Token・API Key を環境変数や別ファイルに分離

**推奨アプローチ**:
```json
// config.json (リポジトリにコミット)
{
  "mcp": {
    "githubToken": "",  // 空にしておく
    "braveApiKey": ""   // 空にしておく
  }
}

// config.local.json (gitignore で除外、個人環境のみ)
{
  "mcp": {
    "githubToken": "Z2hwXz...",
    "braveApiKey": "BSApolE..."
  }
}
```

---

## ステップ2: ローカル Git リポジトリ初期化

```powershell
# プロジェクトディレクトリに移動
cd D:\Claude-EdgeChromeDevTools

# Git 初期化
git init

# すべてのファイルをステージング
git add .

# 初回コミット
git commit -m "Initial commit: Claude-EdgeChromeDevTools v1.2.0

Features:
- Edge/Chrome DevTools integration with Claude Code
- SSH port forwarding automation
- MCP auto-setup (8 servers)
- Hooks integration (on-startup, pre-commit)
- Agent Teams templates (review-team)
- Memory MCP context restoration
- UNC path fallback for network drives

Co-Authored-By: Claude Sonnet 4.5 (1M context) <noreply@anthropic.com>"
```

---

## ステップ3: GitHub リポジトリ作成

### オプションA: GitHub Web UI

1. https://github.com/new にアクセス
2. **Repository name**: `claude-edge-chrome-devtools`
3. **Description**: `Windows-Linux integration for Claude Code with Edge/Chrome DevTools`
4. **Visibility**:
   - 🔒 **Private** 推奨（Token が含まれる場合）
   - 🌐 **Public**（Token を分離した場合のみ）
5. ✅ **Add README** のチェックを**外す**（既に README.md がある）
6. ✅ **.gitignore** のチェックを**外す**（既に .gitignore がある）
7. **Create repository** をクリック

### オプションB: GitHub CLI (`gh` コマンド)

```powershell
# GitHub CLI で作成（Private リポジトリ）
gh repo create claude-edge-chrome-devtools --private --source=. --remote=origin

# または Public リポジトリ
gh repo create claude-edge-chrome-devtools --public --source=. --remote=origin
```

---

## ステップ4: リモートリポジトリに Push

```powershell
# リモート追加（Web UI で作成した場合）
git remote add origin https://github.com/<your-username>/claude-edge-chrome-devtools.git

# デフォルトブランチを main に変更（推奨）
git branch -M main

# 初回 Push
git push -u origin main
```

---

## ステップ5: GitHub リポジトリ設定

### 5.1 ブランチ保護ルール（推奨）

Settings → Branches → Add rule

**ルール設定**:
- ✅ Branch name pattern: `main`
- ✅ Require a pull request before merging
- ✅ Require status checks to pass before merging
- ✅ Require conversation resolution before merging
- ✅ Do not allow bypassing the above settings

### 5.2 Secrets 設定

Settings → Secrets and variables → Actions → New repository secret

**追加する Secrets**:

| Name | Value | 用途 |
|------|-------|------|
| `CLAUDE_GITHUB_TOKEN` | `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` | GitHub MCP用（あなたのToken） |
| `BRAVE_API_KEY` | `BSA********************************` | Brave Search MCP用（あなたのAPI Key） |

これにより、GitHub Actions ワークフローから安全に Token を利用できます。

### 5.3 リポジトリトピック（タグ）

Settings → General → Topics

**推奨トピック**:
- `claude-code`
- `devtools`
- `browser-automation`
- `ssh-integration`
- `agent-teams`
- `mcp-servers`
- `powershell`
- `windows-linux`

---

## ステップ6: README.md 拡張（オプション）

README.md にバッジを追加：

```markdown
# Claude-EdgeChromeDevTools

[![License](https://img.shields.io/github/license/your-username/claude-edge-chrome-devtools)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.5-blue)](https://github.com/PowerShell/PowerShell)
[![Agent Teams](https://img.shields.io/badge/Agent%20Teams-Enabled-green)](https://docs.anthropic.com/claude/docs/agent-teams)
[![MCP Servers](https://img.shields.io/badge/MCP%20Servers-8-orange)](https://modelcontextprotocol.io/)

Windows-Linux integration for Claude Code with Edge/Chrome DevTools
```

---

## ステップ7: GitHub Actions ワークフロー作成

`.github/workflows/validate.yml` を作成（自動検証）：

```yaml
name: Validate Configuration

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  validate-config:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Validate config.json
        shell: pwsh
        run: |
          $config = Get-Content config/config.json -Raw | ConvertFrom-Json
          Write-Host "✅ config.json is valid JSON"

      - name: Validate PowerShell Syntax
        shell: pwsh
        run: |
          Get-ChildItem -Path scripts -Filter *.ps1 -Recurse | ForEach-Object {
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
              (Get-Content $_.FullName -Raw), [ref]$errors
            )
            if ($errors.Count -gt 0) {
              throw "Syntax errors in $($_.Name)"
            }
            Write-Host "✅ $($_.Name)"
          }
```

---

## ステップ8: プロジェクト公開チェックリスト

公開前に以下を確認：

### セキュリティチェック

- [ ] `config.json` から Token・API Key を削除または環境変数化
- [ ] `.gitignore` で機密情報が除外されているか確認
- [ ] `git log` で過去のコミットに機密情報が含まれていないか確認
- [ ] SSH 秘密鍵（`~/.ssh/id_ed25519`）がリポジトリに含まれていないか確認

### ドキュメント充実度

- [ ] README.md に使い方が明記されているか
- [ ] ライセンスファイル（LICENSE）を追加
- [ ] CONTRIBUTING.md を追加（コントリビューションガイドライン）
- [ ] CHANGELOG.md を追加（変更履歴）

### 機能テスト

- [ ] Windows 環境でスクリプトが正常動作するか
- [ ] Linux 環境で Claude Code が起動するか
- [ ] Hooks が正しく動作するか（pre-commit で機密情報検出）
- [ ] MCP 8個が正常に接続するか

---

## Token に関する推奨事項

### 既存 Token を使う場合（推奨）

**メリット**:
- Token の数を最小限に管理
- 既に `config.json` に設定済み
- 即座に利用開始可能

**注意点**:
- Token の権限が十分か確認（`repo` + `workflow`）
- 有効期限を確認（設定されている場合）

---

### 新しい Token を作成する場合

**推奨するケース**:
- プロジェクト専用 Token で管理したい
- 既存 Token の権限が不足している
- 既存 Token を他のプロジェクトと分離したい

**作成手順**:
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token (classic)"
3. **Note**: `Claude-EdgeChromeDevTools Project Token`
4. **Expiration**: 90 days または No expiration
5. **権限**:
   - ✅ `repo` (すべてのサブ項目)
   - ✅ `workflow`
   - ✅ `write:packages`（オプション: Docker イメージ等を使う場合）
6. "Generate token" → Token をコピー
7. Base64 エンコード:
   ```powershell
   $token = "ghp_YOUR_NEW_TOKEN"
   $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($token))
   Write-Host $encoded
   ```
8. `config.json` の `mcp.githubToken` に設定

---

## まとめ

### 推奨: 既存 Token を使用 + Private リポジトリ

**理由**:
- ✅ 最も早く開始できる（Token 再利用）
- ✅ セキュリティが確保される（Private）
- ✅ Agent Teams・CI/CD 機能がフル活用可能
- ✅ `pre-commit` hook で機密情報の誤コミットを防止済み

### 実行コマンド例

```powershell
# Git リポジトリ初期化
cd D:\Claude-EdgeChromeDevTools
git init
git add .
git commit -m "Initial commit: Claude-EdgeChromeDevTools v1.2.0"

# GitHub リポジトリ作成（CLI）
gh repo create claude-edge-chrome-devtools --private --source=. --remote=origin

# Push
git push -u origin main
```

---

GitHub リポジトリを作成しますか？作成する場合、上記のコマンドを実行するお手伝いをします。