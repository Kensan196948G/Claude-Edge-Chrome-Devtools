# ============================================================
# ErrorHandler.psm1 - カテゴリ別エラーハンドリングモジュール
# ============================================================

# エラーカテゴリの定義
enum ErrorCategory {
    SSH_CONNECTION          # SSH 接続エラー
    DEVTOOLS_PROTOCOL       # DevTools Protocol エラー
    PORT_CONFLICT           # ポート競合
    CONFIG_INVALID          # 設定ファイルエラー
    DEPENDENCY_MISSING      # 依存関係不足
    BROWSER_LAUNCH          # ブラウザ起動エラー
    MCP_CONNECTION          # MCP サーバー接続エラー
    DRIVE_ACCESS            # ドライブアクセスエラー
    PERMISSION_DENIED       # 権限エラー
    NETWORK_TIMEOUT         # ネットワークタイムアウト
    FILE_SYSTEM             # ファイル/ディレクトリ操作エラー
    PROCESS_MANAGEMENT      # プロセス起動/終了エラー
    CONFIG_MISMATCH         # config.json と実態の不整合
    LOG_OPERATION           # ログ書き込み/ローテーションエラー
    SCRIPT_GENERATION       # run-claude.sh 生成エラー
    TMUX_SESSION            # tmux セッション操作エラー
    UNKNOWN                 # 未分類エラー
}

# カテゴリごとの絵文字
$script:CategoryEmoji = @{
    SSH_CONNECTION = "🔐"
    DEVTOOLS_PROTOCOL = "🌐"
    PORT_CONFLICT = "⚠️"
    CONFIG_INVALID = "⚙️"
    DEPENDENCY_MISSING = "📦"
    BROWSER_LAUNCH = "🚀"
    MCP_CONNECTION = "🔌"
    DRIVE_ACCESS = "💾"
    PERMISSION_DENIED = "🚫"
    NETWORK_TIMEOUT = "⏱️"
    FILE_SYSTEM = "📄"
    PROCESS_MANAGEMENT = "⚡"
    CONFIG_MISMATCH = "🔀"
    LOG_OPERATION = "📝"
    SCRIPT_GENERATION = "🔧"
    TMUX_SESSION = "🖥️"
    UNKNOWN = "❓"
}

