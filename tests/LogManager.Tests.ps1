# ============================================================
# LogManager.Tests.ps1 - LogManager.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\LogManager.psm1" -Force
}

Describe 'Start-SessionLog' {

    BeforeEach {
        # Start-Transcript をモックしてファイルロック問題を回避
        Mock Start-Transcript {} -ModuleName LogManager
        Mock Stop-Transcript {} -ModuleName LogManager
    }

    Context '正常系: logging.enabled = true の場合' {

        BeforeAll {
            $script:LogDir = Join-Path $TestDrive 'logs'
            $script:Config = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled         = $true
                    logDir          = $script:LogDir
                    logPrefix       = 'claude-devtools'
                    successKeepDays = 30
                    failureKeepDays = 90
                    archiveAfterDays = 30
                    legacyKeepDays  = 7
                }
            }
        }

        It 'ログファイルパスを含むハッシュテーブルを返すこと' {
            $result = Start-SessionLog -Config $script:Config -ProjectName 'TestProject' -Browser 'edge' -Port 9222
            $result | Should -BeOfType [hashtable]
            $result.LogPath | Should -Not -BeNullOrEmpty
        }

        It 'ログファイル名が命名規則に従うこと (prefix-project-browser-port-timestamp.log)' {
            $result = Start-SessionLog -Config $script:Config -ProjectName 'TestProject' -Browser 'edge' -Port 9222
            $fileName = [System.IO.Path]::GetFileName($result.LogPath)
            $fileName | Should -Match '^claude-devtools-TestProject-edge-9222-\d{8}-\d{6}\.log$'
        }

        It 'ログディレクトリが自動作成されること' {
            $freshDir = Join-Path $TestDrive 'fresh-logs'
            $freshConfig = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled   = $true
                    logDir    = $freshDir
                    logPrefix = 'claude-devtools'
                    successKeepDays = 30; failureKeepDays = 90
                    archiveAfterDays = 30; legacyKeepDays = 7
                }
            }
            Start-SessionLog -Config $freshConfig -ProjectName 'P' -Browser 'chrome' -Port 9223
            Test-Path $freshDir | Should -BeTrue
        }
    }

    Context 'フォールバック: logDir にアクセスできない場合' {

        It '$env:TEMP にフォールバックすること' {
            # 書き込みテストが失敗するようにNew-Itemをモック（ディレクトリ作成は成功するが書き込みテストで例外）
            $badPath = "\\?\INVALID_UNC_PATH_$([guid]::NewGuid())"
            $badConfig = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled   = $true
                    logDir    = $badPath
                    logPrefix = 'claude-devtools'
                    successKeepDays = 30; failureKeepDays = 90
                    archiveAfterDays = 30; legacyKeepDays = 7
                }
            }
            $result = Start-SessionLog -Config $badConfig -ProjectName 'P' -Browser 'edge' -Port 9222
            $escapedTemp = [regex]::Escape($env:TEMP)
            $result.LogPath | Should -Match $escapedTemp
        }
    }

    Context 'logging.enabled = false の場合' {

        It 'LogPath が $null であること' {
            $disabledConfig = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled = $false
                    logDir = 'logs'; logPrefix = 'claude-devtools'
                    successKeepDays = 30; failureKeepDays = 90
                    archiveAfterDays = 30; legacyKeepDays = 7
                }
            }
            $result = Start-SessionLog -Config $disabledConfig -ProjectName 'P' -Browser 'edge' -Port 9222
            $result.LogPath | Should -BeNullOrEmpty
        }
    }

    Context 'logging セクションが存在しない場合' {

        It 'LogPath が $null であること (フォールバック動作)' {
            $noLoggingConfig = [pscustomobject]@{}
            $result = Start-SessionLog -Config $noLoggingConfig -ProjectName 'P' -Browser 'edge' -Port 9222
            $result.LogPath | Should -BeNullOrEmpty
        }
    }
}

