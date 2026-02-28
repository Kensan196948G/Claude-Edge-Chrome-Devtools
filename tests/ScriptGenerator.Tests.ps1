# ============================================================
# ScriptGenerator.Tests.ps1 - ScriptGenerator.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\ScriptGenerator.psm1" -Force
}

Describe 'ConvertTo-Base64Utf8' {

    Context '基本的な文字列のエンコード' {

        It '文字列を base64 エンコードできること' {
            $result = ConvertTo-Base64Utf8 -Content 'hello'
            $result | Should -Not -BeNullOrEmpty
            # デコードして元に戻ることを確認
            $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($result))
            $decoded | Should -Be 'hello'
        }

        It '空文字列を渡すと例外をスローすること（Mandatory パラメータのため）' {
            { ConvertTo-Base64Utf8 -Content '' } | Should -Throw
        }

        It '日本語文字列をエンコードできること' {
            $result = ConvertTo-Base64Utf8 -Content 'こんにちは'
            $result | Should -Not -BeNullOrEmpty
            $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($result))
            $decoded | Should -Be 'こんにちは'
        }
    }

    Context 'CRLF → LF 変換' {

        It 'CRLF をLFに統一してエンコードすること' {
            $withCrlf = "line1`r`nline2`r`nline3"
            $result   = ConvertTo-Base64Utf8 -Content $withCrlf
            $decoded  = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($result))
            $decoded | Should -Be "line1`nline2`nline3"
        }

        It '単独 CR をLFに変換すること' {
            $withCr  = "line1`rline2"
            $result  = ConvertTo-Base64Utf8 -Content $withCr
            $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($result))
            $decoded | Should -Be "line1`nline2"
        }

        It '既に LF のみの場合は変換されないこと' {
            $withLf  = "line1`nline2`nline3"
            $result  = ConvertTo-Base64Utf8 -Content $withLf
            $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($result))
            $decoded | Should -Be "line1`nline2`nline3"
        }
    }
}

