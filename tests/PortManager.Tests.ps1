# ============================================================
# PortManager.Tests.ps1 - PortManager.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\PortManager.psm1" -Force
}

Describe 'Test-PortAvailable' {

    Context 'ポートが使用可能な場合' {

        It 'Get-NetTCPConnection がヒットしない場合に $true を返すこと' {
            Mock -CommandName 'Get-NetTCPConnection' -MockWith { return $null } -ModuleName 'PortManager'
            $result = Test-PortAvailable -Port 9222
            $result | Should -Be $true
        }
    }

    Context 'ポートが使用中の場合' {

        It 'Listen 状態の接続がある場合に $false を返すこと' {
            Mock -CommandName 'Get-NetTCPConnection' -MockWith {
                return [PSCustomObject]@{ LocalPort = 9222; State = 'Listen' }
            } -ModuleName 'PortManager'
            $result = Test-PortAvailable -Port 9222
            $result | Should -Be $false
        }
    }
}

Describe 'Get-AvailablePort' {

    Context 'ポート配列に使用可能なポートがある場合' {

        It '最初の使用可能ポートを返すこと' {
            # 9222 は使用中、9223 は空き
            Mock -CommandName 'Test-PortAvailable' -MockWith {
                param([int]$Port)
                return ($Port -ne 9222)
            } -ModuleName 'PortManager'

            $result = Get-AvailablePort -Ports @(9222, 9223, 9224)
            $result | Should -Be 9223
        }

        It '最初のポートが空きの場合はそれを返すこと' {
            Mock -CommandName 'Test-PortAvailable' -MockWith { return $true } -ModuleName 'PortManager'

            $result = Get-AvailablePort -Ports @(9222, 9223)
            $result | Should -Be 9222
        }
    }

    Context 'すべてのポートが使用中の場合' {

        It '$null を返すこと' {
            Mock -CommandName 'Test-PortAvailable' -MockWith { return $false } -ModuleName 'PortManager'

            $result = Get-AvailablePort -Ports @(9222, 9223, 9224)
            $result | Should -BeNullOrEmpty
        }
    }

    Context '単一ポートの配列の場合' {

        It '単一ポートが空きならそれを返すこと' {
            Mock -CommandName 'Test-PortAvailable' -MockWith { return $true } -ModuleName 'PortManager'

            $result = Get-AvailablePort -Ports @(9225)
            $result | Should -Be 9225
        }

        It '単一ポートが使用中なら $null を返すこと' {
            Mock -CommandName 'Test-PortAvailable' -MockWith { return $false } -ModuleName 'PortManager'

            $result = Get-AvailablePort -Ports @(9225)
            $result | Should -BeNullOrEmpty
        }
    }
}