Describe 'Stop-SessionLog' {

    BeforeEach {
        Mock Start-Transcript {} -ModuleName LogManager
        Mock Stop-Transcript {} -ModuleName LogManager
    }

    Context 'SUCCESS サフィックス付与' {

        BeforeAll {
            $script:LogDir = Join-Path $TestDrive 'stop-logs'
            New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
            # ダミーログファイル作成
            $script:DummyLog = Join-Path $script:LogDir 'claude-devtools-Proj-edge-9222-20260303-120000.log'
            Set-Content -Path $script:DummyLog -Value 'test log content'
        }

        It 'SUCCESS サフィックスが付いたファイル名にリネームされること' {
            # モジュール内部状態をセット（テスト用）
            $mod = Get-Module LogManager
            & $mod { $script:CurrentLogPath = $args[0]; $script:LoggingActive = $true } $script:DummyLog

            Stop-SessionLog -Success $true

            $expected = Join-Path $script:LogDir 'claude-devtools-Proj-edge-9222-20260303-120000-SUCCESS.log'
            Test-Path $expected | Should -BeTrue
        }
    }

    Context 'FAILURE サフィックス付与' {

        BeforeAll {
            $script:LogDir2 = Join-Path $TestDrive 'stop-logs-fail'
            New-Item -ItemType Directory -Path $script:LogDir2 -Force | Out-Null
            $script:DummyLog2 = Join-Path $script:LogDir2 'claude-devtools-Proj-chrome-9223-20260303-130000.log'
            Set-Content -Path $script:DummyLog2 -Value 'test log content'
        }

        It 'FAILURE サフィックスが付いたファイル名にリネームされること' {
            $mod = Get-Module LogManager
            & $mod { $script:CurrentLogPath = $args[0]; $script:LoggingActive = $true } $script:DummyLog2

            Stop-SessionLog -Success $false

            $expected = Join-Path $script:LogDir2 'claude-devtools-Proj-chrome-9223-20260303-130000-FAILURE.log'
            Test-Path $expected | Should -BeTrue
        }
    }

    Context 'ログが開始されていない場合' {

        It '例外をスローしないこと' {
            $mod = Get-Module LogManager
            & $mod { $script:CurrentLogPath = $null; $script:LoggingActive = $false }

            { Stop-SessionLog -Success $true } | Should -Not -Throw
        }
    }
}

Describe 'Invoke-LogRotation' {

    Context 'SUCCESS ログの期限切れ削除' {

        BeforeAll {
            $script:RotDir = Join-Path $TestDrive 'rotation'
            New-Item -ItemType Directory -Path $script:RotDir -Force | Out-Null

            # 期限切れファイル (31日前)
            $script:OldSuccess = Join-Path $script:RotDir 'claude-devtools-P-edge-9222-20260201-120000-SUCCESS.log'
            Set-Content -Path $script:OldSuccess -Value 'old'
            (Get-Item $script:OldSuccess).LastWriteTime = (Get-Date).AddDays(-31)

            # 期限内ファイル (1日前)
            $script:NewSuccess = Join-Path $script:RotDir 'claude-devtools-P-edge-9222-20260302-120000-SUCCESS.log'
            Set-Content -Path $script:NewSuccess -Value 'new'
            (Get-Item $script:NewSuccess).LastWriteTime = (Get-Date).AddDays(-1)

            $script:RotConfig = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled = $true; logDir = $script:RotDir; logPrefix = 'claude-devtools'
                    successKeepDays = 30; failureKeepDays = 90
                    archiveAfterDays = 30; legacyKeepDays = 7
                }
            }
        }

        It '期限切れ SUCCESS ログが削除されること' {
            Invoke-LogRotation -Config $script:RotConfig
            Test-Path $script:OldSuccess | Should -BeFalse
        }

        It '期限内 SUCCESS ログが保持されること' {
            Test-Path $script:NewSuccess | Should -BeTrue
        }
    }

    Context 'FAILURE ログの長期保持' {

        BeforeAll {
            $script:FailDir = Join-Path $TestDrive 'rotation-fail'
            New-Item -ItemType Directory -Path $script:FailDir -Force | Out-Null

            # 31日前の FAILURE (failureKeepDays=90 なので保持)
            $script:RecentFailure = Join-Path $script:FailDir 'claude-devtools-P-edge-9222-20260201-120000-FAILURE.log'
            Set-Content -Path $script:RecentFailure -Value 'fail-recent'
            (Get-Item $script:RecentFailure).LastWriteTime = (Get-Date).AddDays(-31)

            # 91日前の FAILURE (failureKeepDays=90 なので削除)
            $script:OldFailure = Join-Path $script:FailDir 'claude-devtools-P-edge-9222-20251201-120000-FAILURE.log'
            Set-Content -Path $script:OldFailure -Value 'fail-old'
            (Get-Item $script:OldFailure).LastWriteTime = (Get-Date).AddDays(-91)

            $script:FailConfig = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled = $true; logDir = $script:FailDir; logPrefix = 'claude-devtools'
                    successKeepDays = 30; failureKeepDays = 90
                    archiveAfterDays = 30; legacyKeepDays = 7
                }
            }
        }

        It '90日以内の FAILURE ログが保持されること' {
            Invoke-LogRotation -Config $script:FailConfig
            Test-Path $script:RecentFailure | Should -BeTrue
        }

        It '90日超の FAILURE ログが削除されること' {
            Test-Path $script:OldFailure | Should -BeFalse
        }
    }

    Context 'レガシーログ (サフィックスなし) の削除' {

        BeforeAll {
            $script:LegacyDir = Join-Path $TestDrive 'rotation-legacy'
            New-Item -ItemType Directory -Path $script:LegacyDir -Force | Out-Null

            # 8日前のレガシーログ (legacyKeepDays=7 なので削除)
            $script:OldLegacy = Join-Path $script:LegacyDir 'claude-devtools-20260223-120000.log'
            Set-Content -Path $script:OldLegacy -Value 'legacy'
            (Get-Item $script:OldLegacy).LastWriteTime = (Get-Date).AddDays(-8)

            $script:LegacyConfig = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled = $true; logDir = $script:LegacyDir; logPrefix = 'claude-devtools'
                    successKeepDays = 30; failureKeepDays = 90
                    archiveAfterDays = 30; legacyKeepDays = 7
                }
            }
        }

        It 'legacyKeepDays 超過のサフィックスなしログが削除されること' {
            Invoke-LogRotation -Config $script:LegacyConfig
            Test-Path $script:OldLegacy | Should -BeFalse
        }
    }
}

