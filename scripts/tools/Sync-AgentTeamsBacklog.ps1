param(
    [ValidateSet('list', 'check', 'sync')]
    [string]$Action = 'list',
    [switch]$ApplyMetadata,
    [string]$RulesPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$DocPath = Join-Path $RepoRoot 'docs\common\08_AgentTeams対応表.md'
$TasksPath = Join-Path $RepoRoot 'TASKS.md'
$DefaultRulesPath = Join-Path $RepoRoot 'config\agent-teams-backlog-rules.json'
$TemplateRulesPath = Join-Path $RepoRoot 'config\agent-teams-backlog-rules.json.template'

function Get-MetadataRules {
    param([string]$Path)

    $resolved = if (-not [string]::IsNullOrWhiteSpace($Path)) { $Path } elseif (Test-Path $DefaultRulesPath) { $DefaultRulesPath } else { $TemplateRulesPath }
    if (-not (Test-Path $resolved)) {
        return $null
    }

    return (Get-Content -Path $resolved -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-UnimplementedItems {
    $docLines = Get-Content -Path $DocPath -Encoding UTF8
    $items = @()
    $inSection = $false
    foreach ($line in $docLines) {
        if ($line -match '^##\s+未実装機能') {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match '^##\s+') {
            break
        }
        if ($inSection -and $line -match '^\-\s+(.+)$') {
            $items += $Matches[1].Trim()
        }
    }
    return @($items)
}

function Get-TaskSeedLine {
    param(
        [int]$Index,
        [string]$Text,
        [object]$Rules
    )

    $owner = 'ScrumMaster'
    $priority = 'P2'
    $source = 'AgentTeamsMatrix'

    if ($Rules -and $Rules.default) {
        if ($Rules.default.owner) { $owner = "$($Rules.default.owner)" }
        if ($Rules.default.priority) { $priority = "$($Rules.default.priority)" }
        if ($Rules.default.source) { $source = "$($Rules.default.source)" }
    }

    if ($Rules -and $Rules.rules) {
        foreach ($rule in @($Rules.rules)) {
            if ($Text -match $rule.pattern) {
                if ($rule.owner) { $owner = "$($rule.owner)" }
                if ($rule.priority) { $priority = "$($rule.priority)" }
                break
            }
        }
    }

    if ($ApplyMetadata) {
        return "$Index. [Priority:$priority][Owner:$owner][Source:$source] $Text"
    }
    return "$Index. $Text"
}

function Get-ExtractedSection {
    param([string[]]$Items, [object]$Rules)

    $lines = @('## Auto Extracted From Agent Teams Matrix', '')
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $lines += (Get-TaskSeedLine -Index ($i + 1) -Text $Items[$i] -Rules $Rules)
    }
    return @($lines)
}

$items = Get-UnimplementedItems
$rules = Get-MetadataRules -Path $RulesPath
$taskLines = Get-Content -Path $TasksPath -Encoding UTF8
$currentExtracted = @()
$inExtracted = $false
foreach ($line in $taskLines) {
    if ($line -match '^##\s+Auto Extracted From Agent Teams Matrix') {
        $inExtracted = $true
        continue
    }
    if ($inExtracted -and $line -match '^##\s+') {
        break
    }
    if ($inExtracted -and $line -match '^\d+\.\s') {
        $currentExtracted += ($line -replace '^\d+\.\s+(?:\[[^\]]+\])+\s*', '')
    }
}

switch ($Action) {
    'list' {
        $items | ForEach-Object { Write-Host $_ }
        exit 0
    }
    'check' {
        $missing = Compare-Object -ReferenceObject $items -DifferenceObject $currentExtracted -PassThru | Where-Object { $_ -in $items }
        if (@($missing).Count -gt 0) {
            $missing | ForEach-Object { Write-Host "Missing extracted task: $_" -ForegroundColor Yellow }
            throw 'TASKS.md auto extracted section is out of sync.'
        }
        exit 0
    }
    'sync' {
        $newSection = Get-ExtractedSection -Items $items -Rules $rules
        $output = [System.Collections.Generic.List[string]]::new()
        $skip = $false
        $replaced = $false
        foreach ($line in $taskLines) {
            if ($line -match '^##\s+Auto Extracted From Agent Teams Matrix') {
                if (-not $replaced) {
                    foreach ($newLine in $newSection) {
                        $output.Add($newLine)
                    }
                    $replaced = $true
                }
                $skip = $true
                continue
            }
            if ($skip -and $line -match '^##\s+') {
                $skip = $false
            }
            if (-not $skip) {
                $output.Add($line)
            }
        }
        if (-not $replaced) {
            $output.Add('')
            foreach ($newLine in $newSection) {
                $output.Add($newLine)
            }
        }
        [System.IO.File]::WriteAllLines($TasksPath, $output, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Synced extracted backlog: $TasksPath"
    }
}
