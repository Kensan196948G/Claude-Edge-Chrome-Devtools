BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:PowerShellExe = (Get-Process -Id $PID).Path
    $script:OriginalPath = $env:PATH
    $script:OriginalConfigOverride = $env:AI_STARTUP_CONFIG_PATH

    $script:ProjectsRoot = Join-Path $TestDrive 'projects'
    $script:SshProjectsRoot = Join-Path $TestDrive 'ssh-projects'
    $script:BinRoot = Join-Path $TestDrive 'bin'
    $script:RecentHistoryPath = Join-Path $TestDrive 'recent-projects.json'
    $script:LogDir = Join-Path $TestDrive 'logs'

    New-Item -ItemType Directory -Path $script:ProjectsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:SshProjectsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:BinRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:ProjectsRoot 'demo') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:SshProjectsRoot 'demo') -Force | Out-Null

    foreach ($cmd in @('claude', 'codex', 'gh')) {
        $cmdPath = Join-Path $script:BinRoot "$cmd.cmd"
        Set-Content -Path $cmdPath -Encoding ASCII -Value "@echo off`recho $cmd stub"
    }
    $script:SshCaptureRoot = Join-Path $TestDrive 'ssh-capture'

    $config = @{
        version        = '2.0.0'
        projectsDir    = $script:ProjectsRoot
        projectsDirUnc = '\\test-host\projects'
        sshProjectsDir = $script:SshProjectsRoot
        linuxHost      = 'test-linux'
        linuxBase      = '/mnt/LinuxHDD'
        localExcludes  = @()
        tools          = @{
            defaultTool = 'claude'
            claude      = @{
                enabled        = $true
                installCommand = 'npm install -g @anthropic-ai/claude-code'
                args           = @()
                env            = @{}
                apiKeyEnvVar   = 'ANTHROPIC_API_KEY'
            }
            codex       = @{
                enabled        = $true
                installCommand = 'npm install -g @openai/codex'
                args           = @()
                env            = @{}
                apiKeyEnvVar   = 'OPENAI_API_KEY'
            }
            copilot     = @{
                enabled        = $true
                command        = 'gh'
                args           = @('copilot')
                installCommand = 'winget install GitHub.cli'
                env            = @{}
            }
        }
        recentProjects = @{
            enabled = $true
            maxHistory = 10
            historyFile = $script:RecentHistoryPath
        }
        logging = @{
            enabled = $true
            logDir = $script:LogDir
        }
    } | ConvertTo-Json -Depth 10

    $script:ConfigPath = Join-Path $TestDrive 'config.json'
    Set-Content -Path $script:ConfigPath -Value $config -Encoding UTF8

    $env:AI_STARTUP_CONFIG_PATH = $script:ConfigPath
    $env:PATH = "$script:BinRoot;$script:OriginalPath"
    $env:AI_STARTUP_SSH_CAPTURE_DIR = $script:SshCaptureRoot
}

AfterAll {
    $env:PATH = $script:OriginalPath
    $env:AI_STARTUP_CONFIG_PATH = $script:OriginalConfigOverride
    Remove-Item Env:AI_STARTUP_SSH_CAPTURE_DIR -ErrorAction SilentlyContinue
}

Describe 'Start-*.ps1 dry-run flows' {
    It 'Start-ClaudeCode.ps1 がローカル DryRun を実行できること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\main\Start-ClaudeCode.ps1'
        $output = & $script:PowerShellExe -NoProfile -File $scriptPath -Project demo -Local -NonInteractive -DryRun 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match '\[DryRun\].*claude'
        $output | Should -Match 'demo'
    }

    It 'Start-CodexCLI.ps1 がローカル DryRun を実行できること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\main\Start-CodexCLI.ps1'
        $output = & $script:PowerShellExe -NoProfile -File $scriptPath -Project demo -Local -NonInteractive -DryRun 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match '\[DryRun\].*codex'
        $output | Should -Match 'demo'
    }

    It 'Start-CopilotCLI.ps1 がローカル DryRun を実行できること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\main\Start-CopilotCLI.ps1'
        $output = & $script:PowerShellExe -NoProfile -File $scriptPath -Project demo -Local -NonInteractive -DryRun 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match '\[DryRun\].*gh copilot'
        $output | Should -Match 'demo'
    }

    It 'Start-All.ps1 が Claude へ委譲できること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\main\Start-All.ps1'
        $output = & $script:PowerShellExe -NoProfile -File $scriptPath -Tool claude -Project demo -Local -NonInteractive -DryRun 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'Orchestration: Agent Teams'
        $output | Should -Match '\[Architect\]'
        $output | Should -Match 'recent='
        $output | Should -Match '\[QA\]'
        $output | Should -Match '\[Ops\]'
        $output | Should -Match 'Agent Teams Backlog:'
        $output | Should -Match 'Recent Tool: claude'
        $output | Should -Match 'Start-ClaudeCode\.ps1'
        $output | Should -Match '\[DryRun\].*claude'
    }

    It 'DryRun 実行でも recentProjects に結果が記録されること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\main\Start-ClaudeCode.ps1'
        Remove-Item $script:RecentHistoryPath -Force -ErrorAction SilentlyContinue
        $null = & $script:PowerShellExe -NoProfile -File $scriptPath -Project demo -Local -NonInteractive -DryRun 2>&1 | Out-String
        $history = Get-Content $script:RecentHistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $history.projects[0].result | Should -Be 'success'
        ([int]$history.projects[0].elapsedMs) | Should -BeGreaterThan -1
        $metadataPath = Join-Path $script:LogDir ("launch-metadata-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd'))
        (Test-Path $metadataPath) | Should -BeTrue
        (Get-Content $metadataPath -Raw -Encoding UTF8) | Should -Match '"project":"demo"'
        (Get-Content $metadataPath -Raw -Encoding UTF8) | Should -Match '"tool":"claude"'
    }

    It 'Start-ClaudeCode.ps1 が SSH 実行経路を通過できること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\main\Start-ClaudeCode.ps1'
        Remove-Item $script:SshCaptureRoot -Recurse -Force -ErrorAction SilentlyContinue
        $output = & $script:PowerShellExe -NoProfile -File $scriptPath -Project demo -NonInteractive 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'SSH_CAPTURE'
        (Get-Content (Join-Path $script:SshCaptureRoot 'script-name.txt') -Raw) | Should -Match 'run-claude-demo\.sh'
        (Get-Content (Join-Path $script:SshCaptureRoot 'script.sh') -Raw) | Should -Match 'claude'
    }

    It 'Start-CodexCLI.ps1 が SSH 実行経路を通過できること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\main\Start-CodexCLI.ps1'
        Remove-Item $script:SshCaptureRoot -Recurse -Force -ErrorAction SilentlyContinue
        $output = & $script:PowerShellExe -NoProfile -File $scriptPath -Project demo -NonInteractive 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'SSH_CAPTURE'
        (Get-Content (Join-Path $script:SshCaptureRoot 'script-name.txt') -Raw) | Should -Match 'run-codex-demo\.sh'
        (Get-Content (Join-Path $script:SshCaptureRoot 'script.sh') -Raw) | Should -Match 'codex'
    }

    It 'Start-CopilotCLI.ps1 が SSH 実行経路を通過できること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\main\Start-CopilotCLI.ps1'
        Remove-Item $script:SshCaptureRoot -Recurse -Force -ErrorAction SilentlyContinue
        $output = & $script:PowerShellExe -NoProfile -File $scriptPath -Project demo -NonInteractive 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'SSH_CAPTURE'
        (Get-Content (Join-Path $script:SshCaptureRoot 'script-name.txt') -Raw) | Should -Match 'run-copilot-demo\.sh'
        (Get-Content (Join-Path $script:SshCaptureRoot 'script.sh') -Raw) | Should -Match 'copilot'
    }
}