Describe 'Invoke-LogArchive' {

    Context 'archiveAfterDays 超過ファイルの ZIP 圧縮' {

        BeforeAll {
            $script:ArchDir = Join-Path $TestDrive 'archive-test'
            New-Item -ItemType Directory -Path $script:ArchDir -Force | Out-Null

            # 31日前の SUCCESS ログ (archiveAfterDays=30 なのでアーカイブ対象)
            $script:OldLog = Join-Path $script:ArchDir 'claude-devtools-P-edge-9222-20260201-120000-SUCCESS.log'
            Set-Content -Path $script:OldLog -Value 'archive target'
            (Get-Item $script:OldLog).LastWriteTime = (Get-Date).AddDays(-31)

            # 1日前のログ (アーカイブ対象外)
            $script:NewLog = Join-Path $script:ArchDir 'claude-devtools-P-edge-9222-20260302-120000-SUCCESS.log'
            Set-Content -Path $script:NewLog -Value 'keep'
            (Get-Item $script:NewLog).LastWriteTime = (Get-Date).AddDays(-1)

            $script:ArchConfig = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled = $true; logDir = $script:ArchDir; logPrefix = 'claude-devtools'
                    successKeepDays = 30; failureKeepDays = 90
                    archiveAfterDays = 30; legacyKeepDays = 7
                }
            }
        }

        It 'archiveAfterDays 超過ファイルの ZIP が作成されること' {
            Invoke-LogArchive -Config $script:ArchConfig
            $zips = Get-ChildItem -Path $script:ArchDir -Filter '*.zip' -Recurse
            $zips.Count | Should -BeGreaterOrEqual 1
        }

        It 'アーカイブ後に元ファイルが削除されること' {
            Test-Path $script:OldLog | Should -BeFalse
        }

        It 'archiveAfterDays 以内のファイルは残ること' {
            Test-Path $script:NewLog | Should -BeTrue
        }
    }
}

Describe 'Get-LogSummary' {

    Context 'ログファイルが存在する場合' {

        BeforeAll {
            $script:SumDir = Join-Path $TestDrive 'summary'
            New-Item -ItemType Directory -Path $script:SumDir -Force | Out-Null

            Set-Content -Path (Join-Path $script:SumDir 'claude-devtools-P-edge-9222-20260301-120000-SUCCESS.log') -Value ('x' * 100)
            Set-Content -Path (Join-Path $script:SumDir 'claude-devtools-P-edge-9222-20260302-120000-FAILURE.log') -Value ('y' * 200)

            $script:SumConfig = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled = $true; logDir = $script:SumDir; logPrefix = 'claude-devtools'
                    successKeepDays = 30; failureKeepDays = 90
                    archiveAfterDays = 30; legacyKeepDays = 7
                }
            }
        }

        It 'TotalFiles が正しいこと' {
            $result = Get-LogSummary -Config $script:SumConfig
            $result.TotalFiles | Should -Be 2
        }

        It 'SuccessCount が正しいこと' {
            $result = Get-LogSummary -Config $script:SumConfig
            $result.SuccessCount | Should -Be 1
        }

        It 'FailureCount が正しいこと' {
            $result = Get-LogSummary -Config $script:SumConfig
            $result.FailureCount | Should -Be 1
        }

        It 'TotalSizeBytes が 0 より大きいこと' {
            $result = Get-LogSummary -Config $script:SumConfig
            $result.TotalSizeBytes | Should -BeGreaterThan 0
        }
    }

    Context 'ログファイルが存在しない場合' {

        It 'TotalFiles が 0 であること' {
            $emptyConfig = [pscustomobject]@{
                logging = [pscustomobject]@{
                    enabled = $true; logDir = (Join-Path $TestDrive 'empty-dir'); logPrefix = 'claude-devtools'
                    successKeepDays = 30; failureKeepDays = 90
                    archiveAfterDays = 30; legacyKeepDays = 7
                }
            }
            $result = Get-LogSummary -Config $emptyConfig
            $result.TotalFiles | Should -Be 0
        }
    }
}
