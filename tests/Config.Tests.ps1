# ============================================================
# Config.Tests.ps1 - Config.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\Config.psm1" -Force
}

Describe 'Import-DevToolsConfig' {

    Context '有効な config.json を読み込む場合' {

        BeforeAll {
            # 一時 config.json を作成
            $script:TempDir = Join-Path $TestDrive 'config'
            New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
            $script:ValidConfigPath = Join-Path $script:TempDir 'config.json'
            $validJson = @{
                ports     = @(9222, 9223)
                zDrive    = 'X:\'
                linuxHost = 'testhost'
                linuxBase = '/mnt/LinuxHDD'
            } | ConvertTo-Json -Depth 3
            Set-Content -Path $script:ValidConfigPath -Value $validJson -Encoding UTF8
        }

        It '読み込んだオブジェクトが $null でないこと' {
            $result = Import-DevToolsConfig -ConfigPath $script:ValidConfigPath
            $result | Should -Not -BeNullOrEmpty
        }

        It 'ports フィールドが配列として読み込まれること' {
            $result = Import-DevToolsConfig -ConfigPath $script:ValidConfigPath
            $result.ports | Should -Not -BeNullOrEmpty
        }

        It 'linuxHost フィールドが正しく読み込まれること' {
            $result = Import-DevToolsConfig -ConfigPath $script:ValidConfigPath
            $result.linuxHost | Should -Be 'testhost'
        }

        It 'linuxBase フィールドが正しく読み込まれること' {
            $result = Import-DevToolsConfig -ConfigPath $script:ValidConfigPath
            $result.linuxBase | Should -Be '/mnt/LinuxHDD'
        }
    }

    Context 'ファイルが存在しない場合' {

        It '例外をスローすること' {
            $missingPath = Join-Path $TestDrive 'nonexistent\config.json'
            { Import-DevToolsConfig -ConfigPath $missingPath } | Should -Throw
        }

        It 'エラーメッセージにパスが含まれること' {
            $missingPath = Join-Path $TestDrive 'missing.json'
            { Import-DevToolsConfig -ConfigPath $missingPath } | Should -Throw -ExpectedMessage '*見つかりません*'
        }
    }

    Context '必須フィールドが欠けている場合' {

        BeforeAll {
            $script:IncompleteDir = Join-Path $TestDrive 'incomplete'
            New-Item -ItemType Directory -Path $script:IncompleteDir -Force | Out-Null
        }

        It 'ports が欠けている場合に例外をスローすること' {
            $path = Join-Path $script:IncompleteDir 'no-ports.json'
            @{ zDrive = 'X:\'; linuxHost = 'host'; linuxBase = '/mnt' } |
                ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $path } | Should -Throw
        }

        It 'linuxHost が欠けている場合に例外をスローすること' {
            $path = Join-Path $script:IncompleteDir 'no-linuxHost.json'
            @{ ports = @(9222); zDrive = 'X:\'; linuxBase = '/mnt' } |
                ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $path } | Should -Throw
        }

        It 'linuxBase が欠けている場合に例外をスローすること' {
            $path = Join-Path $script:IncompleteDir 'no-linuxBase.json'
            @{ ports = @(9222); zDrive = 'X:\'; linuxHost = 'host' } |
                ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $path } | Should -Throw
        }
    }

    Context '不正な JSON の場合' {

        It '不正な JSON で例外をスローすること' {
            $path = Join-Path $TestDrive 'invalid.json'
            Set-Content -Path $path -Value '{ this is not valid json' -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $path } | Should -Throw
        }
    }

    Context 'ポート範囲の検証' {

        It 'ポートが範囲外の場合に例外をスローすること' {
            $path = Join-Path $TestDrive 'bad-port.json'
            @{ ports = @(80); zDrive = 'X:\'; linuxHost = 'host'; linuxBase = '/mnt' } |
                ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $path } | Should -Throw
        }
    }

    Context 'initPromptFile の検証' {

        BeforeAll {
            $script:TempDir2 = Join-Path $TestDrive 'initprompt'
            New-Item -ItemType Directory -Path $script:TempDir2 -Force | Out-Null
        }

        It '存在する initPromptFile は警告なしで成功すること' {
            $promptFile = Join-Path $script:TempDir2 'prompt.txt'
            Set-Content -Path $promptFile -Value 'Test prompt' -Encoding UTF8
            $configPath = Join-Path $script:TempDir2 'config-with-prompt.json'
            @{ ports = @(9222); zDrive = 'X:\'; linuxHost = 'host'; linuxBase = '/mnt'; initPromptFile = $promptFile } |
                ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $configPath } | Should -Not -Throw
        }

        It '存在しない initPromptFile は警告を出すが成功すること' {
            $configPath = Join-Path $script:TempDir2 'config-missing-prompt.json'
            @{ ports = @(9222); zDrive = 'X:\'; linuxHost = 'host'; linuxBase = '/mnt'; initPromptFile = 'C:\nonexistent\prompt.txt' } |
                ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $configPath } | Should -Not -Throw
        }

        It 'initPromptFile が null の場合は検証をスキップすること' {
            $configPath = Join-Path $script:TempDir2 'config-null-prompt.json'
            @{ ports = @(9222); zDrive = 'X:\'; linuxHost = 'host'; linuxBase = '/mnt' } |
                ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $configPath } | Should -Not -Throw
        }
    }

    Context 'tmux スキーマ検証' {

        BeforeAll {
            $script:TempDir3 = Join-Path $TestDrive 'tmux'
            New-Item -ItemType Directory -Path $script:TempDir3 -Force | Out-Null
        }

        It '有効な tmux 設定は警告なしで成功すること' {
            $configPath = Join-Path $script:TempDir3 'config-valid-tmux.json'
            @{
                ports = @(9222); zDrive = 'X:\'; linuxHost = 'host'; linuxBase = '/mnt'
                tmux = @{ enabled = $false; defaultLayout = 'auto' }
            } | ConvertTo-Json -Depth 3 | Set-Content -Path $configPath -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $configPath } | Should -Not -Throw
        }

        It 'tmux セクションがない場合は検証をスキップすること' {
            $configPath = Join-Path $script:TempDir3 'config-no-tmux.json'
            @{ ports = @(9222); zDrive = 'X:\'; linuxHost = 'host'; linuxBase = '/mnt' } |
                ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8
            { Import-DevToolsConfig -ConfigPath $configPath } | Should -Not -Throw
        }
    }
}
