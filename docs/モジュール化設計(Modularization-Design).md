# モジュール化設計ドキュメント
**Modularization Design Document**

作成日: 2026-02-06
対象バージョン: v1.3.0

---

## 目的

現在の2つのメインスクリプト (Edge/Chrome) は540行以上が重複しており、保守性に課題があります。このドキュメントは、共通機能をモジュール化し、単一の統合スクリプトから利用する新アーキテクチャを定義します。

---

## 現状分析

### 現在のファイル構造

```
scripts/
├── main/
│   ├── Claude-EdgeDevTools.ps1       (825行)
│   └── Claude-ChromeDevTools-Final.ps1 (792行)
└── ...

重複率: 約90% (540行以上が実質的に同一)
```

### 機能分解

両スクリプトを分析した結果、以下の独立した責務が特定されました:

| # | 責務 | 行数 | 依存関係 |
|---|------|------|----------|
| 1 | 設定読み込み・検証 | ~30行 | なし |
| 2 | ポート管理 | ~20行 | 設定 |
| 3 | UI (ブラウザ/プロジェクト選択) | ~40行 | 設定 |
| 4 | ブラウザプロセス管理 | ~80行 | 設定, ポート |
| 5 | run-claude.sh生成 | ~200行 | 設定, プロジェクト |
| 6 | リモートセットアップ | ~170行 | 設定, エスケープ |
| 7 | SSH接続管理 | ~30行 | 設定, エスケープ |
| 8 | エラーハンドリング | ~40行 | グローバル状態 |

---

## 新アーキテクチャ

### ディレクトリ構造

```
scripts/
├── lib/
│   ├── Config.ps1              # 設定読み込み・検証
│   ├── PortManager.ps1         # ポート検出・管理
│   ├── UI.ps1                  # ユーザーインターフェース
│   ├── BrowserManager.ps1      # ブラウザ起動・プロセス管理
│   ├── ScriptGenerator.ps1     # run-claude.sh生成
│   ├── RemoteSetup.ps1         # リモート環境セットアップ
│   ├── SSHHelper.ps1           # SSH接続ヘルパー
│   └── ErrorHandler.ps1        # エラーハンドリング・クリーンアップ
├── main/
│   └── Claude-DevTools.ps1     # 統合メインスクリプト (新規)
├── templates/
│   ├── run-claude.sh.tmpl      # bashテンプレート
│   └── init-prompt.txt         # 初期プロンプト
├── setup/
│   └── ...
└── test/
    └── ...
```

###モジュール詳細設計

#### 1. Config.ps1

```powershell
<#
.SYNOPSIS
    設定ファイル読み込み・検証モジュール
#>

function Import-ProjectConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath
    )

    if (-not $ConfigPath) {
        $RootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $ConfigPath = Join-Path $RootDir "config\config.json"
    }

    if (-not (Test-Path $ConfigPath)) {
        throw "設定ファイルが見つかりません: $ConfigPath"
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    # 必須フィールド検証
    $requiredFields = @('ports', 'zDrive', 'linuxHost', 'linuxBase', 'edgeExe', 'chromeExe')
    foreach ($field in $requiredFields) {
        if (-not $config.$field) {
            throw "config.jsonに必須フィールドが不足: $field"
        }
    }

    # ポート検証
    foreach ($port in $config.ports) {
        if ($port -lt 1024 -or $port -gt 65535) {
            throw "無効なポート番号: $port"
        }
    }

    return $config
}

Export-ModuleMember -Function Import-ProjectConfig
```

#### 2. PortManager.ps1

```powershell
<#
.SYNOPSIS
    ポート管理モジュール
#>

function Get-AvailableDevToolsPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int[]]$Ports
    )

    foreach ($port in $Ports) {
        $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if (-not $listener) {
            return $port
        }
    }

    return $null
}

function Stop-PortProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port,

        [Parameter(Mandatory=$true)]
        [string]$ProcessName
    )

    $processes = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique |
        ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_.ProcessName -eq $ProcessName }

    if ($processes) {
        Write-Verbose "ポート $Port を使用中の$($processes.Count)個のプロセスを終了します"
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
        return $true
    }

    return $false
}

Export-ModuleMember -Function Get-AvailableDevToolsPort, Stop-PortProcesses
```

#### 3. UI.ps1

