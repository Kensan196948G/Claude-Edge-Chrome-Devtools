# ============================================================
# PortManager.psm1 - ポート管理モジュール
# Claude-EdgeChromeDevTools v1.3.0
# ============================================================

<#
.SYNOPSIS
    使用可能なポートを検索

.DESCRIPTION
    指定されたポートリストから、現在使用中でない最初のポートを返す。
    すべて使用中の場合は $null を返す。

.PARAMETER Ports
    検索するポート番号の配列

.EXAMPLE
    $port = Get-AvailablePort -Ports @(9222, 9223, 9224)
    if ($null -eq $port) { Write-Warning "空きポートなし" }
#>
function Get-AvailablePort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int[]]$Ports
    )

    foreach ($port in $Ports) {
        if (Test-PortAvailable -Port $port) {
            Write-Host "✅ 利用可能ポート検出: $port" -ForegroundColor Green
            return $port
        }
        else {
            Write-Host "⚠️  ポート $port は使用中" -ForegroundColor Yellow
        }
    }

    Write-Warning "❌ 利用可能なポートが見つかりませんでした (検索済み: $($Ports -join ', '))"
    return $null
}

<#
.SYNOPSIS
    ポートが使用可能か確認

.DESCRIPTION
    指定されたポートが現在リッスン中でないことを確認する。
    Get-NetTCPConnection を使用してローカルポートの状態を確認する。

.PARAMETER Port
    確認するポート番号

.EXAMPLE
    if (Test-PortAvailable -Port 9222) {
        Write-Host "ポート 9222 は空きです"
    }
#>
function Test-PortAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port
    )

    try {
        # Get-NetTCPConnection でリッスン中のポートを確認
        $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($connections) {
            return $false
        }

        # TimeWait等の接続も確認
        $anyConnections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($anyConnections) {
            return $false
        }

        return $true
    }
    catch {
        # コマンド失敗時はTCPListenerで直接確認
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
            $listener.Start()
            $listener.Stop()
            return $true
        }
        catch {
            return $false
        }
    }
}

# モジュールのエクスポート
Export-ModuleMember -Function @(
    'Get-AvailablePort',
    'Test-PortAvailable'
)
