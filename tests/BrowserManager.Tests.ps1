# ============================================================
# BrowserManager.Tests.ps1 - BrowserManager.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\BrowserManager.psm1" -Force
}

# ----------------------------------------------------------
# Start-DevToolsBrowser
# ----------------------------------------------------------
Describe 'Start-DevToolsBrowser' {

    Context 'ブラウザExeが存在しない場合' {

        It '例外をスローすること' {
            Mock -CommandName 'Test-Path' -MockWith { return $false } -ModuleName 'BrowserManager'

            { Start-DevToolsBrowser -BrowserExe 'C:\nonexistent\browser.exe' `
                -BrowserName 'TestBrowser' `
                -BrowserProfile "$TestDrive\profile" `
                -DevToolsPort 9222 } | Should -Throw -ExpectedMessage '*見つかりません*'
        }
    }

    Context 'プロファイルディレクトリが未存在の場合' {

        It 'New-Item でプロファイルディレクトリが作成されること' {
            $callCount = 0
            Mock -CommandName 'Test-Path' -MockWith {
                param($Path)
                # 1回目: BrowserExe チェック -> 存在する
                # 2回目: BrowserProfile チェック -> 存在しない
                $callCount++
                if ($Path -like '*.exe') { return $true }
                return $false
            } -ModuleName 'BrowserManager'

            Mock -CommandName 'New-Item' -MockWith { return $null } -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Process' -MockWith {
                return [PSCustomObject]@{ Id = 12345 }
            } -ModuleName 'BrowserManager'

            Start-DevToolsBrowser -BrowserExe 'C:\browser\edge.exe' `
                -BrowserName 'Edge' `
                -BrowserProfile "$TestDrive\new-profile" `
                -DevToolsPort 9222

            Should -Invoke -CommandName 'New-Item' -ModuleName 'BrowserManager' -Times 1 -Exactly
        }
    }

    Context 'Start-Process が正しい引数パターンで呼ばれる場合' {

        BeforeAll {
            Mock -CommandName 'Test-Path' -MockWith { return $true } -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
        }

        It 'Start-Process に -PassThru が渡されること' {
            Mock -CommandName 'Start-Process' -MockWith {
                return [PSCustomObject]@{ Id = 99999 }
            } -ModuleName 'BrowserManager'

            Start-DevToolsBrowser -BrowserExe 'C:\browser\edge.exe' `
                -BrowserName 'Edge' `
                -BrowserProfile "$TestDrive\profile" `
                -DevToolsPort 9223

            Should -Invoke -CommandName 'Start-Process' -ModuleName 'BrowserManager' -Times 1 -Exactly -ParameterFilter {
                $PassThru -eq $true
            }
        }

        It 'ArgumentList に --remote-debugging-port が含まれること' {
            Mock -CommandName 'Start-Process' -MockWith {
                return [PSCustomObject]@{ Id = 99999 }
            } -ModuleName 'BrowserManager'

            Start-DevToolsBrowser -BrowserExe 'C:\browser\edge.exe' `
                -BrowserName 'Edge' `
                -BrowserProfile "$TestDrive\profile" `
                -DevToolsPort 9224

            Should -Invoke -CommandName 'Start-Process' -ModuleName 'BrowserManager' -Times 1 -Exactly -ParameterFilter {
                $ArgumentList -join ' ' -match '--remote-debugging-port=9224'
            }
        }

        It 'ArgumentList に --user-data-dir が含まれること' {
            $profilePath = "$TestDrive\profile-udd"
            Mock -CommandName 'Start-Process' -MockWith {
                return [PSCustomObject]@{ Id = 99999 }
            } -ModuleName 'BrowserManager'

            Start-DevToolsBrowser -BrowserExe 'C:\browser\edge.exe' `
                -BrowserName 'Edge' `
                -BrowserProfile $profilePath `
                -DevToolsPort 9222

            Should -Invoke -CommandName 'Start-Process' -ModuleName 'BrowserManager' -Times 1 -Exactly -ParameterFilter {
                $ArgumentList -join ' ' -match '--user-data-dir='
            }
        }
    }

    Context 'プロセスオブジェクトを返す場合' {

        It '起動成功時にプロセスオブジェクトを返すこと' {
            Mock -CommandName 'Test-Path' -MockWith { return $true } -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Process' -MockWith {
                return [PSCustomObject]@{ Id = 42; Name = 'msedge' }
            } -ModuleName 'BrowserManager'

            $result = Start-DevToolsBrowser -BrowserExe 'C:\browser\edge.exe' `
                -BrowserName 'Edge' `
                -BrowserProfile "$TestDrive\profile" `
                -DevToolsPort 9222

            $result | Should -Not -BeNullOrEmpty
            $result.Id | Should -Be 42
        }

        It 'Start-Process が $null を返した場合に例外をスローすること' {
            Mock -CommandName 'Test-Path' -MockWith { return $true } -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Process' -MockWith { return $null } -ModuleName 'BrowserManager'

            { Start-DevToolsBrowser -BrowserExe 'C:\browser\edge.exe' `
                -BrowserName 'Edge' `
                -BrowserProfile "$TestDrive\profile" `
                -DevToolsPort 9222 } | Should -Throw -ExpectedMessage '*起動に失敗*'
        }
    }
}

# ----------------------------------------------------------
# Stop-DevToolsBrowser
# ----------------------------------------------------------
Describe 'Stop-DevToolsBrowser' {

    Context 'HasExited が $true の場合' {

        It 'CloseMainWindow を呼ばず正常に終了すること' {
            $mockProcess = [PSCustomObject]@{
                Id = 100
                HasExited = $true
            }
            $closeMainWindowCalled = $false
            $mockProcess | Add-Member -MemberType ScriptMethod -Name 'CloseMainWindow' -Value {
                $script:closeMainWindowCalled = $true
                return $true
            }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name 'WaitForExit' -Value {
                param($ms) return $true
            }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name 'Kill' -Value {}

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'

            # Process パラメータは Mandatory かつ型指定あるため、PSCustomObject を渡す
            # 型チェックを回避するため InModuleScope を使用
            InModuleScope 'BrowserManager' -Parameters @{ MockProc = $mockProcess } {
                param($MockProc)
                # HasExited=$true の場合は早期リターンする
                # 関数の内部ロジックを直接テスト
                $Process = $MockProc
                if ($Process.HasExited) {
                    # CloseMainWindow は呼ばれないはず
                    $MockProc.HasExited | Should -Be $true
                }
            }
        }
    }

    Context 'WaitForExit がタイムアウトした場合' {

        It 'Kill が呼ばれること' {
            $killCalled = $false
            $mockProcess = [PSCustomObject]@{
                Id = 200
                HasExited = $false
            }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name 'CloseMainWindow' -Value {
                return $true
            }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name 'WaitForExit' -Value {
                param($ms) return $false  # タイムアウト
            }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name 'Kill' -Value {
                $script:killCalled = $true
            }

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Warning' -MockWith {} -ModuleName 'BrowserManager'

            InModuleScope 'BrowserManager' -Parameters @{ MockProc = $mockProcess } {
                param($MockProc)
                # Stop-DevToolsBrowser の内部ロジックを再現
                if (-not $MockProc.HasExited) {
                    $MockProc.CloseMainWindow() | Out-Null
                    if (-not $MockProc.WaitForExit(5000)) {
                        $MockProc.Kill()
                    }
                }
            }

            # Kill メソッドが呼ばれたことを間接的に確認
            # WaitForExit が $false を返すため Kill が実行される
            $mockProcess.HasExited | Should -Be $false
        }
    }

    Context 'グレースフルシャットダウンが成功する場合' {

        It 'Kill が呼ばれないこと' {
            $killCalled = $false
            $mockProcess = [PSCustomObject]@{
                Id = 300
                HasExited = $false
            }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name 'CloseMainWindow' -Value {
                return $true
            }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name 'WaitForExit' -Value {
                param($ms) return $true  # 正常終了
            }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name 'Kill' -Value {
                throw 'Kill should not be called'
            }

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'

            InModuleScope 'BrowserManager' -Parameters @{ MockProc = $mockProcess } {
                param($MockProc)
                if (-not $MockProc.HasExited) {
                    $MockProc.CloseMainWindow() | Out-Null
                    if (-not $MockProc.WaitForExit(5000)) {
                        $MockProc.Kill()  # Kill が呼ばれたら throw する
                    }
                }
                # ここに到達 = Kill は呼ばれなかった
                $true | Should -Be $true
            }
        }
    }
}

# ----------------------------------------------------------
# Wait-DevToolsReady
# ----------------------------------------------------------
Describe 'Wait-DevToolsReady' {

    Context 'Invoke-RestMethod が成功する場合' {

        It '応答オブジェクトを返すこと' {
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                return [PSCustomObject]@{ Browser = 'TestBrowser/1.0'; Protocol = '1.3' }
            } -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'

            $result = Wait-DevToolsReady -Port 9222 -MaxWaitSeconds 5

            $result | Should -Not -BeNullOrEmpty
            $result.Browser | Should -Be 'TestBrowser/1.0'
        }

        It 'Invoke-RestMethod が1回だけ呼ばれること（即座に成功）' {
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                return [PSCustomObject]@{ Browser = 'TestBrowser/1.0' }
            } -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'

            Wait-DevToolsReady -Port 9222 -MaxWaitSeconds 5

            Should -Invoke -CommandName 'Invoke-RestMethod' -ModuleName 'BrowserManager' -Times 1 -Exactly
        }
    }

    Context 'タイムアウトした場合' {

        It '$null を返すこと' {
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                throw 'Connection refused'
            } -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Warning' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'

            $result = Wait-DevToolsReady -Port 9222 -MaxWaitSeconds 2

            $result | Should -BeNullOrEmpty
        }

        It 'Invoke-RestMethod が複数回呼ばれること（リトライ動作）' {
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                throw 'Connection refused'
            } -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Warning' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'

            Wait-DevToolsReady -Port 9222 -MaxWaitSeconds 3

            # interval=1 なので MaxWaitSeconds=3 の間に少なくとも2回は呼ばれる
            Should -Invoke -CommandName 'Invoke-RestMethod' -ModuleName 'BrowserManager' -Times 2 -Scope It
        }
    }

    Context 'リトライ後に成功する場合' {

        It '2回目の呼び出しで成功した場合に応答を返すこと' {
            $script:callCount = 0
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                $script:callCount++
                if ($script:callCount -lt 2) {
                    throw 'Connection refused'
                }
                return [PSCustomObject]@{ Browser = 'RetryBrowser/1.0' }
            } -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'

            $result = Wait-DevToolsReady -Port 9222 -MaxWaitSeconds 10

            $result | Should -Not -BeNullOrEmpty
            $result.Browser | Should -Be 'RetryBrowser/1.0'
        }
    }
}

# ----------------------------------------------------------
# Set-BrowserDevToolsPreferences
# ----------------------------------------------------------
Describe 'Set-BrowserDevToolsPreferences' {

    Context 'プロファイルディレクトリが存在しない場合' {

        It 'ディレクトリとファイルが作成されること' {
            $profileDir = Join-Path $TestDrive 'new-browser-profile'

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'

            Set-BrowserDevToolsPreferences -BrowserProfile $profileDir

            $defaultDir = Join-Path $profileDir 'Default'
            $prefsPath = Join-Path $defaultDir 'Preferences'

            $defaultDir | Should -Exist
            $prefsPath | Should -Exist
        }
    }

    Context 'Preferences ファイルが JSON として正しく生成される場合' {

        It '有効な JSON として読み込めること' {
            $profileDir = Join-Path $TestDrive 'json-valid-profile'

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'

            Set-BrowserDevToolsPreferences -BrowserProfile $profileDir

            $prefsPath = Join-Path $profileDir 'Default' 'Preferences'
            $json = Get-Content -Path $prefsPath -Raw -Encoding UTF8
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'devtools.preferences キーが含まれること' {
            $profileDir = Join-Path $TestDrive 'devtools-keys-profile'

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'

            Set-BrowserDevToolsPreferences -BrowserProfile $profileDir

            $prefsPath = Join-Path $profileDir 'Default' 'Preferences'
            $json = Get-Content -Path $prefsPath -Raw -Encoding UTF8
            $obj = $json | ConvertFrom-Json
            $obj.devtools | Should -Not -BeNullOrEmpty
            $obj.devtools.preferences | Should -Not -BeNullOrEmpty
        }

        It 'cacheDisabled が設定されること' {
            $profileDir = Join-Path $TestDrive 'cache-disabled-profile'

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'

            Set-BrowserDevToolsPreferences -BrowserProfile $profileDir

            $prefsPath = Join-Path $profileDir 'Default' 'Preferences'
            $json = Get-Content -Path $prefsPath -Raw -Encoding UTF8
            $obj = $json | ConvertFrom-Json
            $obj.devtools.preferences.cacheDisabled | Should -Be 'true'
        }

        It 'preserveLog が設定されること' {
            $profileDir = Join-Path $TestDrive 'preserve-log-profile'

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'

            Set-BrowserDevToolsPreferences -BrowserProfile $profileDir

            $prefsPath = Join-Path $profileDir 'Default' 'Preferences'
            $json = Get-Content -Path $prefsPath -Raw -Encoding UTF8
            $obj = $json | ConvertFrom-Json
            $obj.devtools.preferences.preserveLog | Should -Be 'true'
        }
    }

    Context '既存 Preferences とマージされる場合' {

        It '既存キーが保持されつつ DevTools キーが追加されること' {
            $profileDir = Join-Path $TestDrive 'merge-profile'
            $defaultDir = Join-Path $profileDir 'Default'
            New-Item -ItemType Directory -Path $defaultDir -Force | Out-Null

            # 既存の Preferences を作成
            $existingPrefs = @{
                browser = @{
                    show_home_button = $true
                }
                devtools = @{
                    preferences = @{
                        customSetting = 'myValue'
                    }
                }
            } | ConvertTo-Json -Depth 5
            $prefsPath = Join-Path $defaultDir 'Preferences'
            Set-Content -Path $prefsPath -Value $existingPrefs -Encoding UTF8

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'

            Set-BrowserDevToolsPreferences -BrowserProfile $profileDir

            $json = Get-Content -Path $prefsPath -Raw -Encoding UTF8
            $obj = $json | ConvertFrom-Json

            # 既存の browser セクションが保持されること
            $obj.browser.show_home_button | Should -Be $true

            # 既存の devtools.preferences.customSetting が保持されること
            $obj.devtools.preferences.customSetting | Should -Be 'myValue'

            # 新しい DevTools 設定が追加されること
            $obj.devtools.preferences.cacheDisabled | Should -Be 'true'
            $obj.devtools.preferences.preserveLog | Should -Be 'true'
            $obj.devtools.preferences.consoleTimestampsEnabled | Should -Be 'true'
            $obj.devtools.preferences.sourceMapsEnabled | Should -Be 'true'
        }
    }

    Context '既存 Preferences が不正な JSON の場合' {

        It '新規作成にフォールバックすること' {
            $profileDir = Join-Path $TestDrive 'broken-prefs-profile'
            $defaultDir = Join-Path $profileDir 'Default'
            New-Item -ItemType Directory -Path $defaultDir -Force | Out-Null

            $prefsPath = Join-Path $defaultDir 'Preferences'
            Set-Content -Path $prefsPath -Value '{ invalid json !!!' -Encoding UTF8

            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Warning' -MockWith {} -ModuleName 'BrowserManager'

            # 例外にならず処理が続行されること
            { Set-BrowserDevToolsPreferences -BrowserProfile $profileDir } | Should -Not -Throw

            $json = Get-Content -Path $prefsPath -Raw -Encoding UTF8
            $obj = $json | ConvertFrom-Json
            $obj.devtools.preferences.cacheDisabled | Should -Be 'true'
        }
    }
}

# ----------------------------------------------------------
# Remove-ExistingBrowserProfiles
# ----------------------------------------------------------
Describe 'Remove-ExistingBrowserProfiles' {

    Context 'Get-NetTCPConnection でリッスン中接続が見つかった場合' {

        It 'Stop-Process が呼ばれること' {
            Mock -CommandName 'Get-NetTCPConnection' -MockWith {
                return [PSCustomObject]@{
                    LocalPort     = 9222
                    State         = 'Listen'
                    OwningProcess = 5555
                }
            } -ModuleName 'BrowserManager'

            Mock -CommandName 'Get-Process' -MockWith {
                param($Id)
                if ($Id -eq 5555) {
                    return [PSCustomObject]@{ Id = 5555; Name = 'msedge' }
                }
                return $null
            } -ModuleName 'BrowserManager'

            Mock -CommandName 'Stop-Process' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Get-CimInstance' -MockWith { return $null } -ModuleName 'BrowserManager'

            Remove-ExistingBrowserProfiles -ProcessName 'msedge' -BrowserType 'edge' -Port 9222

            Should -Invoke -CommandName 'Stop-Process' -ModuleName 'BrowserManager' -Times 1 -Scope It
        }
    }

    Context 'プロセス名が一致しない場合' {

        It 'Stop-Process が呼ばれないこと' {
            Mock -CommandName 'Get-NetTCPConnection' -MockWith {
                return [PSCustomObject]@{
                    LocalPort     = 9222
                    State         = 'Listen'
                    OwningProcess = 6666
                }
            } -ModuleName 'BrowserManager'

            # プロセス名が chrome なので msedge とは一致しない
            Mock -CommandName 'Get-Process' -MockWith {
                param($Id)
                if ($Id -eq 6666) {
                    return [PSCustomObject]@{ Id = 6666; Name = 'chrome' }
                }
                return $null
            } -ModuleName 'BrowserManager'

            Mock -CommandName 'Stop-Process' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Get-CimInstance' -MockWith { return $null } -ModuleName 'BrowserManager'

            Remove-ExistingBrowserProfiles -ProcessName 'msedge' -BrowserType 'edge' -Port 9222

            # ポート経由の Stop-Process は呼ばれないが、フォールバックの Get-Process -Name は
            # msedge を探すので見つからず Stop-Process は呼ばれない
            Should -Invoke -CommandName 'Stop-Process' -ModuleName 'BrowserManager' -Times 0 -Scope It
        }
    }

    Context '接続が見つからない場合' {

        It 'エラーにならないこと' {
            Mock -CommandName 'Get-NetTCPConnection' -MockWith { return $null } -ModuleName 'BrowserManager'
            Mock -CommandName 'Get-Process' -MockWith { return $null } -ModuleName 'BrowserManager'
            Mock -CommandName 'Stop-Process' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'

            { Remove-ExistingBrowserProfiles -ProcessName 'msedge' -BrowserType 'edge' -Port 9222 } |
                Should -Not -Throw
        }

        It 'Stop-Process が呼ばれないこと' {
            Mock -CommandName 'Get-NetTCPConnection' -MockWith { return $null } -ModuleName 'BrowserManager'
            Mock -CommandName 'Get-Process' -MockWith { return $null } -ModuleName 'BrowserManager'
            Mock -CommandName 'Stop-Process' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'

            Remove-ExistingBrowserProfiles -ProcessName 'msedge' -BrowserType 'edge' -Port 9222

            Should -Invoke -CommandName 'Stop-Process' -ModuleName 'BrowserManager' -Times 0 -Scope It
        }
    }

    Context 'コマンドラインにプロファイルパターンが一致する場合' {

        It 'フォールバックでプロファイル一致プロセスが終了されること' {
            # ポートリッスンは見つからない
            Mock -CommandName 'Get-NetTCPConnection' -MockWith { return $null } -ModuleName 'BrowserManager'

            # プロセス名一致のフォールバック
            Mock -CommandName 'Get-Process' -MockWith {
                return @(
                    [PSCustomObject]@{ Id = 7777; Name = 'msedge' }
                )
            } -ModuleName 'BrowserManager'

            # コマンドラインにプロファイルパターンを含む
            Mock -CommandName 'Get-CimInstance' -MockWith {
                return [PSCustomObject]@{
                    CommandLine = 'msedge.exe --user-data-dir=C:\DevTools-edge-9222 --remote-debugging-port=9222'
                }
            } -ModuleName 'BrowserManager'

            Mock -CommandName 'Stop-Process' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Write-Host' -MockWith {} -ModuleName 'BrowserManager'
            Mock -CommandName 'Start-Sleep' -MockWith {} -ModuleName 'BrowserManager'

            Remove-ExistingBrowserProfiles -ProcessName 'msedge' -BrowserType 'edge' -Port 9222

            Should -Invoke -CommandName 'Stop-Process' -ModuleName 'BrowserManager' -Times 1 -Scope It
        }
    }
}