```powershell
<#
.SYNOPSIS
    ユーザーインターフェースモジュール
#>

function Select-Browser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('edge', 'chrome')]
        [string]$DefaultBrowser = 'edge',

        [Parameter(Mandatory=$false)]
        [switch]$NonInteractive
    )

    if ($NonInteractive) {
        return $DefaultBrowser
    }

    Write-Host "`n🌐 ブラウザを選択してください:`n"
    Write-Host "[1] Microsoft Edge"
    Write-Host "[2] Google Chrome"
    Write-Host ""

    do {
        $choice = Read-Host "番号を入力 (1-2, デフォルト: $(if ($DefaultBrowser -eq 'edge') { 1 } else { 2 }))"

        if ([string]::IsNullOrWhiteSpace($choice)) {
            return $DefaultBrowser
        }

        if ($choice -in @("1", "2")) {
            return $(if ($choice -eq "1") { "edge" } else { "chrome" })
        }

        Write-Host "❌ 1 または 2 を入力してください。" -ForegroundColor Red
    } while ($true)
}

function Select-Project {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory=$false)]
        [string]$ProjectName,

        [Parameter(Mandatory=$false)]
        [switch]$NonInteractive,

        [Parameter(Mandatory=$false)]
        [switch]$ShowMetadata
    )

    $projects = Get-ChildItem $ProjectRoot -Directory | Sort-Object Name

    if ($projects.Count -eq 0) {
        throw "プロジェクトが見つかりません: $ProjectRoot"
    }

    # 非対話モード
    if ($NonInteractive -and $ProjectName) {
        $project = $projects | Where-Object { $_.Name -eq $ProjectName } | Select-Object -First 1
        if (-not $project) {
            throw "指定されたプロジェクトが見つかりません: $ProjectName"
        }
        return $project
    }

    # 対話モード
    Write-Host "📦 プロジェクトを選択してください`n"

    for ($i = 0; $i -lt $projects.Count; $i++) {
        $proj = $projects[$i]
        $meta = ""

        if ($ShowMetadata) {
            $indicators = @()
            if (Test-Path "$($proj.FullName)\run-claude.sh") { $indicators += "📜" }
            if (Test-Path "$($proj.FullName)\.git") { $indicators += "🌿" }
            $meta = if ($indicators.Count -gt 0) { " [$($indicators -join ' ')]" } else { "" }
        }

        Write-Host "[$($i+1)] $($proj.Name)$meta"
    }

    if ($ShowMetadata) {
        Write-Host "`n💡 凡例: 📜=設定済, 🌿=Git"
    }

    do {
        $index = Read-Host "`n番号を入力 (1-$($projects.Count))"

        if ($index -match '^\d+$') {
            $idx = [int]$index
            if ($idx -ge 1 -and $idx -le $projects.Count) {
                return $projects[$idx - 1]
            }
        }

        Write-Host "❌ 1から$($projects.Count)の範囲で入力してください。" -ForegroundColor Red
    } while ($true)
}

Export-ModuleMember -Function Select-Browser, Select-Project
```

#### 4. BrowserManager.ps1

```powershell
<#
.SYNOPSIS
    ブラウザライフサイクル管理モジュール
#>

