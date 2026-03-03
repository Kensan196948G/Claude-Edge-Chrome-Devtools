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
