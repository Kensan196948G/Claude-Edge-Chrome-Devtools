# ============================================================
# test-drive-mapping.ps1
# X:\ ドライブマッピング診断スクリプト
# ============================================================

$ErrorActionPreference = "Continue"  # エラーでも継続

# config.json から設定読み込み
$RootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConfigPath = Join-Path $RootDir "config\config.json"

if (Test-Path $ConfigPath) {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $driveLetter = ($Config.zDrive -replace '[:\\]', '')
    $configUncPath = $Config.zDriveUncPath
} else {
    Write-Host "⚠️  config.json が見つかりません。デフォルト値で診断します。" -ForegroundColor Yellow
    $driveLetter = "X"
    $configUncPath = $null
}

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "🔍 ドライブマッピング診断: ${driveLetter}:\" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$results = @{
    directAccess = $false
    registry = $null
    smbMapping = $null
    psDrive = $null
    configUnc = $null
}

# ============================================================
# 1. ドライブレター直接アクセステスト
# ============================================================
Write-Host "[1] ドライブレター直接アクセステスト" -ForegroundColor Yellow
Write-Host "    Test-Path ${driveLetter}:\" -ForegroundColor Gray

if (Test-Path "${driveLetter}:\") {
    Write-Host "    ✅ ${driveLetter}:\ は直接アクセス可能" -ForegroundColor Green
    $results.directAccess = $true

    # ディレクトリ数を表示
    $dirCount = (Get-ChildItem "${driveLetter}:\" -Directory -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "    📁 ディレクトリ数: $dirCount" -ForegroundColor Gray
} else {
    Write-Host "    ❌ ${driveLetter}:\ は直接アクセス不可" -ForegroundColor Red
}

# ============================================================
# 2. レジストリ確認
# ============================================================
Write-Host "`n[2] レジストリ (HKCU:\Network\${driveLetter})" -ForegroundColor Yellow

$regPath = "HKCU:\Network\${driveLetter}"
if (Test-Path $regPath) {
    $remotePath = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).RemotePath
    if ($remotePath) {
        Write-Host "    ✅ UNC パス: $remotePath" -ForegroundColor Green
        $results.registry = $remotePath
    } else {
        Write-Host "    ⚠️  レジストリエントリはあるが RemotePath なし" -ForegroundColor Yellow
    }
} else {
    Write-Host "    ❌ レジストリエントリなし" -ForegroundColor Red
}

# ============================================================
# 3. SMB マッピング確認
# ============================================================
Write-Host "`n[3] SMB マッピング" -ForegroundColor Yellow

$smbMapping = Get-SmbMapping -ErrorAction SilentlyContinue | Where-Object LocalPath -eq "${driveLetter}:"
if ($smbMapping) {
    Write-Host "    ✅ UNC パス: $($smbMapping.RemotePath)" -ForegroundColor Green
    Write-Host "    📊 ステータス: $($smbMapping.Status)" -ForegroundColor Gray
    $results.smbMapping = $smbMapping.RemotePath
} else {
    Write-Host "    ❌ SMB マッピングなし" -ForegroundColor Red
}

# ============================================================
# 4. PSDrive 確認
# ============================================================
Write-Host "`n[4] PSDrive" -ForegroundColor Yellow

$psDrive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
if ($psDrive) {
    Write-Host "    ✅ Provider: $($psDrive.Provider)" -ForegroundColor Green
    Write-Host "    📁 Root: $($psDrive.Root)" -ForegroundColor Gray
    if ($psDrive.DisplayRoot) {
        Write-Host "    🌐 DisplayRoot: $($psDrive.DisplayRoot)" -ForegroundColor Gray
        $results.psDrive = $psDrive.DisplayRoot
    }
} else {
    Write-Host "    ❌ PSDrive なし" -ForegroundColor Red
}

# ============================================================
# 5. Net Use 確認（CMD経由）
# ============================================================
Write-Host "`n[5] Net Use (CMD)" -ForegroundColor Yellow

$netUse = net use 2>&1 | Select-String "${driveLetter}:"
if ($netUse) {
    Write-Host "    ✅ $netUse" -ForegroundColor Green
} else {
    Write-Host "    ❌ Net Use にエントリなし" -ForegroundColor Red
}

# ============================================================
# 6. config.json の zDriveUncPath 確認
# ============================================================
Write-Host "`n[6] config.json の zDriveUncPath" -ForegroundColor Yellow

if ($configUncPath) {
    Write-Host "    ✅ 設定値: $configUncPath" -ForegroundColor Green
    $results.configUnc = $configUncPath

    if (Test-Path $configUncPath) {
        Write-Host "    ✅ UNC パス直接アクセス成功" -ForegroundColor Green
    } else {
        Write-Host "    ❌ UNC パス直接アクセス失敗" -ForegroundColor Red
    }
} else {
    Write-Host "    ❌ config.json に zDriveUncPath が設定されていません" -ForegroundColor Red
}

# ============================================================
# 7. 診断結果サマリー
# ============================================================
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 診断結果サマリー" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

Write-Host "検出された UNC パス:" -ForegroundColor Yellow
$uncPaths = @()
if ($results.registry) { $uncPaths += "Registry: $($results.registry)" }
if ($results.smbMapping) { $uncPaths += "SMB: $($results.smbMapping)" }
if ($results.psDrive) { $uncPaths += "PSDrive: $($results.psDrive)" }
if ($results.configUnc) { $uncPaths += "config.json: $($results.configUnc)" }

if ($uncPaths.Count -gt 0) {
    foreach ($path in $uncPaths) {
        Write-Host "  • $path" -ForegroundColor White
    }
} else {
    Write-Host "  ❌ UNC パスが検出されませんでした" -ForegroundColor Red
}

Write-Host ""
Write-Host "推奨アクション:" -ForegroundColor Yellow

if ($results.directAccess) {
    Write-Host "  ✅ ${driveLetter}:\ は直接アクセス可能です。問題ありません。" -ForegroundColor Green
} elseif ($uncPaths.Count -gt 0) {
    Write-Host "  ⚠️  ${driveLetter}:\ は直接アクセスできませんが、UNC パスが検出されました。" -ForegroundColor Yellow
    Write-Host "     スクリプトは自動的に UNC パス経由でアクセスします。" -ForegroundColor White
    Write-Host ""
    Write-Host "  💡 永続的なドライブマッピングを作成する場合:" -ForegroundColor Cyan
    Write-Host "     New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root '$($uncPaths[0].Split(': ')[1])' -Persist" -ForegroundColor White
} else {
    Write-Host "  ❌ ドライブマッピングが見つかりません。" -ForegroundColor Red
    Write-Host ""
    Write-Host "  💡 対処方法:" -ForegroundColor Cyan
    Write-Host "     1. Windows Explorer でネットワークドライブを割り当て" -ForegroundColor White
    Write-Host "     2. または PowerShell で手動マッピング:" -ForegroundColor White
    Write-Host "        New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root '\\\\server\\share' -Persist" -ForegroundColor White
    Write-Host "     3. config.json に zDriveUncPath を設定" -ForegroundColor White
}

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "診断完了" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