# カテゴリごとの推奨アクション
$script:CategorySolutions = @{
    SSH_CONNECTION = @(
        "1. SSH 鍵の権限を確認: icacls ~/.ssh/id_ed25519",
        "2. ~/.ssh/config の設定を確認",
        "3. ホストへの疎通確認: ping <hostname>",
        "4. 詳細ログ確認: ssh -vvv <hostname>"
    )
    DEVTOOLS_PROTOCOL = @(
        "1. ブラウザが起動しているか確認",
        "2. DevTools エンドポイント確認: curl http://localhost:<port>/json/version",
        "3. ブラウザを再起動してください",
        "4. ポート番号が正しいか確認（9222-9229）"
    )
    PORT_CONFLICT = @(
        "1. 既存プロセスを終了: Get-Process | Where-Object {`$_.Name -match 'msedge|chrome'}",
        "2. または別のポートを使用: config.json の ports 配列を編集",
        "3. ポート使用状況確認: Get-NetTCPConnection -LocalPort <port>"
    )
    CONFIG_INVALID = @(
        "1. config.json の JSON 構文を確認",
        "2. 必須フィールドが存在するか確認: ports, zDrive, linuxHost, linuxBase",
        "3. config.json.template と比較して不足項目を確認"
    )
    DEPENDENCY_MISSING = @(
        "1. 不足しているコマンドをインストール",
        "2. Linux: jq, curl, fuser, git をインストール",
        "3. Windows: PowerShell 7, SSH client をインストール"
    )
    BROWSER_LAUNCH = @(
        "1. ブラウザがインストールされているか確認",
        "2. ブラウザのパスが正しいか確認: config.json の edgeExe/chromeExe",
        "3. すべてのブラウザウィンドウを閉じてから再実行"
    )
    MCP_CONNECTION = @(
        "1. .mcp.json が存在するか確認",
        "2. npx コマンドがインストールされているか確認: npx --version",
        "3. MCP セットアップを再実行: bash scripts/mcp/setup-mcp.sh"
    )
    DRIVE_ACCESS = @(
        "1. ドライブ診断を実行: start.bat → オプション 8",
        "2. config.json に zDriveUncPath を設定",
        "3. UNC パスへの直接アクセスを確認: Test-Path '\\\\server\\share'"
    )
    PERMISSION_DENIED = @(
        "1. 管理者権限で PowerShell を起動",
        "2. ファイル/ディレクトリの権限を確認",
        "3. Windows Defender や アンチウイルスの除外設定を確認"
    )
    NETWORK_TIMEOUT = @(
        "1. ネットワーク接続を確認: ping <hostname>",
        "2. ファイアウォール設定を確認（ポート 22, 9222-9229）",
        "3. タイムアウト値を増やす: ConnectTimeout=10"
    )
    FILE_SYSTEM = @(
        "1. ファイル/ディレクトリの存在を確認",
        "2. ディスク容量を確認: Get-PSDrive",
        "3. ファイルがロックされていないか確認"
    )
    PROCESS_MANAGEMENT = @(
        "1. プロセスの状態を確認: Get-Process",
        "2. 管理者権限で実行してください",
        "3. タスクマネージャーで手動終了を試行"
    )
    CONFIG_MISMATCH = @(
        "1. config.json の設定値と実際の環境を比較",
        "2. config.json を最新テンプレートと照合",
        "3. 設定を再生成: config.json.template を参照"
    )
    LOG_OPERATION = @(
        "1. ログディレクトリの書き込み権限を確認",
        "2. ディスク容量を確認",
        "3. logging.enabled = false で一時的にログを無効化"
    )
    SCRIPT_GENERATION = @(
        "1. ScriptGenerator.psm1 が正しく読み込まれているか確認",
        "2. 必須パラメータ (Port, LinuxBase, ProjectName) を確認",
        "3. テンプレートファイルの存在を確認"
    )
    TMUX_SESSION = @(
        "1. tmux がインストールされているか確認: tmux -V",
        "2. 既存セッションを確認: tmux ls",
        "3. tmux を無効化: config.json の tmux.enabled = false"
    )
    UNKNOWN = @(
        "1. エラーメッセージの詳細を確認",
        "2. ログファイルを確認",
        "3. 問題が再現するか確認してください"
    )
}

<#
.SYNOPSIS
    カテゴリ別のエラーメッセージを表示

.DESCRIPTION
    エラーをカテゴリごとに分類し、適切な絵文字・色・推奨アクションと共に表示

.PARAMETER Category
    エラーカテゴリ（ErrorCategory enum）

.PARAMETER Message
    エラーメッセージ

.PARAMETER Details
    エラーの詳細情報（オプション）

.PARAMETER ThrowAfter
    表示後に例外をスローするか（デフォルト: $true）

.EXAMPLE
    Show-CategorizedError -Category SSH_CONNECTION -Message "SSH接続がタイムアウトしました"

.EXAMPLE
    Show-CategorizedError -Category PORT_CONFLICT -Message "ポート 9222 は既に使用中です" -Details @{Port=9222; Process="chrome.exe"}
#>
function Show-CategorizedError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ErrorCategory]$Category,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [hashtable]$Details = @{},

        [Parameter(Mandatory=$false)]
        [bool]$ThrowAfter = $true
    )

    $emoji = $script:CategoryEmoji[$Category]
    $solutions = $script:CategorySolutions[$Category]

    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host "$emoji エラーカテゴリ: $Category" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Red

    Write-Host "❌ $Message`n" -ForegroundColor Red

    # 詳細情報（オプション）
    if ($Details.Count -gt 0) {
        Write-Host "📋 詳細情報:" -ForegroundColor Yellow
        foreach ($key in $Details.Keys) {
            Write-Host "   $key : $($Details[$key])" -ForegroundColor White
        }
        Write-Host ""
    }

    # 推奨アクション
    Write-Host "💡 推奨アクション:" -ForegroundColor Cyan
    foreach ($solution in $solutions) {
        Write-Host "   $solution" -ForegroundColor White
    }
    Write-Host ""

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Red

    if ($ThrowAfter) {
        throw $Message
    }
}