function Start-DevToolsBrowser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('edge', 'chrome')]
        [string]$Browser,

        [Parameter(Mandatory=$true)]
        [int]$Port,

        [Parameter(Mandatory=$true)]
        [hashtable]$Config,

        [Parameter(Mandatory=$false)]
        [int]$StartupTimeoutSeconds = 15
    )

    $browserExe = if ($Browser -eq 'edge') { $Config.edgeExe } else { $Config.chromeExe }
    $browserName = if ($Browser -eq 'edge') { "Microsoft Edge" } else { "Google Chrome" }
    $processName = if ($Browser -eq 'edge') { "msedge" } else { "chrome" }

    # ブラウザ存在確認
    if (-not (Test-Path $browserExe)) {
        throw "$browserName が見つかりません: $browserExe"
    }

    # プロファイルディレクトリ
    $profileDir = "C:\DevTools-$Browser-$Port"

    # 既存プロセスクリーンアップ
    $cleaned = Stop-PortProcesses -Port $Port -ProcessName $processName
    if ($cleaned) {
        Start-Sleep -Milliseconds 500
    }

    # プロファイル作成
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # Edge固有: DevTools Preferences設定
    if ($Browser -eq 'edge') {
        Set-EdgeDevToolsPreferences -ProfileDir $profileDir
    }

    # ブラウザ起動
    $startUrl = "http://localhost:$Port"
    $browserArgs = @(
        "--remote-debugging-port=$Port",
        "--user-data-dir=`"$profileDir`"",
        "--no-first-run",
        "--no-default-browser-check",
        "--remote-allow-origins=*"
    )

    if ($Browser -eq 'edge') {
        $browserArgs += "--auto-open-devtools-for-tabs"
    }

    $browserArgs += $startUrl

    Write-Host "🌐 $browserName DevTools 起動中..."
    $process = Start-Process -FilePath $browserExe -ArgumentList $browserArgs -PassThru

    # 起動待機
    $versionInfo = Wait-DevToolsReady -Port $Port -TimeoutSeconds $StartupTimeoutSeconds

    return @{
        Process = $process
        VersionInfo = $versionInfo
        Browser = $browserName
    }
}

function Wait-DevToolsReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port,

        [Parameter(Mandatory=$true)]
        [int]$TimeoutSeconds
    )

    $waited = 0

    while ($waited -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 1
        $waited++

        $listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue

        if ($listening) {
            try {
                $versionInfo = Invoke-RestMethod -Uri "http://localhost:$Port/json/version" -TimeoutSec 3 -ErrorAction Stop
                Write-Host "✅ DevTools接続成功 ($waited 秒)" -ForegroundColor Green
                return $versionInfo
            } catch {
                Write-Verbose "応答待機中... ($waited/$TimeoutSeconds)"
            }
        } else {
            Write-Verbose "起動中... ($waited/$TimeoutSeconds)"
        }
    }

    throw "DevTools起動タイムアウト ($TimeoutSeconds 秒)"
}

function Set-EdgeDevToolsPreferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfileDir
    )

    $prefsPath = Join-Path $ProfileDir "Default\Preferences"
    $prefsDir = Split-Path $prefsPath -Parent

    if (-not (Test-Path $prefsDir)) {
        New-Item -ItemType Directory -Path $prefsDir -Force | Out-Null
    }

    $devToolsPrefs = @{
        devtools = @{
            preferences = @{
                "cacheDisabled" = "true"
                "autoOpenDevToolsForPopups" = "true"
                "preserveConsoleLog" = "true"
                "consoleTimestampsEnabled" = "true"
                "network_log.preserve-log" = "true"
            }
        }
    }

    $prefsJson = $devToolsPrefs | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($prefsPath, $prefsJson, [System.Text.UTF8Encoding]::new($false))
}

Export-ModuleMember -Function Start-DevToolsBrowser, Wait-DevToolsReady, Set-EdgeDevToolsPreferences
```

#### 5. 統合メインスクリプト

```powershell
<#
.SYNOPSIS
    Claude Code DevTools統合セットアップスクリプト

.PARAMETER Browser
    使用するブラウザ ('edge' または 'chrome')

.PARAMETER Project
    プロジェクト名

.PARAMETER Port
    DevToolsポート (省略時は自動選択)

.PARAMETER NonInteractive
    非対話モード

.PARAMETER DryRun
    ドライランモード (実行せずプレビュー)
#>

[CmdletBinding()]
param(
    [ValidateSet('edge', 'chrome')]
    [string]$Browser,

    [string]$Project,

    [ValidateRange(1024, 65535)]
    [int]$Port,

    [switch]$NonInteractive,
    [switch]$SkipBrowserLaunch,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ===== モジュール読み込み =====
$libDir = Join-Path $PSScriptRoot "..\lib"

. (Join-Path $libDir "Config.ps1")
. (Join-Path $libDir "PortManager.ps1")
. (Join-Path $libDir "UI.ps1")
. (Join-Path $libDir "BrowserManager.ps1")
. (Join-Path $libDir "ScriptGenerator.ps1")
. (Join-Path $libDir "RemoteSetup.ps1")
. (Join-Path $libDir "SSHHelper.ps1")
. (Join-Path $libDir "ErrorHandler.ps1")

# ===== グローバル状態初期化 =====
Initialize-ErrorHandler

# ===== 設定読み込み =====
$config = Import-ProjectConfig
Register-CleanupContext -LinuxHost $config.linuxHost

# ===== ポート選択 =====
if ($Port) {
    $devToolsPort = $Port
} else {
    $devToolsPort = Get-AvailableDevToolsPort -Ports $config.ports
    if (-not $devToolsPort) {
        throw "利用可能なポートがありません"
    }
}

Register-CleanupContext -Port $devToolsPort

# ===== ブラウザ選択 =====
if (-not $Browser) {
    $Browser = Select-Browser -DefaultBrowser $config.defaultBrowser -NonInteractive:$NonInteractive
}

# ===== プロジェクト選択 =====
$projectObj = Select-Project -ProjectRoot $config.zDrive -ProjectName $Project -NonInteractive:$NonInteractive -ShowMetadata

# ===== SSH事前確認 =====
Test-SSHConnection -LinuxHost $config.linuxHost

# ===== ブラウザ起動 =====
if (-not $SkipBrowserLaunch) {
    $browserInfo = Start-DevToolsBrowser -Browser $Browser -Port $devToolsPort -Config $config
    Register-CleanupContext -BrowserProcess $browserInfo.Process
}

# ===== run-claude.sh生成 =====
$runClaudeScript = New-RunClaudeScript -Config $config -Project $projectObj.Name -Port $devToolsPort
Deploy-RunClaudeScript -Script $runClaudeScript -LinuxHost $config.linuxHost -LinuxBase $config.linuxBase -ProjectName $projectObj.Name

# ===== リモートセットアップ =====
Invoke-RemoteSetup -Config $config -ProjectName $projectObj.Name -Port $devToolsPort

# ===== Claude Code起動 =====
if (-not $DryRun) {
    Connect-ClaudeCode -Config $config -ProjectName $projectObj.Name -Port $devToolsPort
}
```

---

## 移行計画

### Phase 1: lib/ディレクトリ作成とモジュール実装 (2時間)

1. `scripts/lib/` ディレクトリ作成
2. 各モジュールファイル作成
3. 既存コードから機能抽出・リファクタリング

### Phase 2: 統合スクリプト実装 (1時間)

1. `scripts/main/Claude-DevTools.ps1` 作成
2. パラメータ処理実装
3. モジュール連携実装

### Phase 3: テンプレート外部化 (30分)

1. `scripts/templates/` ディレクトリ作成
2. `run-claude.sh.tmpl` 抽出
3. `init-prompt.txt` 抽出

### Phase 4: テスト・検証 (1時間)

1. Edge/Chrome両方で動作確認
2. エラーケーステスト
3. 既存スクリプトとの比較検証

### Phase 5: ドキュメント更新・旧スクリプト削除 (30分)

1. README.md更新
2. start.bat更新
3. 旧スクリプトのアーカイブまたは削除

**合計工数**: 5時間

---

## 期待効果

### 定量的効果

| 指標 | Before | After | 改善 |
|------|--------|-------|------|
| 総行数 | 1617行 (825+792) | ~800行 | 50%削減 |
| 重複コード | 540行 | 0行 | 100%削減 |
| ファイル数 | 2 | 9 | 関心の分離 |
| テストカバレッジ | 0% | 80%+ | モジュール単位テスト可能 |

### 定性的効果

- ✅ **保守性**: 変更が1箇所で済む
- ✅ **テスト容易性**: モジュール単位でテスト可能
- ✅ **拡張性**: Firefox等の追加が容易
- ✅ **可読性**: 各モジュールが単一責務
- ✅ **再利用性**: 他プロジェクトでも利用可能

---

## リスク管理

### 潜在的リスク

1. **既存スクリプトとの互換性** - 既存ユーザーが混乱
2. **テスト不足** - 全パターンのテストが困難
3. **パフォーマンス低下** - モジュール読み込みオーバーヘッド

### 軽減策

1. 旧スクリプトを`scripts/legacy/`に移動して共存
2. 段階的移行 (v1.3.0で新スクリプト導入、v1.4.0で旧削除)
3. パフォーマンスベンチマーク実施

---

## 次のアクション

このモジュール化を実装しますか？

- **Option A**: 完全実装 (推定5時間)
- **Option B**: Phase 1のみ (モジュール作成、2時間)
- **Option C**: Week 4 (UX改善) を先に実施して、モジュール化は後回し

---

**作成者**: Claude Code Opus 4.6
**レビュー**: 未
**承認**: 未
