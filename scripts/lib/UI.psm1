# ============================================================
# UI.psm1 - ユーザーインターフェースモジュール
# Claude-EdgeChromeDevTools v1.3.0
# ============================================================

<#
.SYNOPSIS
    ブラウザ選択UI

.DESCRIPTION
    対話的なブラウザ選択UIを表示する。
    入力検証を行い、無効な入力は再入力を促す。

.PARAMETER DefaultBrowser
    デフォルトのブラウザ（"edge" または "chrome"、デフォルト: "edge"）

.EXAMPLE
    $browser = Select-Browser -DefaultBrowser "edge"
    Write-Host "選択: $($browser.Name)"
#>
function Select-Browser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$DefaultBrowser = "edge",

        [Parameter(Mandatory=$false)]
        [string]$EdgeExe = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",

        [Parameter(Mandatory=$false)]
        [string]$ChromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    )

    $browsers = @{
        "1" = @{ Name = "Microsoft Edge"; Exe = $EdgeExe;   Type = "edge" }
        "2" = @{ Name = "Google Chrome";  Exe = $ChromeExe; Type = "chrome" }
    }

    # デフォルト番号を決定
    $defaultNum = if ($DefaultBrowser -eq "chrome") { "2" } else { "1" }

    Write-Host "`n🌐 ブラウザを選択してください:" -ForegroundColor Cyan
    Write-Host "   1) Microsoft Edge" -ForegroundColor White
    Write-Host "   2) Google Chrome" -ForegroundColor White
    Write-Host ""

    while ($true) {
        $input = Read-Host "番号を入力 [デフォルト: $defaultNum ($($browsers[$defaultNum].Name))]"

        # 空入力はデフォルト使用
        if ([string]::IsNullOrWhiteSpace($input)) {
            $input = $defaultNum
        }

        $input = $input.Trim()

        if ($browsers.ContainsKey($input)) {
            $selected = $browsers[$input]
            Write-Host "✅ 選択: $($selected.Name)" -ForegroundColor Green
            return $selected
        }
        else {
            Write-Host "⚠️  無効な入力です。1 または 2 を入力してください。" -ForegroundColor Yellow
        }
    }
}

<#
.SYNOPSIS
    プロジェクト選択UI

.DESCRIPTION
    指定されたルートパス内のディレクトリを一覧表示し、
    ユーザーにプロジェクトを選択させる。
    最近使用したプロジェクトには ⭐ マークを付ける。

.PARAMETER ProjectRootPath
    プロジェクトが格納されているルートディレクトリ

.PARAMETER RecentProjects
    最近使用したプロジェクト名のリスト

.EXAMPLE
    $project = Select-Project -ProjectRootPath "X:\" -RecentProjects @("MyApp", "WebProject")
    Write-Host "選択: $($project.Name)"
#>
function Select-Project {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRootPath,

        [Parameter(Mandatory=$false)]
        $Projects = $null,

        [Parameter(Mandatory=$false)]
        [string[]]$RecentProjects = @()
    )

    if (-not (Test-Path $ProjectRootPath)) {
        throw "プロジェクトルートパスが見つかりません: $ProjectRootPath"
    }

    # ディレクトリ一覧取得（引数で指定されていなければ取得）
    $dirs = if ($null -ne $Projects) {
        $Projects
    } else {
        Get-ChildItem -Path $ProjectRootPath -Directory -ErrorAction Stop |
            Where-Object { -not $_.Name.StartsWith('.') } |
            Sort-Object Name
    }

    if ($dirs.Count -eq 0) {
        throw "プロジェクトディレクトリが見つかりません: $ProjectRootPath"
    }

    Write-Host "`n📁 プロジェクトを選択してください:" -ForegroundColor Cyan
    Write-Host "   (⭐ = 最近使用)" -ForegroundColor DarkGray
    Write-Host ""

    $i = 1
    $indexedDirs = @()

    # 最近使用プロジェクトを先頭にソート
    $recentSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $RecentProjects) { $recentSet.Add($r) | Out-Null }

    $sorted = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    foreach ($name in $RecentProjects) {
        $match = $dirs | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($match) { $sorted.Add($match) }
    }
    foreach ($dir in $dirs) {
        if (-not $recentSet.Contains($dir.Name)) {
            $sorted.Add($dir)
        }
    }

    foreach ($dir in $sorted) {
        $star = if ($recentSet.Contains($dir.Name)) { "⭐ " } else { "   " }
        $numStr = "$i".PadLeft(3)
        Write-Host "$numStr) $star$($dir.Name)" -ForegroundColor White
        $indexedDirs += $dir
        $i++
    }

    Write-Host ""

    while ($true) {
        $input = Read-Host "番号を入力 (1-$($indexedDirs.Count))"

        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Host "⚠️  番号を入力してください。" -ForegroundColor Yellow
            continue
        }

        $num = 0
        if ([int]::TryParse($input.Trim(), [ref]$num) -and $num -ge 1 -and $num -le $indexedDirs.Count) {
            $selected = $indexedDirs[$num - 1]
            Write-Host "✅ 選択: $($selected.Name)" -ForegroundColor Green
            return $selected
        }
        else {
            Write-Host "⚠️  1 から $($indexedDirs.Count) の番号を入力してください。" -ForegroundColor Yellow
        }
    }
}

<#
.SYNOPSIS
    ドライブレター→UNCパスへのフォールバック解決

.DESCRIPTION
    ドライブレターパスへのアクセスを試み、失敗した場合はUNCパスにフォールバックする。
    確実にアクセス可能なパスを返す。

.PARAMETER ZRoot
    Zドライブのルートパス（例: "X:\"）

.PARAMETER ZUncPath
    UNCパス（例: "\\server\share"）。省略可能。

.EXAMPLE
    $path = Resolve-ProjectRootPath -ZRoot "X:\" -ZUncPath "\\kensan1969\LinuxHDD"
#>
function Resolve-ProjectRootPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ZRoot,

        [Parameter(Mandatory=$false)]
        [string]$ZUncPath = ""
    )

    # ドライブレターパスを試みる
    if (Test-Path $ZRoot) {
        Write-Host "✅ ドライブパスアクセス成功: $ZRoot" -ForegroundColor Green
        return $ZRoot
    }

    Write-Warning "⚠️  ドライブパスへのアクセス失敗: $ZRoot"

    # UNCパスにフォールバック
    if (-not [string]::IsNullOrWhiteSpace($ZUncPath)) {
        Write-Host "🔄 UNCパスでアクセスを試みます: $ZUncPath" -ForegroundColor Yellow

        if (Test-Path $ZUncPath) {
            Write-Host "✅ UNCパスアクセス成功: $ZUncPath" -ForegroundColor Green
            return $ZUncPath
        }
        else {
            throw "ドライブパスとUNCパスの両方にアクセスできません。`n  ドライブ: $ZRoot`n  UNC: $ZUncPath`n`n💡 ドライブのマッピングを確認するか、config.jsonのzDriveUncPathを設定してください。"
        }
    }

    throw "プロジェクトルートパスにアクセスできません: $ZRoot`n`n💡 ドライブがマッピングされているか確認してください。`n   またはconfig.jsonにzDriveUncPathを設定してください。"
}

# モジュールのエクスポート
Export-ModuleMember -Function @(
    'Select-Browser',
    'Select-Project',
    'Resolve-ProjectRootPath'
)
