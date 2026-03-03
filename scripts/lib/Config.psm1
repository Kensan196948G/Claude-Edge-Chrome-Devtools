# ============================================================
# Config.psm1 - 設定管理モジュール
# Claude-EdgeChromeDevTools v1.3.0
# ============================================================

# 必須フィールドの定義
$script:RequiredFields = @('ports', 'zDrive', 'linuxHost', 'linuxBase')

# ポートの有効範囲
$script:PortMin = 1024
$script:PortMax = 65535

<#
.SYNOPSIS
    config.jsonを読み込んで検証

.DESCRIPTION
    指定されたパスからconfig.jsonを読み込み、必須フィールドの存在確認と
    ポート範囲の検証を行う。検証失敗時は例外をスローする。

.PARAMETER ConfigPath
    config.jsonのファイルパス

.EXAMPLE
    $config = Import-DevToolsConfig -ConfigPath ".\config\config.json"
#>
function Import-DevToolsConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )

    # ファイル存在確認
    if (-not (Test-Path $ConfigPath)) {
        throw "設定ファイルが見つかりません: $ConfigPath"
    }

    # JSON読み込み
    try {
        $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $config = $content | ConvertFrom-Json
        Write-Host "⚙️  設定ファイル読み込み: $ConfigPath" -ForegroundColor Cyan
    }
    catch {
        throw "config.jsonのJSONパースに失敗しました: $_"
    }

    # 必須フィールド検証
    foreach ($field in $script:RequiredFields) {
        $value = $config.$field
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
            throw "config.jsonに必須フィールドがありません: '$field'"
        }
    }
    Write-Host "✅ 必須フィールド検証OK" -ForegroundColor Green

    # ポート配列の検証
    if ($null -eq $config.ports -or $config.ports.Count -eq 0) {
        throw "config.jsonの 'ports' が空またはnullです"
    }

    foreach ($port in $config.ports) {
        if ($port -lt $script:PortMin -or $port -gt $script:PortMax) {
            throw "ポート番号が有効範囲外です: $port (有効範囲: $($script:PortMin)-$($script:PortMax))"
        }
    }
    Write-Host "✅ ポート範囲検証OK ($($config.ports.Count) ポート)" -ForegroundColor Green

    # initPromptFile の検証（オプション）
    if ($null -ne $config.initPromptFile -and -not [string]::IsNullOrWhiteSpace($config.initPromptFile)) {
        if (-not (Test-Path $config.initPromptFile)) {
            Write-Warning "initPromptFile が見つかりません: $($config.initPromptFile) (スキップして続行)"
        } else {
            Write-Host "✅ initPromptFile 検証OK: $($config.initPromptFile)" -ForegroundColor Green
        }
    }

    # tmux 設定のスキーマ検証（オプション）
    if ($null -ne $config.tmux) {
        $tmuxValidLayouts = @('auto', 'default', 'review-team', 'fullstack-dev-team', 'debug-team')
        if ($null -ne $config.tmux.defaultLayout -and
            $tmuxValidLayouts -notcontains $config.tmux.defaultLayout) {
            Write-Warning "tmux.defaultLayout が無効な値です: '$($config.tmux.defaultLayout)' (有効値: $($tmuxValidLayouts -join ', '))"
        }
        if ($null -ne $config.tmux.enabled -and $config.tmux.enabled -isnot [bool]) {
            Write-Warning "tmux.enabled はブール値である必要があります: '$($config.tmux.enabled)'"
        }
        Write-Host "✅ tmux 設定スキーマ検証OK" -ForegroundColor Green
    }

    return $config
}

<#
.SYNOPSIS
    タイムスタンプ付きバックアップを作成

.DESCRIPTION
    設定ファイルをタイムスタンプ付きでバックアップする。
    機密情報のマスキングと最大バックアップ数の管理を行う。

.PARAMETER ConfigPath
    バックアップ元のファイルパス

.PARAMETER BackupDir
    バックアップ先ディレクトリ

.PARAMETER MaxBackups
    保持する最大バックアップ数（デフォルト: 10）

