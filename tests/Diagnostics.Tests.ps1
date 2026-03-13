BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'scripts\test\test-drive-mapping.ps1')
    . (Join-Path $script:RepoRoot 'scripts\test\Test-AllTools.ps1')
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\MenuCommon.psm1') -Force
    $script:PowerShellExe = (Get-Process -Id $PID).Path
}

Describe 'Get-DriveMappingReport' {
    It '直接アクセス可能な共有ドライブ情報を返すこと' {
        Mock Test-Path {
            param($Path)
            switch ($Path) {
                'Z:\' { $true }
                'HKCU:\Network\Z' { $true }
                '\\server\share' { $true }
                default { $false }
            }
        }
        Mock Get-ChildItem { @([pscustomobject]@{ Name = 'a' }, [pscustomobject]@{ Name = 'b' }) }
        Mock Get-ItemProperty { [pscustomobject]@{ RemotePath = '\\server\share' } }
        Mock Get-SmbMapping { [pscustomobject]@{ LocalPath = 'Z:'; RemotePath = '\\server\share'; Status = 'OK' } }
        Mock Get-PSDrive { [pscustomobject]@{ Root = 'Z:\'; DisplayRoot = '\\server\share'; Provider = 'FileSystem' } }
        Mock Get-NetUseLine { 'OK Z: \\server\share' }

        $configInfo = [pscustomobject]@{
            sshProjectsDir = 'Z:\'
            projectsDirUnc = '\\server\share'
            linuxHost = 'host'
            configFound = $true
        }

        $report = Get-DriveMappingReport -ConfigInfo $configInfo
        $report.directAccess | Should -Be $true
        $report.directoryCount | Should -Be 2
        $report.registryRemotePath | Should -Be '\\server\share'
        $report.recommendation | Should -Be 'DirectAccess'
    }

    It 'マッピングが無ければ MissingMapping を返すこと' {
        Mock Test-Path { $false }
        Mock Get-ChildItem { @() }
        Mock Get-ItemProperty { [pscustomobject]@{} }
        Mock Get-SmbMapping { param($ErrorAction) $null }
        Mock Get-PSDrive { param($Name, $ErrorAction) $null }
        Mock Get-NetUseLine { $null }

        $configInfo = [pscustomobject]@{
            sshProjectsDir = 'Z:\'
            projectsDirUnc = $null
            linuxHost = 'host'
            configFound = $true
        }

        $report = Get-DriveMappingReport -ConfigInfo $configInfo
        $report.directAccess | Should -Be $false
        $report.uncCandidates.Count | Should -Be 0
        $report.recommendation | Should -Be 'MissingMapping'
        $report.remapCommand | Should -Match 'New-PSDrive'
        $report.repairAdvice.Count | Should -BeGreaterThan 0
    }

    It 'SMB 切断時は再マッピング提案を返すこと' {
        Mock Test-Path {
            param($Path)
            switch ($Path) {
                'Z:\' { $false }
                'HKCU:\Network\Z' { $true }
                '\\server\share' { $true }
                default { $false }
            }
        }
        Mock Get-ChildItem { @() }
        Mock Get-ItemProperty { [pscustomobject]@{ RemotePath = '\\server\share' } }
        Mock Get-SmbMapping { [pscustomobject]@{ LocalPath = 'Z:'; RemotePath = '\\server\share'; Status = 'Disconnected' } }
        Mock Get-PSDrive { [pscustomobject]@{ Root = 'Z:\'; DisplayRoot = '\\server\share'; Provider = 'FileSystem' } }
        Mock Get-NetUseLine { 'Disconnected Z: \\server\share' }

        $configInfo = [pscustomobject]@{
            sshProjectsDir = 'Z:\'
            projectsDirUnc = '\\server\share'
            linuxHost = 'host'
            configFound = $true
        }

        $report = Get-DriveMappingReport -ConfigInfo $configInfo
        $report.recommendation | Should -Be 'RemapDisconnectedSmb'
        $report.remapCommand | Should -Match 'Remove-PSDrive'
    }

    It '資格情報エラー時は再認証提案を返すこと' {
        Mock Test-Path { $false }
        Mock Get-ChildItem { @() }
        Mock Get-ItemProperty { [pscustomobject]@{} }
        Mock Get-SmbMapping { param($ErrorAction) $null }
        Mock Get-PSDrive { param($Name, $ErrorAction) $null }
        Mock Get-NetUseLine { 'System error 1219 has occurred. credential conflict' }

        $configInfo = [pscustomobject]@{
            sshProjectsDir = 'Z:\'
            projectsDirUnc = '\\server\share'
            linuxHost = 'host'
            configFound = $true
        }

        $report = Get-DriveMappingReport -ConfigInfo $configInfo
        $report.netUseIssue | Should -Be 'CredentialError'
        $report.recommendation | Should -Be 'CheckCredentials'
    }

    It '名前解決失敗時は DNS 確認提案を返すこと' {
        Mock Test-Path { $false }
        Mock Get-ChildItem { @() }
        Mock Get-ItemProperty { [pscustomobject]@{} }
        Mock Get-SmbMapping { param($ErrorAction) $null }
        Mock Get-PSDrive { param($Name, $ErrorAction) $null }
        Mock Get-NetUseLine { 'System error 53 has occurred. The network path was not found.' }

        $configInfo = [pscustomobject]@{
            sshProjectsDir = 'Z:\'
            projectsDirUnc = '\\server\share'
            linuxHost = 'host'
            configFound = $true
        }

        $report = Get-DriveMappingReport -ConfigInfo $configInfo
        $report.netUseIssue | Should -Be 'NameResolutionFailure'
        $report.recommendation | Should -Be 'CheckNameResolution'
    }

    It 'SMB 445 が閉じている場合は SMB ポート確認提案を返すこと' {
        Mock Test-Path { $false }
        Mock Get-ChildItem { @() }
        Mock Get-ItemProperty { [pscustomobject]@{ RemotePath = '\\server\share' } }
        Mock Get-SmbMapping { param($ErrorAction) $null }
        Mock Get-PSDrive { param($Name, $ErrorAction) $null }
        Mock Get-NetUseLine { $null }
        Mock Resolve-DnsName { [pscustomobject]@{ Name = 'server' } }
        Mock Test-Connection { $true }
        Mock Test-NetConnection { $false }

        $configInfo = [pscustomobject]@{
            sshProjectsDir = 'Z:\'
            projectsDirUnc = '\\server\share'
            linuxHost = 'host'
            configFound = $true
        }

        $report = Get-DriveMappingReport -ConfigInfo $configInfo
        $report.smbPort445Reachable | Should -BeFalse
        $report.recommendation | Should -Be 'CheckSmbPort445'
    }

    It 'UNC 候補から net use 再接続コマンドを生成すること' {
        Mock Test-Path { $false }
        Mock Get-ChildItem { @() }
        Mock Get-ItemProperty { [pscustomobject]@{ RemotePath = '\\server\share' } }
        Mock Get-SmbMapping { [pscustomobject]@{ LocalPath = 'Z:'; RemotePath = '\\server\share'; Status = 'Disconnected' } }
        Mock Get-PSDrive { [pscustomobject]@{ Root = 'Z:\'; DisplayRoot = '\\server\share'; Provider = 'FileSystem' } }
        Mock Get-NetUseLine { 'Disconnected Z: \\server\share' }

        $configInfo = [pscustomobject]@{
            sshProjectsDir = 'Z:\'
            projectsDirUnc = '\\server\share'
            linuxHost = 'host'
            configFound = $true
        }

        $report = Get-DriveMappingReport -ConfigInfo $configInfo
        (@($report.reconnectCommands | Where-Object { $_ -match 'net use Z:' })).Count | Should -BeGreaterThan 0
    }
}

Describe 'Test-AllTools Json output' {
    BeforeAll {
        $script:OriginalPath = $env:PATH
        $script:OriginalConfigOverride = $env:AI_STARTUP_CONFIG_PATH
        $script:OriginalMcpConfigOverride = $env:AI_STARTUP_MCP_CONFIG_PATH
        $script:BinRoot = Join-Path $TestDrive 'diag-bin'
        $script:ProjectsRoot = Join-Path $TestDrive 'diag-projects'
        New-Item -ItemType Directory -Force -Path $script:BinRoot, $script:ProjectsRoot, (Join-Path $script:ProjectsRoot 'demo') | Out-Null

        Set-Content -Path (Join-Path $script:BinRoot 'claude.cmd') -Encoding ASCII -Value @'
@echo off
if "%1"=="--version" (
  echo claude 1.0
  exit /b 0
)
echo claude stub
'@
        Set-Content -Path (Join-Path $script:BinRoot 'codex.cmd') -Encoding ASCII -Value @'
@echo off
if "%1"=="--version" (
  echo codex 1.0
  exit /b 0
)
echo codex stub
'@
        Set-Content -Path (Join-Path $script:BinRoot 'gh.cmd') -Encoding ASCII -Value @'
@echo off
if "%1"=="--version" (
  echo gh 1.0
  exit /b 0
)
if "%1"=="copilot" if "%2"=="--version" (
  echo gh-copilot 1.0
  exit /b 0
)
if "%1"=="auth" if "%2"=="status" (
  exit /b 0
)
echo gh stub
'@
        Set-Content -Path (Join-Path $script:BinRoot 'node.cmd') -Encoding ASCII -Value @'
@echo off
echo v20.0.0
'@
        Set-Content -Path (Join-Path $script:BinRoot 'npm.cmd') -Encoding ASCII -Value @'
@echo off
echo 10.0.0
'@
        Set-Content -Path (Join-Path $script:BinRoot 'git.cmd') -Encoding ASCII -Value @'
@echo off
echo git version 2.0.0
'@
        Set-Content -Path (Join-Path $script:BinRoot 'ssh.cmd') -Encoding ASCII -Value @'
@echo off
echo OpenSSH_9
'@

        $config = @{
            version = '2.0.0'
            projectsDir = $script:ProjectsRoot
            sshProjectsDir = $script:ProjectsRoot
            projectsDirUnc = '\\server\share'
            linuxHost = 'host'
            linuxBase = '/mnt/LinuxHDD'
            localExcludes = @()
            tools = @{
                defaultTool = 'claude'
                claude = @{ enabled = $true; command = 'claude'; args = @(); installCommand = 'install-claude'; env = @{}; apiKeyEnvVar = 'ANTHROPIC_API_KEY' }
                codex = @{ enabled = $true; command = 'codex'; args = @(); installCommand = 'install-codex'; env = @{ OPENAI_API_KEY = '' }; apiKeyEnvVar = 'OPENAI_API_KEY' }
                copilot = @{ enabled = $true; command = 'gh'; args = @('copilot'); installCommand = 'install-copilot'; env = @{} }
            }
        } | ConvertTo-Json -Depth 10

        $script:ConfigPath = Join-Path $TestDrive 'diag-config.json'
        Set-Content -Path $script:ConfigPath -Value $config -Encoding UTF8
        $script:McpConfigPath = Join-Path $TestDrive 'diag-mcp.json'
        @{
            mcpServers = @{
                memory = @{ command = 'node'; args = @('memory.js'); startupCommand = @('node', 'memory.js', '--start'); healthCommand = @('node', '--version'); shutdownCommand = @('node', 'memory.js', '--stop'); healthCommandTimeoutSec = 3 }
                browser = @{ command = 'missing-mcp'; args = @() }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:McpConfigPath -Encoding UTF8
        $env:AI_STARTUP_CONFIG_PATH = $script:ConfigPath
        $env:AI_STARTUP_MCP_CONFIG_PATH = $script:McpConfigPath
        $env:PATH = "$script:BinRoot;$script:OriginalPath"
    }

    AfterAll {
        $env:PATH = $script:OriginalPath
        $env:AI_STARTUP_CONFIG_PATH = $script:OriginalConfigOverride
        $env:AI_STARTUP_MCP_CONFIG_PATH = $script:OriginalMcpConfigOverride
    }

    It 'JSON 出力が機械可読であること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\test\Test-AllTools.ps1'
        $raw = & $script:PowerShellExe -NoProfile -File $scriptPath -OutputFormat Json 2>$null
        $report = $raw | ConvertFrom-Json
        $report.schemaVersion | Should -Be '1.0.0'
        $report.configExists | Should -Be $true
        $report.schemaValid | Should -Be $true
        ($report.tools | Where-Object id -eq 'copilot') | Should -Not -BeNullOrEmpty
        $report.mcp | Should -Not -BeNullOrEmpty
        $report.mcp.configured | Should -Be $true
        (@($report.mcp.servers | Where-Object name -eq 'memory')).Count | Should -Be 1
        (@($report.mcp.connections | Where-Object name -eq 'memory')).Count | Should -Be 1
        (@($report.mcp.servers | Where-Object name -eq 'memory'))[0].startupCommand[0] | Should -Be 'node'
        (@($report.mcp.servers | Where-Object name -eq 'memory'))[0].shutdownCommand[0] | Should -Be 'node'
        $report.examples.Count | Should -Be 3
    }

    It 'JSON スキーマ検証関数が通ること' {
        $report = Get-AllToolsDiagnostics -ConfigPath $script:ConfigPath
        $errors = Test-AllToolsReportSchema -Report $report
        $errors | Should -BeNullOrEmpty
    }

    It 'MCP server の運用手順を connections に含めること' {
        $report = Get-AllToolsDiagnostics -ConfigPath $script:ConfigPath
        $memoryConnection = @($report.mcp.connections | Where-Object name -eq 'memory')[0]
        $memoryConnection.kind | Should -Be 'memory'
        $memoryConnection.operatingProcedure.startup | Should -Match 'memory.js --start'
        $memoryConnection.operatingProcedure.shutdown | Should -Match 'memory.js --stop'
        $memoryConnection.runtimeProbe.enabled | Should -BeFalse
    }

    It 'MCP server の startup/shutdown timeout を返すこと' {
        $report = Get-AllToolsDiagnostics -ConfigPath $script:ConfigPath
        $memoryServer = @($report.mcp.servers | Where-Object name -eq 'memory')[0]
        $memoryServer.startupCommandTimeoutSec | Should -Be 10
        $memoryServer.shutdownCommandTimeoutSec | Should -Be 10
    }

    It 'MCP config parse failure を summary に反映すること' {
        Set-Content -Path $script:McpConfigPath -Value '{invalid-json' -Encoding UTF8
        $report = Get-AllToolsDiagnostics -ConfigPath $script:ConfigPath
        $report.mcp.summary | Should -Match '解析に失敗'
    }

    It 'MCP unavailable command を unavailable として返すこと' {
        @{
            mcpServers = @{
                browser = @{ command = 'missing-mcp'; args = @(); healthCommand = @('missing-health') }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:McpConfigPath -Encoding UTF8
        $report = Get-AllToolsDiagnostics -ConfigPath $script:ConfigPath
        $server = $report.mcp.servers | Where-Object name -eq 'browser'
        $server.status | Should -Be 'unavailable'
        $server.healthStatus | Should -Be 'health_command_unavailable'
    }

    It 'MCP health fail を unhealthy として返すこと' {
        @{
            mcpServers = @{
                memory = @{ command = 'node'; args = @('memory.js'); healthCommand = @($script:PowerShellExe, '-NoProfile', '-Command', 'Write-Output fail; exit 1'); healthCommandTimeoutSec = 2 }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:McpConfigPath -Encoding UTF8
        $report = Get-AllToolsDiagnostics -ConfigPath $script:ConfigPath
        $server = @($report.mcp.servers | Where-Object name -eq 'memory')[0]
        $server.healthStatus | Should -Be 'unhealthy'
    }

    It 'MCP health timeout を timeout として返すこと' {
        @{
            mcpServers = @{
                memory = @{ command = 'node'; args = @('memory.js'); healthCommand = @('ping', '127.0.0.1', '-n', '6'); healthCommandTimeoutSec = 1 }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:McpConfigPath -Encoding UTF8
        $report = Get-AllToolsDiagnostics -ConfigPath $script:ConfigPath
        $server = @($report.mcp.servers | Where-Object name -eq 'memory')[0]
        $server.healthStatus | Should -Be 'timeout'
        $server.healthOutput | Should -Match 'timed out'
    }

    It 'runtime probe 有効時は startup/shutdown 結果を connections に含めること' {
        $originalProbe = $env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE
        try {
            $env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE = '1'
            @{
                mcpServers = @{
                    memory = @{
                        command = 'node'
                        args = @('memory.js')
                        startupCommand = @('node', '--version')
                        startupCommandTimeoutSec = 2
                        healthCommand = @('node', '--version')
                        shutdownCommand = @('node', '--version')
                        shutdownCommandTimeoutSec = 2
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:McpConfigPath -Encoding UTF8
            $report = Get-AllToolsDiagnostics -ConfigPath $script:ConfigPath
            $connection = @($report.mcp.connections | Where-Object name -eq 'memory')[0]
            $connection.runtimeProbe.enabled | Should -BeTrue
            $connection.runtimeProbe.startupStatus | Should -Be 'started'
            $connection.runtimeProbe.shutdownStatus | Should -Be 'stopped'
        }
        finally {
            if ($null -eq $originalProbe) {
                Remove-Item Env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE -ErrorAction SilentlyContinue
            }
            else {
                $env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE = $originalProbe
            }
        }
    }
}

Describe 'setup-windows-terminal.ps1 non-interactive' {
    It '既定プロファイル化と開始ディレクトリ指定を書き込めること' {
        $settingsPath = Join-Path $TestDrive 'wt\settings.json'
        $scriptPath = Join-Path $script:RepoRoot 'scripts\setup\setup-windows-terminal.ps1'
        & $script:PowerShellExe -NoProfile -File $scriptPath -SettingsPath $settingsPath -StartingDirectory 'D:\Work' -SetAsDefault -Theme 'Campbell' -FontSize 20 -FontFace 'Fira Code' -Opacity 90 -UseAcrylic:$false -NonInteractive | Out-Null
        $LASTEXITCODE | Should -Be 0

        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile = $settings.profiles.list | Where-Object name -eq 'AI CLI Startup'
        $profile.startingDirectory | Should -Be 'D:\Work'
        $profile.colorScheme | Should -Be 'Campbell'
        $profile.font.face | Should -Be 'Fira Code'
        $profile.font.size | Should -Be 20
        $profile.opacity | Should -Be 90
        $profile.useAcrylic | Should -BeFalse
        $settings.defaultProfile | Should -Be $profile.guid
    }

    It '既存プロファイルを上書き更新できること' {
        $settingsPath = Join-Path $TestDrive 'wt-update\settings.json'
        $settingsDir = Split-Path -Parent $settingsPath
        New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
        $seed = @{
            profiles = @{
                list = @(
                    @{
                        name = 'AI CLI Startup'
                        guid = '{11111111-1111-1111-1111-111111111111}'
                        startingDirectory = 'C:\Old'
                        colorScheme = 'One Half Light'
                        font = @{ size = 14 }
                        opacity = 80
                    }
                )
            }
            schemes = @()
        } | ConvertTo-Json -Depth 8
        Set-Content -Path $settingsPath -Value $seed -Encoding UTF8

        $scriptPath = Join-Path $script:RepoRoot 'scripts\setup\setup-windows-terminal.ps1'
        & $script:PowerShellExe -NoProfile -File $scriptPath -SettingsPath $settingsPath -StartingDirectory 'D:\New' -Theme 'One Half Dark' -FontSize 16 -FontFace 'Cascadia Mono' -Opacity 88 -UseAcrylic:$true -NonInteractive | Out-Null
        $LASTEXITCODE | Should -Be 0

        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile = $settings.profiles.list | Where-Object name -eq 'AI CLI Startup'
        $profile.guid | Should -Be '{11111111-1111-1111-1111-111111111111}'
        $profile.startingDirectory | Should -Be 'D:\New'
        $profile.colorScheme | Should -Be 'One Half Dark'
        $profile.font.face | Should -Be 'Cascadia Mono'
        $profile.font.size | Should -Be 16
        $profile.opacity | Should -Be 88
        $profile.useAcrylic | Should -BeTrue
    }

    It '外部テーマ JSON を読み込めること' {
        $settingsPath = Join-Path $TestDrive 'wt-theme\settings.json'
        $themePath = Join-Path $TestDrive 'wt-theme\scheme.json'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsPath) | Out-Null
        @'
{
  "name": "Custom Daylight",
  "background": "#FFFFFF",
  "foreground": "#111111"
}
'@ | Set-Content -Path $themePath -Encoding UTF8

        $scriptPath = Join-Path $script:RepoRoot 'scripts\setup\setup-windows-terminal.ps1'
        & $script:PowerShellExe -NoProfile -File $scriptPath -SettingsPath $settingsPath -ThemeJsonPath $themePath -NonInteractive | Out-Null
        $LASTEXITCODE | Should -Be 0

        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile = $settings.profiles.list | Where-Object name -eq 'AI CLI Startup'
        $profile.colorScheme | Should -Be 'Custom Daylight'
        ($settings.schemes | Where-Object name -eq 'Custom Daylight') | Should -Not -BeNullOrEmpty
    }

    It '複数プロファイルと profile 名指定ができること' {
        $settingsPath = Join-Path $TestDrive 'wt-multi\settings.json'
        $scriptPath = Join-Path $script:RepoRoot 'scripts\setup\setup-windows-terminal.ps1'
        & $script:PowerShellExe -NoProfile -File $scriptPath -SettingsPath $settingsPath -ProfileName 'AI CLI Main' -AdditionalProfileNames 'AI CLI Ops','AI CLI QA' -NonInteractive | Out-Null
        $LASTEXITCODE | Should -Be 0

        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        ($settings.profiles.list | Where-Object name -eq 'AI CLI Main') | Should -Not -BeNullOrEmpty
        ($settings.profiles.list | Where-Object name -eq 'AI CLI Ops') | Should -Not -BeNullOrEmpty
        ($settings.profiles.list | Where-Object name -eq 'AI CLI QA') | Should -Not -BeNullOrEmpty
    }

    It 'profile ごとの starting directory と theme を上書きできること' {
        $settingsPath = Join-Path $TestDrive 'wt-overrides\settings.json'
        $overridesPath = Join-Path $TestDrive 'wt-overrides\profiles.json'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsPath) | Out-Null
        @'
[
  { "name": "AI CLI Main", "startingDirectory": "D:\\Main", "theme": "Campbell" },
  { "name": "AI CLI Ops", "startingDirectory": "D:\\Ops", "theme": "One Half Dark" }
]
'@ | Set-Content -Path $overridesPath -Encoding UTF8

        $scriptPath = Join-Path $script:RepoRoot 'scripts\setup\setup-windows-terminal.ps1'
        & $script:PowerShellExe -NoProfile -File $scriptPath -SettingsPath $settingsPath -ProfileName 'AI CLI Main' -AdditionalProfileNames 'AI CLI Ops' -ProfileOverridesJsonPath $overridesPath -NonInteractive | Out-Null
        $LASTEXITCODE | Should -Be 0

        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        ($settings.profiles.list | Where-Object name -eq 'AI CLI Main').startingDirectory | Should -Be 'D:\Main'
        ($settings.profiles.list | Where-Object name -eq 'AI CLI Main').colorScheme | Should -Be 'Campbell'
        ($settings.profiles.list | Where-Object name -eq 'AI CLI Ops').startingDirectory | Should -Be 'D:\Ops'
        ($settings.profiles.list | Where-Object name -eq 'AI CLI Ops').colorScheme | Should -Be 'One Half Dark'
    }

    It 'profile ごとの icon / font / opacity を上書きできること' {
        $settingsPath = Join-Path $TestDrive 'wt-visual\settings.json'
        $overridesPath = Join-Path $TestDrive 'wt-visual\profiles.json'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsPath) | Out-Null
        @'
[
  { "name": "AI CLI Main", "icon": "D:\\Icons\\main.ico", "fontFace": "Fira Code", "fontSize": 21, "opacity": 87 }
]
'@ | Set-Content -Path $overridesPath -Encoding UTF8

        $scriptPath = Join-Path $script:RepoRoot 'scripts\setup\setup-windows-terminal.ps1'
        & $script:PowerShellExe -NoProfile -File $scriptPath -SettingsPath $settingsPath -ProfileName 'AI CLI Main' -ProfileOverridesJsonPath $overridesPath -NonInteractive | Out-Null
        $LASTEXITCODE | Should -Be 0

        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile = ($settings.profiles.list | Where-Object name -eq 'AI CLI Main')
        $profile.icon | Should -Be 'D:\Icons\main.ico'
        $profile.font.face | Should -Be 'Fira Code'
        $profile.font.size | Should -Be 21
        $profile.opacity | Should -Be 87
    }

    It 'profile ごとの background image / color scheme を上書きできること' {
        $settingsPath = Join-Path $TestDrive 'wt-background\settings.json'
        $overridesPath = Join-Path $TestDrive 'wt-background\profiles.json'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsPath) | Out-Null
        @'
[
  { "name": "AI CLI Main", "colorScheme": "Campbell", "backgroundImage": "D:\\Walls\\ops.png" }
]
'@ | Set-Content -Path $overridesPath -Encoding UTF8

        $scriptPath = Join-Path $script:RepoRoot 'scripts\setup\setup-windows-terminal.ps1'
        & $script:PowerShellExe -NoProfile -File $scriptPath -SettingsPath $settingsPath -ProfileName 'AI CLI Main' -ProfileOverridesJsonPath $overridesPath -NonInteractive | Out-Null
        $LASTEXITCODE | Should -Be 0

        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile = ($settings.profiles.list | Where-Object name -eq 'AI CLI Main')
        $profile.colorScheme | Should -Be 'Campbell'
        $profile.backgroundImage | Should -Be 'D:\Walls\ops.png'
    }
}

Describe 'Start-Menu recent projects' {
    BeforeAll {
        $script:MenuConfigPath = Join-Path $TestDrive 'menu-config.json'
        $script:MenuHistoryPath = Join-Path $TestDrive 'recent-projects.json'
        @{
            version = '2.0.0'
            projectsDir = 'D:\Projects'
            sshProjectsDir = 'Z:\'
            projectsDirUnc = '\\server\share'
            linuxHost = 'host'
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
                maxHistory = 5
                historyFile = $script:MenuHistoryPath
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:MenuConfigPath -Encoding UTF8
        @{
            projects = @(
                @{ project = 'demo-local'; tool = 'codex'; mode = 'local'; timestamp = '2026-03-13T10:00:00+09:00'; result = 'success'; elapsedMs = 1200 },
                @{ project = 'demo-ssh'; tool = 'claude'; mode = 'ssh'; timestamp = '2026-03-13T09:00:00+09:00'; result = 'failure'; elapsedMs = 900 }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:MenuHistoryPath -Encoding UTF8

        $env:AI_STARTUP_CONFIG_PATH = $script:MenuConfigPath
        $env:AI_STARTUP_MENU_TEST_EXPORT = '1'
        . (Join-Path $script:RepoRoot 'scripts\main\Start-Menu.ps1')
    }

    BeforeEach {
        @{
            projects = @(
                @{ project = 'demo-local'; tool = 'codex'; mode = 'local'; timestamp = '2026-03-13T10:00:00+09:00'; result = 'success'; elapsedMs = 1200 },
                @{ project = 'demo-ssh'; tool = 'claude'; mode = 'ssh'; timestamp = '2026-03-13T09:00:00+09:00'; result = 'failure'; elapsedMs = 900 }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:MenuHistoryPath -Encoding UTF8
    }

    AfterAll {
        Remove-Item Env:AI_STARTUP_MENU_TEST_EXPORT -ErrorAction SilentlyContinue
        Remove-Item Env:AI_STARTUP_CONFIG_PATH -ErrorAction SilentlyContinue
    }

    It 'recent projects 表示ラベルに tool と mode が含まれること' {
        $recent = Get-RecentProjects -HistoryPath $script:MenuHistoryPath
        $label = Get-RecentProjectLabel -Entry $recent[0]
        $label | Should -Match 'demo-local \[codex/Local/OK\]'
        $label | Should -Match '1200ms'
        $label | Should -Match 'success 100%'
    }

    It 'R1 起動導線が保存済み tool と mode を再現すること' {
        $recent = Get-RecentProjects -HistoryPath $script:MenuHistoryPath
        $launchSpec = Get-RecentProjectLaunchSpec -Entry $recent[0]
        $launchSpec.file | Should -Be 'scripts\main\Start-CodexCLI.ps1'
        $launchSpec.scriptArgs | Should -Contain '-Local'
        $launchSpec.scriptArgs | Should -Contain 'demo-local'
    }

    It 'legacy と新形式が混在しても成功結果を優先して並び替えること' {
        @{
            projects = @(
                'legacy-project',
                @{ project = 'failed-project'; tool = 'claude'; mode = 'ssh'; timestamp = '2026-03-13T12:00:00+09:00'; result = 'failure' },
                @{ project = 'good-project'; tool = 'copilot'; mode = 'local'; timestamp = '2026-03-13T11:00:00+09:00'; result = 'success' }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:MenuHistoryPath -Encoding UTF8

        $entries = Get-SortedRecentProjects -Entries @(Get-RecentProjects -HistoryPath $script:MenuHistoryPath)
        $entries[0].project | Should -Be 'good-project'
        $entries[-1].project | Should -Be 'failed-project'
    }

    It 'recent projects の表示色が最終結果に応じて変わること' {
        $recent = Get-RecentProjects -HistoryPath $script:MenuHistoryPath
        (Get-RecentProjectColor -Entry $recent[0]) | Should -BeIn @('Green', 'Red', 'Yellow', 'Cyan')
    }

    It 'tool filter と search query で recent projects を絞り込めること' {
        $entries = @(Get-FilteredRecentProjects -Entries @(Get-RecentProjects -HistoryPath $script:MenuHistoryPath) -ToolFilter 'codex' -SearchQuery 'demo' -SortMode 'success')
        $entries.Count | Should -Be 1
        $entries[0].project | Should -Be 'demo-local'
    }

    It 'sort mode=timestamp で最新時刻順に並ぶこと' {
        $entries = @(Get-SortedRecentProjects -Entries @(Get-RecentProjects -HistoryPath $script:MenuHistoryPath) -SortMode 'timestamp')
        $entries[0].project | Should -Be 'demo-local'
    }

    It 'menu helper が filter と sort を正規化できること' {
        (Normalize-MenuRecentToolFilter -ToolFilter 'all') | Should -Be ''
        (Normalize-MenuRecentSortMode -SortMode 'invalid') | Should -Be 'success'
    }
}

Describe 'TASKS tooling' {
    It 'Update-TASKS.ps1 が metadata 付きで追加できること' {
        $tasksPath = Join-Path $TestDrive 'TASKS-temp.md'
        @'
# TASKS

1. sample
'@ | Set-Content -Path $tasksPath -Encoding UTF8
        Copy-Item -Path $tasksPath -Destination (Join-Path $script:RepoRoot 'TASKS.temp.md') -Force
        $tempRepoTasks = Join-Path $script:RepoRoot 'TASKS.md'
        $backup = Get-Content $tempRepoTasks -Raw -Encoding UTF8
        try {
            $scriptPath = Join-Path $script:RepoRoot 'scripts\tools\Update-TASKS.ps1'
            Set-Content -Path $tempRepoTasks -Value (Get-Content $tasksPath -Raw -Encoding UTF8) -Encoding UTF8
            & $scriptPath -Action add -Text 'new task' -Priority P1 -Owner Ops -Source CI | Out-Null
            $content = Get-Content $tempRepoTasks -Raw -Encoding UTF8
            $content | Should -Match '\[Priority:P1\]\[Owner:Ops\]\[Source:CI\] new task'
        }
        finally {
            Set-Content -Path $tempRepoTasks -Value $backup -Encoding UTF8
            Remove-Item (Join-Path $script:RepoRoot 'TASKS.temp.md') -ErrorAction SilentlyContinue
        }
    }

    It 'Update-TASKS.ps1 が edit と reopen を実行できること' {
        $tempRepoTasks = Join-Path $script:RepoRoot 'TASKS.md'
        $backup = Get-Content $tempRepoTasks -Raw -Encoding UTF8
        try {
            Set-Content -Path $tempRepoTasks -Value "# TASKS`n`n1. [DONE] [Priority:P1][Owner:Ops][Source:CI] old task`n" -Encoding UTF8
            $scriptPath = Join-Path $script:RepoRoot 'scripts\tools\Update-TASKS.ps1'
            & $scriptPath -Action reopen -Index 1 | Out-Null
            & $scriptPath -Action edit -Index 1 -Text 'edited task' | Out-Null
            $content = Get-Content $tempRepoTasks -Raw -Encoding UTF8
            $content | Should -Match '1\. \[Priority:P1\]\[Owner:Ops\]\[Source:CI\] edited task'
        }
        finally {
            Set-Content -Path $tempRepoTasks -Value $backup -Encoding UTF8
        }
    }

    It 'Update-TASKS.ps1 が assign と reprioritize を実行できること' {
        $tempRepoTasks = Join-Path $script:RepoRoot 'TASKS.md'
        $backup = Get-Content $tempRepoTasks -Raw -Encoding UTF8
        try {
            Set-Content -Path $tempRepoTasks -Value "# TASKS`n`n1. [Priority:P2][Owner:ScrumMaster][Source:CI] sample`n" -Encoding UTF8
            $scriptPath = Join-Path $script:RepoRoot 'scripts\tools\Update-TASKS.ps1'
            & $scriptPath -Action assign -Index 1 -Owner Ops | Out-Null
            & $scriptPath -Action reprioritize -Index 1 -Priority P1 | Out-Null
            $content = Get-Content $tempRepoTasks -Raw -Encoding UTF8
            $content | Should -Match '1\. \[Priority:P1\]\[Owner:Ops\]\[Source:CI\] sample'
        }
        finally {
            Set-Content -Path $tempRepoTasks -Value $backup -Encoding UTF8
        }
    }

    It 'Sync-AgentTeamsBacklog.ps1 が metadata 付き抽出を同期できること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\tools\Sync-AgentTeamsBacklog.ps1'
        & $scriptPath -Action sync -ApplyMetadata | Out-Null
        $content = Get-Content (Join-Path $script:RepoRoot 'TASKS.md') -Raw -Encoding UTF8
        $content | Should -Match 'Source:AgentTeamsMatrix'
    }

    It 'Test-McpRuntime.ps1 が Json 出力できること' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\test\Test-McpRuntime.ps1'
        @{
            mcpServers = @{
                memory = @{
                    command = 'node'
                    args = @('memory.js')
                    startupCommand = @('node', '--version')
                    healthCommand = @('node', '--version')
                    shutdownCommand = @('node', '--version')
                }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:McpConfigPath -Encoding UTF8
        $raw = & $script:PowerShellExe -NoProfile -File $scriptPath -OutputFormat Json -ConfigPath $script:ConfigPath -McpConfigPath $script:McpConfigPath 2>$null
        $report = $raw | ConvertFrom-Json
        $report.mcp | Should -Not -BeNullOrEmpty
        $report.mcp.configured | Should -BeTrue
        $report.mcp.summary | Should -Match 'MCP 設定あり'
    }
}