Describe 'Build-ClaudeCodeJsonFromConfig' {

    Context '正常なパラメータの場合' {

        It 'EnvJson, SettingsJson, FullJson の 3 キーを含むハッシュテーブルを返すこと' {
            $env      = @{ MY_VAR = 'value1' }
            $settings = @{ language = 'ja' }
            $result   = Build-ClaudeCodeJsonFromConfig -ClaudeEnv $env -ClaudeSettings $settings
            $result             | Should -BeOfType [hashtable]
            $result.EnvJson     | Should -Not -BeNullOrEmpty
            $result.SettingsJson | Should -Not -BeNullOrEmpty
            $result.FullJson    | Should -Not -BeNullOrEmpty
        }

        It 'EnvJson が有効な JSON 文字列であること' {
            $env    = @{ KEY1 = 'val1'; KEY2 = 'val2' }
            $result = Build-ClaudeCodeJsonFromConfig -ClaudeEnv $env
            { $result.EnvJson | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'SettingsJson が有効な JSON 文字列であること' {
            $settings = @{ language = '日本語'; outputStyle = 'Explanatory' }
            $result   = Build-ClaudeCodeJsonFromConfig -ClaudeSettings $settings
            { $result.SettingsJson | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'FullJson が有効な JSON 文字列であること' {
            $env      = @{ AGENT_TEAMS = '1' }
            $settings = @{ language = '日本語' }
            $result   = Build-ClaudeCodeJsonFromConfig -ClaudeEnv $env -ClaudeSettings $settings
            { $result.FullJson | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'FullJson に env セクションが含まれること（EnvVars がある場合）' {
            $env    = @{ MY_KEY = 'my_val' }
            $result = Build-ClaudeCodeJsonFromConfig -ClaudeEnv $env -ClaudeSettings @{}
            $parsed = $result.FullJson | ConvertFrom-Json
            $parsed.env | Should -Not -BeNullOrEmpty
        }
    }

    Context 'パラメータが省略された場合' {

        It 'パラメータなしでも 3 キーを返すこと' {
            $result = Build-ClaudeCodeJsonFromConfig
            $result             | Should -BeOfType [hashtable]
            $result.EnvJson     | Should -Not -BeNullOrEmpty
            $result.SettingsJson | Should -Not -BeNullOrEmpty
            $result.FullJson    | Should -Not -BeNullOrEmpty
        }

        It 'ClaudeEnv のみ指定しても動作すること' {
            $result = Build-ClaudeCodeJsonFromConfig -ClaudeEnv @{ FOO = 'bar' }
            $result.EnvJson | Should -Not -BeNullOrEmpty
        }

        It 'ClaudeSettings のみ指定しても動作すること' {
            $result = Build-ClaudeCodeJsonFromConfig -ClaudeSettings @{ language = 'ja' }
            $result.SettingsJson | Should -Not -BeNullOrEmpty
        }
    }

    Context 'PSCustomObject パラメータの場合' {

        It 'PSCustomObject を受け入れること' {
            $envObj = [PSCustomObject]@{ ENV_KEY = 'env_val' }
            $result = Build-ClaudeCodeJsonFromConfig -ClaudeEnv $envObj
            $result.EnvJson | Should -Not -BeNullOrEmpty
            $parsed = $result.EnvJson | ConvertFrom-Json
            $parsed.ENV_KEY | Should -Be 'env_val'
        }
    }
}

Describe 'New-RunClaudeScript' {

    Context '必須パラメータが不足している場合' {

        It 'Port が欠けている場合に例外をスローすること' {
            $params = @{ LinuxBase = '/mnt/LinuxHDD'; ProjectName = 'TestProject' }
            { New-RunClaudeScript -Params $params } | Should -Throw
        }

        It 'LinuxBase が欠けている場合に例外をスローすること' {
            $params = @{ Port = 9222; ProjectName = 'TestProject' }
            { New-RunClaudeScript -Params $params } | Should -Throw
        }

        It 'ProjectName が欠けている場合に例外をスローすること' {
            $params = @{ Port = 9222; LinuxBase = '/mnt/LinuxHDD' }
            { New-RunClaudeScript -Params $params } | Should -Throw
        }

        It '空のハッシュテーブルで例外をスローすること' {
            { New-RunClaudeScript -Params @{} } | Should -Throw
        }
    }

    Context '有効なパラメータの場合' {

        BeforeAll {
            $script:ValidParams = @{
                Port        = 9222
                LinuxBase   = '/mnt/LinuxHDD'
                ProjectName = 'TestProject'
            }
        }

        It '文字列を返すこと' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -BeOfType [string]
        }

        It '生成されたスクリプトが shebang を含むこと' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '^#!/bin/bash'
        }

        It '生成されたスクリプトにポート番号が含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '9222'
        }

        It '生成されたスクリプトにプロジェクトパスが含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '/mnt/LinuxHDD/TestProject'
        }

        It '生成されたスクリプトに claude コマンドが含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match 'claude'
        }

        It 'InitPrompt を指定した場合にプロンプト内容が含まれること' {
            $params = $script:ValidParams.Clone()
            $params['InitPrompt'] = 'カスタム初期プロンプトです'
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match 'カスタム初期プロンプトです'
        }

        It 'EnvVars を指定した場合に export 文が含まれること' {
            $params = $script:ValidParams.Clone()
            $params['EnvVars'] = @{ MY_CUSTOM_VAR = 'custom_value' }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match 'MY_CUSTOM_VAR'
        }

        It 'TmuxEnabled = $true の場合に tmux セクションが含まれること' {
            $params = $script:ValidParams.Clone()
            $params['TmuxEnabled'] = $true
            $params['Layout']      = 'default'
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match 'tmux'
        }

        It 'Layout を指定した場合にレイアウト名が含まれること' {
            $params = $script:ValidParams.Clone()
            $params['TmuxEnabled'] = $true
            $params['Layout']      = 'review-team'
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match 'review-team'
        }
    }

    Context 'InitPromptFile パラメータの場合' {

        It '存在するファイルからプロンプトを読み込むこと' {
            $promptFile = Join-Path $TestDrive 'prompt.txt'
            Set-Content -Path $promptFile -Value 'ファイルからの初期プロンプト' -Encoding UTF8

            $params = @{
                Port           = 9222
                LinuxBase      = '/mnt/LinuxHDD'
                ProjectName    = 'TestProject'
                InitPromptFile = $promptFile
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match 'ファイルからの初期プロンプト'
        }

        It 'InitPrompt が指定されている場合は InitPromptFile より優先されること' {
            $promptFile = Join-Path $TestDrive 'prompt2.txt'
            Set-Content -Path $promptFile -Value 'ファイルのプロンプト' -Encoding UTF8

            $params = @{
                Port           = 9222
                LinuxBase      = '/mnt/LinuxHDD'
                ProjectName    = 'TestProject'
                InitPrompt     = 'インラインプロンプト優先'
                InitPromptFile = $promptFile
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match 'インラインプロンプト優先'
            $result | Should -Not -Match 'ファイルのプロンプト'
        }

        It '存在しないファイルを指定してもデフォルトプロンプトで動作すること' {
            $params = @{
                Port           = 9222
                LinuxBase      = '/mnt/LinuxHDD'
                ProjectName    = 'TestProject'
                InitPromptFile = Join-Path $TestDrive 'nonexistent_prompt.txt'
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match '#!/bin/bash'
        }
    }

    Context '言語テンプレート自動選択' {

        It 'Language=ja の場合は日本語テンプレートが自動選択されること' {
            $params = @{
                Port        = 9222
                LinuxBase   = '/mnt/LinuxHDD'
                ProjectName = 'TestProject'
                Language    = 'ja'
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match '#!/bin/bash'
        }

        It 'Language=en の場合も正常に動作すること' {
            $params = @{
                Port        = 9222
                LinuxBase   = '/mnt/LinuxHDD'
                ProjectName = 'TestProject'
                Language    = 'en'
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match '#!/bin/bash'
        }

        It 'Language 未指定時はデフォルト(ja)が使われること' {
            $params = @{
                Port        = 9222
                LinuxBase   = '/mnt/LinuxHDD'
                ProjectName = 'TestProject'
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'bash変数エスケープの正確性' {

        It '生成スクリプトに $DEVTOOLS_PORT がリテラルとして含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '\$DEVTOOLS_PORT'
        }

        It '生成スクリプトに $PROJECT_ROOT がリテラルとして含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '\$PROJECT_ROOT'
        }

        It '生成スクリプトに $INIT_PROMPT がリテラルとして含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '\$INIT_PROMPT'
        }

        It '生成スクリプトに $DEVTOOLS_READY がリテラルとして含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '\$DEVTOOLS_READY'
        }

        It '生成スクリプトに $RESTART_ANSWER がリテラルとして含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '\$RESTART_ANSWER'
        }

        It 'バックスラッシュ+ドルがリテラルとして出力されないこと (エスケープ誤り検出)' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            # \$VARIABLE (バックスラッシュ直後にドル) はPowerShellのエスケープ誤り
            # cd "\" のようなパターンが出力されていないことを確認
            $result | Should -Not -Match 'cd "\\"'
            $result | Should -Not -Match 'export CLAUDE_CHROME_DEBUG_PORT="\\"'
        }
    }

    Context 'リスタートループの条件分岐' {

        It 'INIT_PROMPT が非空の場合に対話モードで起動する条件が含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match 'if \[ -n "\$INIT_PROMPT" \]'
        }

        It 'INIT_PROMPT が空の場合にプロンプトなしで起動するelse節が含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match 'claude --dangerously-skip-permissions \|\| true'
        }

        It 'INIT_PROMPT 付きの対話モード起動コマンドが含まれること（-p フラグなし）' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match 'claude --dangerously-skip-permissions "\$INIT_PROMPT"'
        }

        It '-p フラグが使われていないこと（print mode ではなく対話モード）' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Not -Match 'claude --dangerously-skip-permissions -p "\$INIT_PROMPT"'
        }

        It 'INIT_PROMPT 表示用の echo 文が含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match 'echo "\$INIT_PROMPT"'
        }

        It 'プロンプト表示の区切り線が含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '📋 初期プロンプト指示内容'
        }
    }

    Context '再起動モード選択メニュー' {

        It '再起動モード選択の案内メッセージが含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '再起動モードを選択してください'
        }

        It 'プロンプト指示付き再起動オプションが含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match 'プロンプト指示付きで再起動'
        }

        It '対話モード再起動オプションが含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match '対話モードで再起動'
        }

        It 'case文による再起動モード分岐が含まれること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match 'case "\$RESTART_ANSWER" in'
        }

        It 'esac でcase文が閉じられていること' {
            $result = New-RunClaudeScript -Params $script:ValidParams
            $result | Should -Match 'esac'
        }
    }
}