.PARAMETER MaskSensitive
    機密情報をマスクするか（デフォルト: $true）

.PARAMETER SensitiveKeys
    マスクするキーのリスト（例: @('mcp.githubToken', 'mcp.braveApiKey')）

.EXAMPLE
    Backup-ConfigFile -ConfigPath ".\config\config.json" -BackupDir ".\config\backups"
#>
function Backup-ConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath,

        [Parameter(Mandatory=$true)]
        [string]$BackupDir,

        [Parameter(Mandatory=$false)]
        [int]$MaxBackups = 10,

        [Parameter(Mandatory=$false)]
        [bool]$MaskSensitive = $true,

        [Parameter(Mandatory=$false)]
        [string[]]$SensitiveKeys = @()
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "バックアップ元ファイルが見つかりません: $ConfigPath"
        return
    }

    # バックアップディレクトリ作成
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }

    # タイムスタンプ付きファイル名
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
    $ext = [System.IO.Path]::GetExtension($ConfigPath)
    $backupFile = Join-Path $BackupDir "${baseName}_${timestamp}${ext}"

    try {
        $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8

        # 機密情報のマスキング
        if ($MaskSensitive -and $SensitiveKeys.Count -gt 0) {
            try {
                $json = $content | ConvertFrom-Json
                foreach ($keyPath in $SensitiveKeys) {
                    $parts = $keyPath -split '\.'
                    $obj = $json
                    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
                        if ($null -ne $obj.($parts[$i])) {
                            $obj = $obj.($parts[$i])
                        }
                    }
                    $lastKey = $parts[-1]
                    if ($null -ne $obj -and $null -ne $obj.$lastKey -and $obj.$lastKey -ne "") {
                        $obj.$lastKey = "***MASKED***"
                    }
                }
                $content = $json | ConvertTo-Json -Depth 10
            }
            catch {
                Write-Warning "機密情報マスキング中にエラー（マスクなしでバックアップ）: $_"
            }
        }

        Set-Content -Path $backupFile -Value $content -Encoding UTF8
        Write-Host "💾 設定バックアップ作成: $backupFile" -ForegroundColor Cyan

        # 古いバックアップを削除（MaxBackupsを超えた分）
        $pattern = "${baseName}_*${ext}"
        $backups = Get-ChildItem -Path $BackupDir -Filter $pattern | Sort-Object LastWriteTime -Descending
        if ($backups.Count -gt $MaxBackups) {
            $toDelete = $backups | Select-Object -Skip $MaxBackups
            foreach ($old in $toDelete) {
                Remove-Item -Path $old.FullName -Force
                Write-Host "🗑️  古いバックアップ削除: $($old.Name)" -ForegroundColor DarkGray
            }
        }
    }
    catch {
        Write-Warning "バックアップ作成中にエラーが発生しました: $_"
    }
}

<#
.SYNOPSIS
    最近使用プロジェクト履歴を取得

.DESCRIPTION
    JSONファイルから最近使用したプロジェクトのリストを読み込む。
    ファイルが存在しない場合は空の配列を返す。

.PARAMETER HistoryPath
    履歴ファイルのパス（%USERPROFILE% などの環境変数を展開する）

.EXAMPLE
    $recent = Get-RecentProjects -HistoryPath "%USERPROFILE%\.claude\recent-projects.json"
#>
function Get-RecentProjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath
    )

    # 環境変数を展開
    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($HistoryPath)

    if (-not (Test-Path $expandedPath)) {
        return @()
    }

    try {
        $content = Get-Content -Path $expandedPath -Raw -Encoding UTF8
        $data = $content | ConvertFrom-Json

        if ($null -eq $data -or $null -eq $data.projects) {
            return @()
        }

        return @($data.projects)
    }
    catch {
        Write-Warning "最近使用プロジェクト履歴の読み込みに失敗しました: $_"
        return @()
    }
}

<#
.SYNOPSIS
    最近使用プロジェクト履歴を更新

.DESCRIPTION
    指定されたプロジェクトを履歴の先頭に追加する。
    重複は削除し、MaxHistoryを超えた古いエントリは削除する。

