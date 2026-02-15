# Configuration Setup

## クイックスタート

### 1. config.json の作成

```powershell
# テンプレートから config.json をコピー
cd config
cp config.json.template config.json
```

### 2. 環境に合わせて編集

`config.json` を開き、以下を設定：

#### 必須設定

| 項目 | 説明 | 例 |
|------|------|-----|
| `zDrive` | プロジェクトがマウントされているドライブ | `"X:\\"` または `"Z:\\"` |
| `zDriveUncPath` | ドライブのUNCパス | `"\\\\192.168.1.100\\Projects"` |
| `linuxHost` | SSH接続先ホスト名（~/.ssh/config で定義） | `"your-linux-host"` |
| `linuxBase` | Linuxプロジェクトベースパス | `"/mnt/Projects"` |

#### オプション設定

**GitHub MCP を使用する場合**:
```json
{
  "mcp": {
    "githubToken": "<Base64エンコード済みToken>"
  }
}
```

Token の Base64 エンコード方法:
```powershell
$token = "ghp_YOUR_GITHUB_TOKEN"
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($token))
Write-Host $encoded
# 出力された文字列を githubToken に設定
```

**Brave Search MCP を使用する場合**:
```json
{
  "mcp": {
    "braveApiKey": "YOUR_BRAVE_API_KEY"
  }
}
```

### 3. SSH 設定

`~/.ssh/config` にホストを定義：

```
Host your-linux-host
    HostName 192.168.1.100
    User your-username
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 60
```

SSH鍵がない場合は生成：
```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
ssh-copy-id your-linux-host
```

### 4. 動作確認

```cmd
start.bat
```

メニューからオプション 1 (Edge) または 2 (Chrome) を選択。

---

## トラブルシューティング

### config.json が見つからない

**エラー**: `❌ 設定ファイルが見つかりません: config\config.json`

**解決策**: `config.json.template` から `config.json` を作成してください（上記手順1参照）

### SSH接続できない

**確認事項**:
1. `~/.ssh/config` でホストが定義されているか
2. `ssh your-linux-host` でパスワードなしで接続できるか
3. SSH鍵の権限が正しいか（Windows の場合は icacls で確認）

### X:\ ドライブが見つからない

スクリプトは自動的に `zDriveUncPath` の UNC パスにフォールバックします。

UNC パスが正しく設定されているか確認：
```powershell
Test-Path "\\your-server\your-share"
```

---

## config.json スキーマ

完全なスキーマは `config.json.template` を参照してください。

主要セクション:
- `ports`: DevToolsポート配列
- `zDrive` / `zDriveUncPath`: プロジェクトルート
- `linuxHost` / `linuxBase`: Linux環境
- `edgeExe` / `chromeExe`: ブラウザパス
- `statusline`: Statusline表示設定
- `claudeCode`: Claude Code環境変数・設定
- `mcp`: MCP自動セットアップ設定
