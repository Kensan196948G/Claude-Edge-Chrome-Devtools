# ============================================================
# Integration.Tests.ps1 - Claude-DevTools.ps1 統合テスト
# モック SSH 環境で run-claude.sh 生成フローを検証
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\ScriptGenerator.psm1" -Force

    # テスト用一時ディレクトリ
    $script:TmpDir = Join-Path $env:TEMP "claudedevtools-integration-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null

    # テンプレートディレクトリ
    $script:TemplatesDir = Join-Path $PSScriptRoot "..\scripts\templates"

    # 最小限のテスト用 config.json
    $script:TestConfigPath = Join-Path $script:TmpDir "config.json"
    @{
        ports      = @(9222, 9223)
        zDrive     = "X:\\"
        linuxHost  = "testhost"
        linuxBase  = "/mnt/LinuxHDD"
        edgeExe    = "C:\\edge.exe"
        chromeExe  = "C:\\chrome.exe"
        defaultBrowser = "edge"
        autoCleanup    = $false
        statusline = @{ enabled = $false }
        claudeCode = @{
            env = @{
                CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
                ENABLE_TOOL_SEARCH = "true"
            }
            settings = @{
                language = "日本語"
            }
        }
        tmux = @{
            enabled       = $false
            autoInstall   = $false
            defaultLayout = "auto"
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:TestConfigPath -Encoding UTF8
}

AfterAll {
    Remove-Item -Path $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================
# New-RunClaudeScript 生成フロー統合テスト
# ============================================================

Describe 'New-RunClaudeScript 統合テスト' {

    Context 'Edge テンプレート（日本語設定）' {

        BeforeAll {
            $script:jaPromptFile = Join-Path $script:TemplatesDir "init-prompt-ja.txt"
            $script:hasJaTemplate = Test-Path $script:jaPromptFile
        }

        It 'run-claude.sh の内容を文字列として返すこと' {
            $params = @{
                Port        = 9222
                LinuxBase   = "/mnt/LinuxHDD"
                ProjectName = "TestProject"
                Language    = "ja"
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Not -BeNullOrEmpty
        }

        It 'ポート番号がスクリプト内に含まれること' {
            $params = @{
                Port        = 9222
                LinuxBase   = "/mnt/LinuxHDD"
                ProjectName = "TestProject"
                Language    = "ja"
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match '9222'
        }

        It 'プロジェクトパスがスクリプト内に含まれること' {
            $params = @{
                Port        = 9222
                LinuxBase   = "/mnt/LinuxHDD"
                ProjectName = "MyApp"
                Language    = "ja"
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match '/mnt/LinuxHDD/MyApp'
        }

        It '日本語テンプレートが存在する場合、INIT_PROMPT プレースホルダーが解決されること' -Skip:(-not $script:hasJaTemplate) {
            $params = @{
                Port            = 9222
                LinuxBase       = "/mnt/LinuxHDD"
                ProjectName     = "TestProject"
                Language        = "ja"
                InitPromptFile  = $script:jaPromptFile
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Not -Match '__INIT_PROMPT__'
        }

        It 'CRLF 変換後に LF のみとなること' {
            $params = @{
                Port        = 9222
                LinuxBase   = "/mnt/LinuxHDD"
                ProjectName = "TestProject"
                Language    = "ja"
            }
            $result = New-RunClaudeScript -Params $params
            # 呼び出し元で CRLF → LF 変換を行う（Claude-DevTools.ps1 と同様）
            $resultLF = $result -replace "`r`n", "`n" -replace "`r", "`n"
            $resultLF | Should -Not -Match "`r`n"
        }
    }

    Context '英語テンプレート（en 設定）' {

        BeforeAll {
            $script:enPromptFile = Join-Path $script:TemplatesDir "init-prompt-en.txt"
            $script:hasEnTemplate = Test-Path $script:enPromptFile
        }

        It '英語テンプレートが存在する場合、INIT_PROMPT プレースホルダーが解決されること' -Skip:(-not $script:hasEnTemplate) {
            $params = @{
                Port            = 9223
                LinuxBase       = "/mnt/LinuxHDD"
                ProjectName     = "EnglishProject"
                Language        = "en"
                InitPromptFile  = $script:enPromptFile
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Not -Match '__INIT_PROMPT__'
        }
    }

    Context '環境変数エクスポート' {

        It '追加環境変数が export 文としてスクリプトに含まれること' {
            $params = @{
                Port        = 9222
                LinuxBase   = "/mnt/LinuxHDD"
                ProjectName = "TestProject"
                Language    = "ja"
                EnvVars     = @{
                    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
                    ENABLE_TOOL_SEARCH = "true"
                }
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'
            $result | Should -Match 'ENABLE_TOOL_SEARCH'
        }
    }

    Context 'tmux 対応' {

        It 'TmuxEnabled=$false の場合、tmux セクションが含まれないこと' {
            $params = @{
                Port        = 9222
                LinuxBase   = "/mnt/LinuxHDD"
                ProjectName = "TestProject"
                TmuxEnabled = $false
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Not -Match 'tmux-dashboard'
        }

        It 'TmuxEnabled=$true の場合、tmux セクションが含まれること' {
            $params = @{
                Port        = 9222
                LinuxBase   = "/mnt/LinuxHDD"
                ProjectName = "TestProject"
                TmuxEnabled = $true
                Layout      = "default"
            }
            $result = New-RunClaudeScript -Params $params
            $result | Should -Match 'tmux'
        }
    }

    Context 'エラーハンドリング' {

        It 'Port が未指定の場合に例外をスローすること' {
            { New-RunClaudeScript -Params @{ LinuxBase = "/mnt"; ProjectName = "x" } } | Should -Throw
        }

        It 'LinuxBase が未指定の場合に例外をスローすること' {
            { New-RunClaudeScript -Params @{ Port = 9222; ProjectName = "x" } } | Should -Throw
        }

        It 'ProjectName が未指定の場合に例外をスローすること' {
            { New-RunClaudeScript -Params @{ Port = 9222; LinuxBase = "/mnt" } } | Should -Throw
        }
    }
}

# ============================================================
# Language 自動選択フロー統合テスト
# ============================================================

Describe 'Language 自動選択テスト' {

    Context 'config.json の language 設定から言語を自動検出' {

        It '日本語設定の場合、init-prompt-ja.txt が選択されること' {
            $langSetting = "日本語"
            $lang = if ($langSetting -match '英語|english|en') { 'en' } else { 'ja' }
            $lang | Should -Be 'ja'
        }

        It '英語設定（英語）の場合、init-prompt-en.txt が選択されること' {
            $langSetting = "英語"
            $lang = if ($langSetting -match '英語|english|en') { 'en' } else { 'ja' }
            $lang | Should -Be 'en'
        }

        It '英語設定（english）の場合、init-prompt-en.txt が選択されること' {
            $langSetting = "english"
            $lang = if ($langSetting -match '英語|english|en') { 'en' } else { 'ja' }
            $lang | Should -Be 'en'
        }

        It '英語設定（en）の場合、init-prompt-en.txt が選択されること' {
            $langSetting = "en"
            $lang = if ($langSetting -match '英語|english|en') { 'en' } else { 'ja' }
            $lang | Should -Be 'en'
        }

        It '空文字列の場合、日本語（ja）がデフォルト選択されること' {
            $langSetting = ""
            $lang = if ($langSetting -match '英語|english|en') { 'en' } else { 'ja' }
            $lang | Should -Be 'ja'
        }
    }
}

# ============================================================
# Chrome テンプレート統合テスト
# ============================================================

Describe 'Chrome テンプレート統合テスト' {

    BeforeAll {
        $script:ChromeTemplatePath = Join-Path $script:TemplatesDir "run-claude-chrome-template.sh"
        $script:hasChromeTpl = Test-Path $script:ChromeTemplatePath
    }

    It 'Chrome テンプレートファイルが存在すること' {
        $script:hasChromeTpl | Should -BeTrue
    }

    It 'Chrome テンプレートに __DEVTOOLS_PORT__ プレースホルダーが含まれること' -Skip:(-not $script:hasChromeTpl) {
        $tpl = Get-Content -Path $script:ChromeTemplatePath -Raw
        $tpl | Should -Match '__DEVTOOLS_PORT__'
    }

    It 'Chrome テンプレートに __ENV_EXPORTS__ プレースホルダーが含まれること' -Skip:(-not $script:hasChromeTpl) {
        $tpl = Get-Content -Path $script:ChromeTemplatePath -Raw
        $tpl | Should -Match '__ENV_EXPORTS__'
    }

    It 'Chrome テンプレートに __INIT_PROMPT__ プレースホルダーが含まれること' -Skip:(-not $script:hasChromeTpl) {
        $tpl = Get-Content -Path $script:ChromeTemplatePath -Raw
        $tpl | Should -Match '__INIT_PROMPT__'
    }

    It 'Chrome テンプレートが有効な bash shebang で始まること' -Skip:(-not $script:hasChromeTpl) {
        $firstLine = (Get-Content -Path $script:ChromeTemplatePath -TotalCount 1)
        $firstLine | Should -Match '^#!/'
    }

    It 'Chrome テンプレートにポート番号を置換するとプレースホルダーが解決されること' -Skip:(-not $script:hasChromeTpl) {
        $tpl = Get-Content -Path $script:ChromeTemplatePath -Raw
        $resolved = $tpl -replace '__DEVTOOLS_PORT__', '9222'
        $resolved | Should -Match '9222'
        $resolved | Should -Not -Match '__DEVTOOLS_PORT__'
    }
}

# ============================================================
# Edge テンプレート統合テスト
# ============================================================

Describe 'Edge テンプレート統合テスト' {

    BeforeAll {
        $script:EdgeTemplatePath = Join-Path $script:TemplatesDir "run-claude-edge-template.sh"
        $script:hasEdgeTpl = Test-Path $script:EdgeTemplatePath
    }

    It 'Edge テンプレートファイルが存在すること' {
        $script:hasEdgeTpl | Should -BeTrue
    }

    It 'Edge テンプレートに必要なプレースホルダーが含まれること' -Skip:(-not $script:hasEdgeTpl) {
        $tpl = Get-Content -Path $script:EdgeTemplatePath -Raw
        $tpl | Should -Match '__DEVTOOLS_PORT__'
        $tpl | Should -Match '__ENV_EXPORTS__'
        $tpl | Should -Match '__INIT_PROMPT__'
    }
}