.PARAMETER ProjectName
    追加するプロジェクト名

.PARAMETER HistoryPath
    履歴ファイルのパス（%USERPROFILE% などの環境変数を展開する）

.PARAMETER MaxHistory
    保持する最大履歴数（デフォルト: 10）

.EXAMPLE
    Update-RecentProjects -ProjectName "MyProject" -HistoryPath "%USERPROFILE%\.claude\recent-projects.json"
#>
function Update-RecentProjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectName,

        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,

        [Parameter(Mandatory=$false)]
        [int]$MaxHistory = 10
    )

    # 環境変数を展開
    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($HistoryPath)

    # ディレクトリ作成
    $dir = Split-Path $expandedPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # 既存履歴を読み込み
    $projects = [System.Collections.Generic.List[string]]::new()
    $existing = Get-RecentProjects -HistoryPath $HistoryPath
    foreach ($p in $existing) {
        if ($p -ne $ProjectName) {
            $projects.Add($p)
        }
    }

    # 先頭に追加
    $projects.Insert(0, $ProjectName)

    # MaxHistoryに切り詰め
    if ($projects.Count -gt $MaxHistory) {
        $projects = [System.Collections.Generic.List[string]]($projects | Select-Object -First $MaxHistory)
    }

    # JSONとして保存
    try {
        $data = @{ projects = @($projects) }
        $json = $data | ConvertTo-Json -Depth 3
        Set-Content -Path $expandedPath -Value $json -Encoding UTF8
        Write-Host "📝 最近使用プロジェクト更新: $ProjectName" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "最近使用プロジェクト履歴の保存に失敗しました: $_"
    }
}

<#
.SYNOPSIS
    MCP サーバーの可用性を検証
.DESCRIPTION
    config.json の mcp.requiredServers と .mcp.json を比較し、
    不足しているサーバーやトークン形式の問題を報告する。
.PARAMETER Config
    config.json から読み込んだ設定オブジェクト
.PARAMETER ProjectRoot
    プロジェクトルートディレクトリ (.mcp.json の存在場所)
.EXAMPLE
    $result = Test-McpServerAvailability -Config $Config -ProjectRoot "X:\MyProject"
#>
function Test-McpServerAvailability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$Config,

        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot
    )

    $result = @{
        Available = @()
        Missing   = @()
        Warnings  = @()
    }

    if ($null -eq $Config.mcp -or $Config.mcp.enabled -ne $true) {
        return $result
    }

    $mcpConfig = $Config.mcp
    $mcpJsonPath = Join-Path $ProjectRoot '.mcp.json'

    # .mcp.json 読み込み
    $mcpServers = @{}
    if (Test-Path $mcpJsonPath) {
        try {
            $mcpContent = Get-Content -Path $mcpJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $mcpContent.mcpServers) {
                foreach ($prop in $mcpContent.mcpServers.PSObject.Properties) {
                    $mcpServers[$prop.Name] = $true
                }
            }
        } catch {
            $result.Warnings += ".mcp.json のパースに失敗しました: $_"
        }
    }

    # 必須サーバー検証
    if ($null -ne $mcpConfig.requiredServers) {
        foreach ($server in $mcpConfig.requiredServers) {
            if ($mcpServers.ContainsKey($server)) {
                $result.Available += $server
            } else {
                $result.Missing += $server
            }
        }
    }

    # トークン形式検証
    if ($null -ne $mcpConfig.githubToken -and $mcpConfig.githubToken -ne '') {
        $token = $mcpConfig.githubToken
        if ($token -notmatch '^(ghp_|github_pat_)') {
            $result.Warnings += "githubToken の形式が不正です (ghp_ または github_pat_ プレフィックスが必要)"
        }
    }

    return $result
}

# モジュールのエクスポート
Export-ModuleMember -Function @(
    'Import-DevToolsConfig',
    'Backup-ConfigFile',
    'Get-RecentProjects',
    'Update-RecentProjects',
    'Test-McpServerAvailability'
)