<#
.SYNOPSIS
    エラーメッセージから自動的にカテゴリを推定

.DESCRIPTION
    エラーメッセージのキーワードからカテゴリを自動判定

.PARAMETER ErrorMessage
    エラーメッセージ

.EXAMPLE
    $category = Get-ErrorCategory -ErrorMessage "SSH接続がタイムアウトしました"
    # → ErrorCategory::SSH_CONNECTION
#>
function Get-ErrorCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage
    )

    $message = $ErrorMessage.ToLower()

    # キーワードベースの分類
    if ($message -match "ssh|authorized|authentication|connection refused") {
        return [ErrorCategory]::SSH_CONNECTION
    }
    elseif ($message -match "devtools|websocket|protocol|/json") {
        return [ErrorCategory]::DEVTOOLS_PROTOCOL
    }
    elseif ($message -match "port.*already|port.*in use|port.*conflict|listening") {
        return [ErrorCategory]::PORT_CONFLICT
    }
    elseif ($message -match "config\.json|invalid json|parse error|schema") {
        return [ErrorCategory]::CONFIG_INVALID
    }
    elseif ($message -match "command not found|not installed|jq|curl|npx") {
        return [ErrorCategory]::DEPENDENCY_MISSING
    }
    elseif ($message -match "browser|msedge|chrome|firefox") {
        return [ErrorCategory]::BROWSER_LAUNCH
    }
    elseif ($message -match "mcp|\.mcp\.json") {
        return [ErrorCategory]::MCP_CONNECTION
    }
    elseif ($message -match "drive|unc path|network|x:\\|z:\\") {
        return [ErrorCategory]::DRIVE_ACCESS
    }
    elseif ($message -match "permission|access.*denied|unauthorized|forbidden") {
        return [ErrorCategory]::PERMISSION_DENIED
    }
    elseif ($message -match "timeout|timed out|unreachable") {
        return [ErrorCategory]::NETWORK_TIMEOUT
    }
    elseif ($message -match "file|directory|folder|write.*fail|read.*fail|path.*not") {
        return [ErrorCategory]::FILE_SYSTEM
    }
    elseif ($message -match "process|kill|stop-process|start-process|pid") {
        return [ErrorCategory]::PROCESS_MANAGEMENT
    }
    elseif ($message -match "mismatch|inconsistent|out of sync") {
        return [ErrorCategory]::CONFIG_MISMATCH
    }
    elseif ($message -match "log|transcript|rotation|archive.*log") {
        return [ErrorCategory]::LOG_OPERATION
    }
    elseif ($message -match "run-claude|script.*gen|generate.*script") {
        return [ErrorCategory]::SCRIPT_GENERATION
    }
    elseif ($message -match "tmux|session.*create|pane") {
        return [ErrorCategory]::TMUX_SESSION
    }
    else {
        return [ErrorCategory]::UNKNOWN
    }
}

<#
.SYNOPSIS
    簡易エラー表示（カテゴリ自動判定）

.DESCRIPTION
    エラーメッセージから自動的にカテゴリを判定して表示

.PARAMETER Message
    エラーメッセージ

.PARAMETER ThrowAfter
    表示後に例外をスローするか

.EXAMPLE
    Show-Error "SSH接続がタイムアウトしました"
    # → 自動的に SSH_CONNECTION カテゴリと判定して表示
#>
function Show-Error {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [hashtable]$Details = @{},

        [Parameter(Mandatory=$false)]
        [bool]$ThrowAfter = $true
    )

    $category = Get-ErrorCategory -ErrorMessage $Message

    Show-CategorizedError -Category $category -Message $Message -Details $Details -ThrowAfter $ThrowAfter
}

# モジュールのエクスポート
Export-ModuleMember -Function @(
    'Show-CategorizedError',
    'Get-ErrorCategory',
    'Show-Error'
)