Describe 'Start-Menu helper flows' {
    BeforeAll {
        $script:MenuConfigPath = Join-Path $TestDrive 'menu-startscripts-config.json'
        $script:MenuHistoryPath = Join-Path $TestDrive 'menu-startscripts-history.json'
        @{
            version = '2.0.0'
            projectsDir = $script:ProjectsRoot
            sshProjectsDir = $script:SshProjectsRoot
            projectsDirUnc = '\\test-host\projects'
            linuxHost = 'test-linux'
            linuxBase = '/mnt/LinuxHDD'
            localExcludes = @()
            tools = @{
                defaultTool = 'claude'
                claude = @{ enabled = $true; command = 'claude'; args = @(); installCommand = 'install-claude'; env = @{}; apiKeyEnvVar = 'ANTHROPIC_API_KEY' }
                codex = @{ enabled = $true; command = 'codex'; args = @(); installCommand = 'install-codex'; env = @{}; apiKeyEnvVar = 'OPENAI_API_KEY' }
                copilot = @{ enabled = $true; command = 'gh'; args = @('copilot'); installCommand = 'install-copilot'; env = @{} }
            }
            recentProjects = @{
                enabled = $true
                maxHistory = 10
                historyFile = $script:MenuHistoryPath
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:MenuConfigPath -Encoding UTF8

        $env:AI_STARTUP_CONFIG_PATH = $script:MenuConfigPath
        $env:AI_STARTUP_MENU_TEST_EXPORT = '1'
        . (Join-Path $script:RepoRoot 'scripts\main\Start-Menu.ps1')
    }

    BeforeEach {
        @{
            projects = @(
                @{ project = 'demo-claude'; tool = 'claude'; mode = 'ssh'; timestamp = '2026-03-13T10:00:00+09:00'; result = 'failure'; elapsedMs = 3000 },
                @{ project = 'demo-codex'; tool = 'codex'; mode = 'local'; timestamp = '2026-03-13T11:00:00+09:00'; result = 'success'; elapsedMs = 1200 },
                @{ project = 'demo-copilot'; tool = 'copilot'; mode = 'local'; timestamp = '2026-03-13T12:00:00+09:00'; result = 'success'; elapsedMs = 800 }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:MenuHistoryPath -Encoding UTF8
    }

    AfterAll {
        Remove-Item Env:AI_STARTUP_MENU_TEST_EXPORT -ErrorAction SilentlyContinue
        $env:AI_STARTUP_CONFIG_PATH = $script:OriginalConfigOverride
    }

    It 'recent filter/search で codex の project を絞り込めること' {
        $entries = @(Get-FilteredRecentProjects -Entries @(Get-RecentProjects -HistoryPath $script:MenuHistoryPath) -ToolFilter 'codex' -SearchQuery 'demo' -SortMode 'success')
        $entries.Count | Should -Be 1
        $entries[0].project | Should -Be 'demo-codex'
    }

    It 'recent projects を elapsed sort に切り替えられること' {
        $entries = @(Get-SortedRecentProjects -Entries @(Get-RecentProjects -HistoryPath $script:MenuHistoryPath) -SortMode 'elapsed')
        $entries[0].project | Should -Be 'demo-copilot'
    }
}

