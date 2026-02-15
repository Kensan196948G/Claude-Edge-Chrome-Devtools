# Claude-EdgeChromeDevTools 改善提案
**Improvement Proposals**

作成日: 2026-02-06
対象バージョン: v1.1.0 → v1.2.0以降

---

## 📋 目次

- [エグゼクティブサマリー](#エグゼクティブサマリー)
- [優先度: 高 (Critical)](#優先度-高-critical)
- [優先度: 中 (Important)](#優先度-中-important)
- [優先度: 低 (Future)](#優先度-低-future)
- [Quick Wins](#quick-wins-即座に実装可能)
- [実装ロードマップ](#実装ロードマップ)

---

## エグゼクティブサマリー

### 現状分析結果

両メインスクリプト (`Claude-EdgeDevTools.ps1` 648行, `Claude-ChromeDevTools-Final.ps1` 592行) を詳細分析した結果、以下の課題が判明:

| カテゴリ | 重大度 | 件数 | 影響 |
|---------|--------|------|------|
| **コード重複** | 🔴 高 | 540行 (90%) | 保守性低下、機能乖離発生済み |
| **セキュリティ** | 🔴 高 | 5箇所 | コマンドインジェクション、予測可能な一時ファイル |
| **入力検証欠落** | 🔴 高 | 5種類 | クラッシュリスク、誤操作 |
| **エラーハンドリング** | 🔴 高 | 7箇所 | リソースリーク、不明瞭なエラー |
| **パフォーマンス** | 🟡 中 | 10+ SSH | 起動時間の30-40%削減可能 |
| **機能乖離** | 🟡 中 | 4機能 | Edge/Chrome間で異なる挙動 |
| **未使用設定** | 🟡 中 | 2セクション | config.jsonの`claudeCode`が無効化 |

### 推奨アクション

**即座実装 (Quick Wins - 20分)**:
1. `.mcp.json`バックアップ追加 (Edge版)
2. 重複バナー・チェック削除
3. DevTools重複HTTP取得削除
4. プロジェクトインデックス検証

**v1.2.0リリース (3-4日)**:
- スクリプト統合・モジュール化
- セキュリティ強化 (入力サニタイズ、インジェクション対策)
- SSH接続バッチ化
- エラーハンドリング強化

---

## 優先度: 高 (Critical)

### 提案 #1: スクリプト統合とモジュール化

**現状の問題**:
```
Claude-EdgeDevTools.ps1     (648行)  ━┓
                                      ┣━ 540行 (90%) が重複
Claude-ChromeDevTools-Final.ps1 (592行) ━┛

既に発生している機能乖離:
  - Edge: DevTools Preferences設定あり、.mcp.jsonバックアップなし
  - Chrome: DevTools Preferences設定なし、.mcp.jsonバックアップあり
```

**解決策**: モジュール化アーキテクチャ

```
scripts/
├── lib/
│   ├── Config.ps1              # 設定読み込み・検証
│   ├── PortManager.ps1         # ポート検出・管理
│   ├── BrowserManager.ps1      # ブラウザ起動・プロセス管理
│   ├── ScriptGenerator.ps1     # run-claude.sh生成
│   ├── SettingsDeployer.ps1    # Statusline・設定展開
│   ├── SSHHelper.ps1           # SSH接続ヘルパー
│   └── Validator.ps1           # 入力検証ユーティリティ
├── main/
│   └── Claude-DevTools.ps1     # 統合スクリプト (単一ファイル)
└── templates/
    ├── run-claude.sh.tmpl      # bashテンプレート
    ├── init-prompt.txt         # 初期プロンプト (外部化)
    └── global-settings.sh.tmpl # グローバル設定スクリプト
```

**使用例**:
```powershell
# 対話モード
.\Claude-DevTools.ps1

# 非対話モード
.\Claude-DevTools.ps1 -Browser edge -Project "my-app" -NonInteractive

# ドライラン
.\Claude-DevTools.ps1 -DryRun
```

**効果**:
- 保守工数 **50%削減**
- 機能乖離の根絶
- テスタビリティ向上
- コマンドライン自動化対応

**工数**: 3日

---

### 提案 #2: `.mcp.json` バックアップ追加 (Edge版)

**現状**: Chrome版に実装済み、Edge版に欠落

**リスク**: MCP設定の意図しない上書き → データ損失

**実装**: Edge版スクリプト Section V-b直後に挿入

```powershell
# ============================================================
# ⑥ .mcp.json バックアップ
# ============================================================
Write-Host "📦 .mcp.json バックアップ作成中..."
$McpPath = "$LinuxBase/$ProjectName/.mcp.json"
$McpBackup = "$LinuxBase/$ProjectName/.mcp.json.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$McpBackupCmd = "if [ -f '$McpPath' ]; then cp '$McpPath' '$McpBackup'; echo '✅ バックアップ完了: $McpBackup'; else echo 'ℹ️  .mcp.jsonが存在しません（初回起動の可能性）'; fi"
ssh $LinuxHost $McpBackupCmd
```

**配置場所**: `Claude-EdgeDevTools.ps1` line 605付近 (Section VI/VII直前)

**工数**: 5分

---

### 提案 #3: 包括的入力検証

**現状の問題**:

| 入力項目 | 現在の検証 | リスク |
|---------|-----------|--------|
| プロジェクトインデックス | なし | 範囲外入力でクラッシュ |
| ブラウザ選択 | なし | 無効値で不明瞭なデフォルト動作 |
| ポート番号 | なし | 無効ポートで接続失敗 |
| config.json構造 | なし | null参照エラー |
| プロジェクト名 | なし | コマンドインジェクション |

**実装**:

```powershell
# ============================================================
# 入力検証モジュール
# ============================================================

function Assert-ConfigValid {
    param($Config)

    $requiredFields = @('ports', 'zDrive', 'linuxHost', 'linuxBase', 'edgeExe', 'chromeExe')
    foreach ($field in $requiredFields) {
        if (-not $Config.$field) {
            throw "❌ config.jsonに必須フィールドが不足: $field"
        }
    }

    # ポート範囲検証
    foreach ($port in $Config.ports) {
        if ($port -lt 1024 -or $port -gt 65535) {
            throw "❌ 無効なポート番号: $port (有効範囲: 1024-65535)"
        }
    }

    # ブラウザ実行ファイル存在確認
    if (-not (Test-Path $Config.edgeExe)) {
        Write-Warning "⚠️ Edge実行ファイルが見つかりません: $($Config.edgeExe)"
    }
    if (-not (Test-Path $Config.chromeExe)) {
        Write-Warning "⚠️ Chrome実行ファイルが見つかりません: $($Config.chromeExe)"
    }
}

function Read-ValidatedIndex {
    param([int]$Max, [string]$Prompt)

    do {
        $input = Read-Host $Prompt
        if ($input -match '^\d+$') {
            $idx = [int]$input
            if ($idx -ge 1 -and $idx -le $Max) {
                return $idx
            }
        }
        Write-Host "❌ 1から${Max}の数字を入力してください。" -ForegroundColor Red
    } while ($true)
}

function Read-ValidatedChoice {
    param([string[]]$ValidChoices, [string]$Prompt, [string]$Default)

    do {
        $input = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($input) -and $Default) {
            return $Default
        }
        if ($input -in $ValidChoices) {
            return $input
        }
        Write-Host "❌ 無効な選択です。有効な値: $($ValidChoices -join ', ')" -ForegroundColor Red
    } while ($true)
}

function Test-SafeProjectName {
    param([string]$Name)
    # 英数字、ハイフン、アンダースコア、ドットのみ許可
    return $Name -match '^[a-zA-Z0-9._-]+$'
}

# 使用例
Assert-ConfigValid $Config

$BrowserChoice = Read-ValidatedChoice -ValidChoices @("1", "2") `
    -Prompt "番号を入力 (1-2, デフォルト: 1)" -Default "1"

$Index = Read-ValidatedIndex -Max $Projects.Count `
    -Prompt "`n番号を入力 (1-$($Projects.Count))"
```

**工数**: 1時間

---

### 提案 #4: コマンドインジェクション対策

**現状の問題**:

```powershell
# 脆弱なコード (Edge: line 647, Chrome: line 591)
ssh -t ... $LinuxHost "cd $LinuxBase/$ProjectName && ./run-claude.sh"

# $ProjectName = "test; rm -rf /" の場合:
# → "cd /mnt/LinuxHDD/test; rm -rf / && ./run-claude.sh"
```

**解決策**:

```powershell
function Escape-SSHArgument {
    param([string]$Value)
    # bash変数として安全にエスケープ (printf %q相当)
    return "'" + ($Value -replace "'", "'\\''") + "'"
}

# すべてのSSH呼び出しで使用
$EscapedProjectName = Escape-SSHArgument $ProjectName
$EscapedLinuxBase = Escape-SSHArgument $LinuxBase
$EscapedLinuxPath = Escape-SSHArgument $LinuxPath

ssh $LinuxHost "mkdir -p $EscapedLinuxBase/$EscapedProjectName/.claude"
ssh $LinuxHost "chmod +x $EscapedLinuxPath"
ssh -t ... $LinuxHost "cd $EscapedLinuxBase/$EscapedProjectName && ./run-claude.sh"

# または配列渡しでより安全に
$sshArgs = @(
    "-t",
    "-o", "ControlMaster=no",
    "-o", "ControlPath=none",
    "-R", "${DevToolsPort}:127.0.0.1:${DevToolsPort}",
    $LinuxHost,
    "cd $(Escape-SSHArgument ($LinuxBase + '/' + $ProjectName)) && ./run-claude.sh"
)
& ssh @sshArgs
```

**影響範囲**:
- Edge: lines 510, 513, 522, 526, 529, 542, 548, 603, 626, 633, 647
- Chrome: lines 450, 453, 457, 461, 464, 477, 483, 538, 564, 570, 577, 591

**工数**: 1.5時間

---

### 提案 #5: SSH事前接続テスト

**現状の問題**:
- ブラウザ起動後にSSH失敗 → ブラウザプロセスが残存
- エラーメッセージがSSHの生エラー

**実装**:

```powershell
# ============================================================
# ① SSH接続事前確認
# ============================================================
Write-Host "`n🔍 SSH接続確認中: $LinuxHost ..."

try {
    $sshTestStart = Get-Date
    $sshResult = ssh -o ConnectTimeout=5 -o BatchMode=yes `
        -o StrictHostKeyChecking=accept-new $LinuxHost "echo OK" 2>&1

    if ($sshResult -ne "OK") {
        throw "SSH接続テスト失敗: $sshResult"
    }

    $elapsed = ((Get-Date) - $sshTestStart).TotalSeconds
    Write-Host "✅ SSH接続成功 ($([math]::Round($elapsed, 1))秒)"

} catch {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host "❌ SSHホスト '$LinuxHost' に接続できません" -ForegroundColor Red
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Red

    Write-Host "確認事項:"
    Write-Host "  1. ~/.ssh/config で $LinuxHost が定義されているか"
    Write-Host "  2. SSHキー認証が正しく設定されているか"
    Write-Host "  3. ホストが起動しているか (ping $LinuxHost)"
    Write-Host "  4. ネットワーク接続が有効か`n"

    Write-Host "詳細ログの確認: ssh -vvv $LinuxHost`n"

    throw "SSH接続テストに失敗しました。上記を確認してください。"
}
```

**配置場所**: ブラウザ起動直前 (Section II-III間)

**工数**: 30分

---

### 提案 #6: エラー時のクリーンアップ処理

**現状の問題**:
- スクリプト中断時にリソースが残存 (ブラウザプロセス、Linuxポート)
- try/finallyやtrapがない

**実装**:

```powershell
# ============================================================
# クリーンアップハンドラー
# ============================================================

$Global:BrowserProcess = $null
$Global:DevToolsPort = $null
$Global:LinuxHost = $null

# エラートラップ設定
trap {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    Write-Host "⚠️ エラーが発生しました。クリーンアップ中..." -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Yellow

    # ブラウザプロセス終了
    if ($Global:BrowserProcess) {
        try {
            if (-not $Global:BrowserProcess.HasExited) {
                Write-Host "🧹 ブラウザプロセスを終了中 (PID: $($Global:BrowserProcess.Id))..."
                $Global:BrowserProcess | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
                Write-Host "✅ ブラウザプロセス終了完了"
            }
        } catch {
            Write-Warning "ブラウザプロセス終了中にエラー: $_"
        }
    }

    # Linux側ポートクリーンアップ
    if ($Global:DevToolsPort -and $Global:LinuxHost) {
        try {
            Write-Host "🧹 Linux側ポート $Global:DevToolsPort をクリーンアップ中..."
            ssh -o ConnectTimeout=3 $Global:LinuxHost "fuser -k $Global:DevToolsPort/tcp 2>/dev/null || true" 2>$null
            Write-Host "✅ ポートクリーンアップ完了"
        } catch {
            Write-Warning "ポートクリーンアップ中にエラー: $_"
        }
    }

    Write-Host "`n❌ スクリプトを中断しました。" -ForegroundColor Red
    Write-Host "エラー詳細: $_`n" -ForegroundColor Red

    exit 1
}

# Ctrl+C ハンドラー
[Console]::TreatControlCAsInput = $false
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    # 既にtrapで処理されるため、追加処理は不要
}

# ブラウザ起動後にプロセス参照を保存
$Global:BrowserProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
    Where-Object { ... } | Select-Object -First 1
$Global:DevToolsPort = $DevToolsPort
$Global:LinuxHost = $LinuxHost
```

**工数**: 1時間

---

### 提案 #7: `config.json` `claudeCode` セクションの活用

**現状の問題**:
```json
// config.json に定義済みだが完全に無視されている
{
  "claudeCode": {
    "env": {
      "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
      "ENABLE_TOOL_SEARCH": "true",
      ...
    },
    "settings": {
      "language": "日本語",
      "outputStyle": "Explanatory",
      ...
    }
  }
}
```

スクリプト内でハードコード (Edge: lines 551-598, Chrome: lines 486-534)

**解決策**:

```powershell
# config.json読み込み後
$ClaudeEnv = $Config.claudeCode.env
$ClaudeSettings = $Config.claudeCode.settings

# グローバル設定スクリプトを動的生成
$envEntries = @()
foreach ($key in $ClaudeEnv.PSObject.Properties.Name) {
    $envEntries += "`"$key`": `"$($ClaudeEnv.$key)`""
}
$envJson = "{$($envEntries -join ', ')}"

$settingsEntries = @()
foreach ($key in $ClaudeSettings.PSObject.Properties.Name) {
    $value = $ClaudeSettings.$key
    $jsonValue = if ($value -is [bool]) { $value.ToString().ToLower() }
                 elseif ($value -is [int]) { $value }
                 else { "`"$value`"" }
    $settingsEntries += "`"$key`": $jsonValue"
}
$settingsJson = "{$($settingsEntries -join ', ')}"

$GlobalSettingsScript = @"
#!/bin/bash
jq '. + $settingsJson | .env = ((.env // {}) + $envJson)' ...
"@
```

**効果**: 設定変更が`config.json`編集のみで完結 (スクリプト変更不要)

**工数**: 2時間

---

### 提案 #8: SSH操作のバッチ化

**現状の問題**:
```
SSH接続 #1: jq確認
SSH接続 #2: jq インストール
SSH接続 #3: mkdir -p .claude
SSH接続 #4: statusline.sh展開
SSH接続 #5: settings.json展開
SSH接続 #6: グローバルコピー
SSH接続 #7: グローバル設定更新
SSH接続 #8: .mcp.jsonバックアップ
SSH接続 #9: chmod +x
SSH接続 #10: fuser -k (ポートクリーンアップ)
SSH接続 #11: 最終接続 (Claude起動)

合計11回の接続 → 各接続で約0.5-1秒のオーバーヘッド
```

**解決策**: 単一リモートセットアップスクリプト

```powershell
$RemoteSetupScript = @"
#!/bin/bash
set -e

echo '🔧 リモートセットアップ開始...'

# jq確認・インストール
if ! command -v jq &>/dev/null; then
    echo '📦 jq インストール中...'
    sudo apt-get update -qq && sudo apt-get install -y jq 2>/dev/null || \
    sudo yum install -y jq 2>/dev/null || \
    echo '⚠️ jq自動インストール失敗 (sudo権限が必要)'
fi

# ディレクトリ作成
mkdir -p '$LinuxBase/$ProjectName/.claude' ~/.claude

# statusline.sh展開
echo '$encodedStatusline' | base64 -d > '$StatuslineDest' && chmod +x '$StatuslineDest'
cp '$StatuslineDest' ~/.claude/statusline.sh

# settings.json展開
echo '$encodedSettings' | base64 -d > '$SettingsPath'

# グローバル設定更新
echo '$encodedGlobalScript' | base64 -d > /tmp/update_settings_\$\$.sh
chmod +x /tmp/update_settings_\$\$.sh
/tmp/update_settings_\$\$.sh
rm /tmp/update_settings_\$\$.sh

# .mcp.jsonバックアップ
if [ -f '$McpPath' ]; then
    cp '$McpPath' '$McpBackup'
    echo '✅ .mcp.jsonバックアップ: $McpBackup'
fi

# run-claude.sh権限
chmod +x '$LinuxPath'

# ポートクリーンアップ
fuser -k $DevToolsPort/tcp 2>/dev/null || true

echo '✅ リモートセットアップ完了'
"@

$encodedSetup = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RemoteSetupScript))
Write-Host "🚀 リモートセットアップ実行中..."
ssh $LinuxHost "echo '$encodedSetup' | base64 -d | bash -s"
```

**効果**:
- SSH接続回数: 11回 → 2回 (setup + 最終起動)
- セットアップ時間: **30-40%短縮**
- ネットワーク遅延の影響軽減

**工数**: 2時間

---

## 優先度: 中 (Important)

### 提案 #9: コマンドライン引数サポート

```powershell
<#
.SYNOPSIS
    Claude Code開発環境セットアップスクリプト

.DESCRIPTION
    Edge/ChromeブラウザとLinux上のClaude Codeを統合したリモート開発環境をセットアップ

.PARAMETER Browser
    使用するブラウザ ('edge' または 'chrome')

.PARAMETER Project
    プロジェクト名 (Z:\配下のディレクトリ名)

.PARAMETER Port
    DevToolsポート番号 (指定しない場合は自動選択)

.PARAMETER NonInteractive
    対話モードを無効化 (すべてのパラメータ指定が必須)

.PARAMETER SkipBrowserLaunch
    ブラウザ起動をスキップ (既に起動済みの場合)

.PARAMETER DryRun
    実際には実行せず、実行内容のプレビューのみ表示

.EXAMPLE
    .\Claude-DevTools.ps1
    対話モードで起動

.EXAMPLE
    .\Claude-DevTools.ps1 -Browser chrome -Project "my-app"
    Chrome + my-app で起動

.EXAMPLE
    .\Claude-DevTools.ps1 -Browser edge -Project "backend-api" -Port 9223 -NonInteractive
    完全非対話モードで起動 (CI/CD対応)
#>

param(
    [ValidateSet('edge', 'chrome')]
    [string]$Browser,

    [ValidateScript({
        if (Test-Path "Z:\$_") { $true }
        else { throw "プロジェクトが見つかりません: Z:\$_" }
    })]
    [string]$Project,

    [ValidateRange(1024, 65535)]
    [int]$Port,

    [switch]$NonInteractive,
    [switch]$SkipBrowserLaunch,
    [switch]$DryRun
)

# NonInteractiveモードでの必須パラメータチェック
if ($NonInteractive) {
    if (-not $Browser) { throw "-NonInteractiveモードでは -Browser が必須です" }
    if (-not $Project) { throw "-NonInteractiveモードでは -Project が必須です" }
}
```

**CI/CD統合例**:
```yaml
# GitHub Actions
- name: Deploy to Claude Dev Environment
  run: |
    pwsh -File scripts/main/Claude-DevTools.ps1 `
      -Browser chrome `
      -Project "my-ci-project" `
      -NonInteractive
```

**工数**: 3時間

---

### 提案 #10: 初期プロンプトの外部ファイル化

**現状の問題**:
- 145行の初期プロンプトがbash heredoc内にハードコード
- 変更時にPowerShellスクリプトを編集が必要
- 多言語対応困難

**解決策**:

```
scripts/
└── templates/
    ├── init-prompt-ja.txt      # 日本語版
    ├── init-prompt-en.txt      # 英語版
    └── run-claude.sh.tmpl      # bashテンプレート
```

```bash
# run-claude.sh.tmpl (簡略化)
#!/usr/bin/env bash
set -euo pipefail

PORT=__DEVTOOLS_PORT__
RESTART_DELAY=__RESTART_DELAY__
INIT_PROMPT_FILE="__INIT_PROMPT_FILE__"

# DevTools接続確認
...

# 環境変数設定
export CLAUDE_CHROME_DEBUG_PORT=${PORT}
export MCP_CHROME_DEBUG_PORT=${PORT}
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Claude起動 (初期プロンプトは外部ファイルから)
if [ -f "$INIT_PROMPT_FILE" ]; then
    cat "$INIT_PROMPT_FILE" | claude --dangerously-skip-permissions
else
    claude --dangerously-skip-permissions
fi
```

```powershell
# PowerShell側
$promptTemplate = Get-Content "scripts\templates\init-prompt-ja.txt" -Raw -Encoding UTF8
$promptPath = "$LinuxBase/$ProjectName/.claude/init-prompt.txt"

# プロンプトファイルを転送
$encodedPrompt = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($promptTemplate))
ssh $LinuxHost "echo '$encodedPrompt' | base64 -d > '$promptPath'"

# run-claude.sh生成時にパスを埋め込み
$runClaude = $runClaudeTemplate `
    -replace '__DEVTOOLS_PORT__', $DevToolsPort `
    -replace '__RESTART_DELAY__', 3 `
    -replace '__INIT_PROMPT_FILE__', "$promptPath"
```

**効果**:
- 初期プロンプト変更がテキスト編集のみで完結
- 多言語対応が容易
- PowerShellスクリプトの可読性向上

**工数**: 1.5時間

---

### 提案 #11: プロセス終了待機の最適化

**現状**: 固定2秒待機 (Edge: line 126, Chrome: line 116)

```powershell
# 改善版
$existingProcesses | Stop-Process -Force -ErrorAction SilentlyContinue

# プロセス終了をポーリング (最大5秒)
$maxWait = 5
$waited = 0
while ($waited -lt $maxWait) {
    $remaining = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -in $existingProcesses.Id }

    if (-not $remaining) {
        Write-Host "✅ プロセス終了確認 ($waited 秒)" -ForegroundColor Green
        break
    }

    Start-Sleep -Milliseconds 200
    $waited += 0.2
}

if ($waited -ge $maxWait) {
    Write-Warning "⚠️ 一部プロセスが終了しませんでした (タイムアウト)"
}
```

**効果**: 平均待機時間 2秒 → 0.2-0.5秒

---

### 提案 #12: プロジェクト選択UI拡張

**提案**:

```powershell
Write-Host "`n📦 プロジェクトを選択してください`n"

for ($i = 0; $i -lt $Projects.Count; $i++) {
    $proj = $Projects[$i]
    $meta = @()

    # run-claude.sh存在確認
    $runClaudeExists = Test-Path "$($proj.FullName)\run-claude.sh"
    if ($runClaudeExists) { $meta += "📜" }

    # Gitリポジトリ確認
    $isGitRepo = Test-Path "$($proj.FullName)\.git"
    if ($isGitRepo) {
        $branch = git -C $proj.FullName branch --show-current 2>$null
        if ($branch) {
            $meta += "🌿 $branch"
        } else {
            $meta += "🌿"
        }
    }

    # 最終使用マーク
    if ($proj.Name -eq $LastUsedProject) {
        $meta += "⭐"
    }

    # 最終更新日時
    $age = (Get-Date) - $proj.LastWriteTime
    $ageStr = if ($age.TotalDays -lt 1) {
        "$([math]::Round($age.TotalHours))h前"
    } elseif ($age.TotalDays -lt 7) {
        "$([math]::Round($age.TotalDays))日前"
    } else {
        $proj.LastWriteTime.ToString("MM/dd")
    }

    $metaStr = if ($meta.Count -gt 0) { " [$($meta -join ' ')]" } else { "" }
    $ageColor = if ($age.TotalDays -lt 7) { "Green" } else { "Gray" }

    Write-Host "[$($i + 1)] " -NoNewline
    Write-Host $proj.Name -NoNewline -ForegroundColor White
    Write-Host $metaStr -NoNewline -ForegroundColor Cyan
    Write-Host " ($ageStr)" -ForegroundColor $ageColor
}

Write-Host "`n💡 凡例: 📜=設定済, 🌿=Git, ⭐=前回使用"
```

**出力例**:
```
📦 プロジェクトを選択してください

[1] frontend-app [📜 🌿 main ⭐] (2h前)
[2] api-server [📜 🌿 develop] (1日前)
[3] legacy-tool [🌿] (01/15)
[4] test-project (3日前)

💡 凡例: 📜=設定済, 🌿=Git, ⭐=前回使用
```

**工数**: 1.5時間

---

## 優先度: 低 (Future)

### 提案 #13-23

詳細は省略。以下を含む:

13. 定数の`config.json`外部化 (`timeouts`セクション)
14. ブラウザプロファイル自動クリーンアップ (30日以上古いプロファイル削除)
15. ログファイル出力 (`Start-Transcript`)
16. ドライラン (Dry-Run) モード
17. 設定バックアップ・ロールバック機能
18. Firefoxサポート
19. 並列プロジェクト起動コマンド
20. 設定プリセット機能
21. Windows Terminal自動起動 (start.bat改善)
22. `Get-AvailablePort`関数の共通ライブラリ化
23. DevTools Preferences の Chrome版追加 (機能パリティ)

---

## Quick Wins (即座に実装可能)

### 🚀 20分で4つの改善

#### A. `.mcp.json`バックアップ追加 (5分)
- Edge版 line 605に6行追加

#### B. 重複バナー・チェック削除 (2分)
- Edge版 lines 70-77を削除

#### C. DevTools重複HTTP取得削除 (3分)
- 両スクリプトで2回目の`Invoke-RestMethod`削除

#### D. プロジェクトインデックス検証 (10分)
- `Read-ValidatedIndex`関数追加

**実装コード**は上記の各提案セクションを参照。

---

## 実装ロードマップ

### Phase 1: Quick Wins (即日)
**工数**: 20分
**対象**: 提案 #2, #9の一部, #11

### Phase 2: v1.2.0 Critical (1週間)
**工数**: 3-4日
**対象**: 提案 #1, #3, #4, #5, #6, #7, #8

**期待効果**:
- 🔒 セキュリティリスク排除
- 🚀 起動時間30-40%短縮
- 🛡️ 安定性向上 (クラッシュ・リソースリーク解消)
- 📦 保守工数50%削減

### Phase 3: v1.3.0 Enhancement (2週間)
**工数**: 2-3日
**対象**: 提案 #9, #10, #12, #13, #14, #15

**期待効果**:
- 🎨 UX大幅改善
- 🤖 CI/CD統合対応
- 📊 デバッグ効率化

### Phase 4: v1.4.0 Advanced (1ヶ月)
**工数**: 3-4日
**対象**: 提案 #16-23

**期待効果**:
- 🌐 ブラウザサポート拡大
- ⚙️ 高度な設定機能
- 🔄 エンタープライズ運用対応

---

## 参考: 類似プロジェクトのベストプラクティス

1. **VS Code Remote Development** - SSH接続プール、設定同期機構
2. **Docker Compose** - YAML設定駆動、サービス依存関係管理
3. **Vagrant** - Rubyベースプラグインアーキテクチャ、プロビジョナー分離
4. **Ansible** - 冪等性保証、ロールベースモジュール構造

これらのパターンを参考に、特に**設定駆動**と**モジュール分離**を重視すべきです。

---

## 📞 フィードバック

この改善提案について:
- 優先度の調整が必要な項目
- 追加で検討すべき機能
- 実装時の技術的懸念

があればお知らせください。

---

**最終更新**: 2026-02-06
