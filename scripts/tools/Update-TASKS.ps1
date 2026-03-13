param(
    [ValidateSet('list', 'add', 'complete', 'edit', 'reopen', 'assign', 'reprioritize')]
    [string]$Action = 'list',
    [string]$Text = '',
    [int]$Index = 0,
    [ValidateSet('P0', 'P1', 'P2', 'P3', '')]
    [string]$Priority = '',
    [string]$Owner = '',
    [string]$Source = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TasksPath = Join-Path $RepoRoot 'TASKS.md'

if (-not (Test-Path $TasksPath)) {
    throw "TASKS.md が見つかりません: $TasksPath"
}

$lines = [System.Collections.Generic.List[string]]::new()
foreach ($line in Get-Content $TasksPath -Encoding UTF8) {
    $lines.Add($line)
}

function Get-TaskLines {
    param([System.Collections.Generic.List[string]]$TaskLines)
    return @($TaskLines | Where-Object { $_ -match '^\d+\.\s' })
}

function New-TaskMetadataPrefix {
    param(
        [string]$Priority,
        [string]$Owner,
        [string]$Source
    )

    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($Priority)) {
        $parts += "[Priority:$Priority]"
    }
    if (-not [string]::IsNullOrWhiteSpace($Owner)) {
        $parts += "[Owner:$Owner]"
    }
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $parts += "[Source:$Source]"
    }
    if ($parts.Count -eq 0) {
        return ''
    }

    return ($parts -join '') + ' '
}

function Get-TaskLineIndex {
    param(
        [System.Collections.Generic.List[string]]$TaskLines,
        [int]$TaskIndex
    )

    for ($i = 0; $i -lt $TaskLines.Count; $i++) {
        if ($TaskLines[$i] -match "^$TaskIndex\.\s") {
            return $i
        }
    }
    return -1
}

function Parse-TaskBody {
    param([string]$Line)

    $body = $Line -replace '^\d+\.\s*', ''
    $isDone = $body -match '^\[DONE\]\s*'
    if ($isDone) {
        $body = $body -replace '^\[DONE\]\s*', ''
    }

    $metadata = [ordered]@{}
    foreach ($match in [regex]::Matches($body, '\[(Priority|Owner|Source):([^\]]+)\]')) {
        $metadata[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    $text = ($body -replace '^(?:\[(?:Priority|Owner|Source):[^\]]+\])+\s*', '').Trim()

    return [pscustomobject]@{
        IsDone = $isDone
        Metadata = $metadata
        Text = $text
    }
}

function Build-TaskLine {
    param(
        [int]$Index,
        [bool]$IsDone,
        [System.Collections.IDictionary]$Metadata,
        [string]$Text
    )

    $parts = @()
    if ($IsDone) {
        $parts += '[DONE]'
    }
    foreach ($key in @('Priority', 'Owner', 'Source')) {
        if (($Metadata.Keys -contains $key) -and -not [string]::IsNullOrWhiteSpace($Metadata[$key])) {
            $parts += "[$($key):$($Metadata[$key])]"
        }
    }

    $prefix = if ($parts.Count -gt 0) { ($parts -join '') + ' ' } else { '' }
    return "$Index. $prefix$Text"
}

switch ($Action) {
    'list' {
        Get-TaskLines -TaskLines $lines | ForEach-Object { Write-Host $_ }
        exit 0
    }
    'add' {
        if ([string]::IsNullOrWhiteSpace($Text)) {
            throw "-Text が必要です。"
        }
        $tasks = @(Get-TaskLines -TaskLines $lines)
        $nextIndex = $tasks.Count + 1
        $prefix = New-TaskMetadataPrefix -Priority $Priority -Owner $Owner -Source $Source
        $lines.Add("$nextIndex. $prefix$Text")
    }
    'complete' {
        if ($Index -lt 1) {
            throw "-Index には 1 以上を指定してください。"
        }
        $taskLineIndex = Get-TaskLineIndex -TaskLines $lines -TaskIndex $Index
        if ($taskLineIndex -lt 0) {
            throw "指定したタスクが見つかりません: $Index"
        }
        $lines[$taskLineIndex] = "$Index. [DONE] " + ($lines[$taskLineIndex] -replace "^\d+\.\s*", '')
    }
    'edit' {
        if ($Index -lt 1 -or [string]::IsNullOrWhiteSpace($Text)) {
            throw "-Index と -Text が必要です。"
        }
        $taskLineIndex = Get-TaskLineIndex -TaskLines $lines -TaskIndex $Index
        if ($taskLineIndex -lt 0) {
            throw "指定したタスクが見つかりません: $Index"
        }
        $parsed = Parse-TaskBody -Line $lines[$taskLineIndex]
        $metadata = [ordered]@{}
        foreach ($key in $parsed.Metadata.Keys) {
            $metadata[$key] = $parsed.Metadata[$key]
        }
        if (-not [string]::IsNullOrWhiteSpace($Priority)) { $metadata['Priority'] = $Priority }
        if (-not [string]::IsNullOrWhiteSpace($Owner)) { $metadata['Owner'] = $Owner }
        if (-not [string]::IsNullOrWhiteSpace($Source)) { $metadata['Source'] = $Source }
        $lines[$taskLineIndex] = Build-TaskLine -Index $Index -IsDone $parsed.IsDone -Metadata $metadata -Text $Text
    }
    'reopen' {
        if ($Index -lt 1) {
            throw "-Index には 1 以上を指定してください。"
        }
        $taskLineIndex = Get-TaskLineIndex -TaskLines $lines -TaskIndex $Index
        if ($taskLineIndex -lt 0) {
            throw "指定したタスクが見つかりません: $Index"
        }
        $parsed = Parse-TaskBody -Line $lines[$taskLineIndex]
        $lines[$taskLineIndex] = Build-TaskLine -Index $Index -IsDone $false -Metadata $parsed.Metadata -Text $parsed.Text
    }
    'assign' {
        if ($Index -lt 1 -or [string]::IsNullOrWhiteSpace($Owner)) {
            throw "-Index と -Owner が必要です。"
        }
        $taskLineIndex = Get-TaskLineIndex -TaskLines $lines -TaskIndex $Index
        if ($taskLineIndex -lt 0) {
            throw "指定したタスクが見つかりません: $Index"
        }
        $parsed = Parse-TaskBody -Line $lines[$taskLineIndex]
        $metadata = [ordered]@{}
        foreach ($key in $parsed.Metadata.Keys) {
            $metadata[$key] = $parsed.Metadata[$key]
        }
        $metadata['Owner'] = $Owner
        if (-not [string]::IsNullOrWhiteSpace($Source)) {
            $metadata['Source'] = $Source
        }
        $lines[$taskLineIndex] = Build-TaskLine -Index $Index -IsDone $parsed.IsDone -Metadata $metadata -Text $parsed.Text
    }
    'reprioritize' {
        if ($Index -lt 1 -or [string]::IsNullOrWhiteSpace($Priority)) {
            throw "-Index と -Priority が必要です。"
        }
        $taskLineIndex = Get-TaskLineIndex -TaskLines $lines -TaskIndex $Index
        if ($taskLineIndex -lt 0) {
            throw "指定したタスクが見つかりません: $Index"
        }
        $parsed = Parse-TaskBody -Line $lines[$taskLineIndex]
        $metadata = [ordered]@{}
        foreach ($key in $parsed.Metadata.Keys) {
            $metadata[$key] = $parsed.Metadata[$key]
        }
        $metadata['Priority'] = $Priority
        if (-not [string]::IsNullOrWhiteSpace($Source)) {
            $metadata['Source'] = $Source
        }
        $lines[$taskLineIndex] = Build-TaskLine -Index $Index -IsDone $parsed.IsDone -Metadata $metadata -Text $parsed.Text
    }
}

[System.IO.File]::WriteAllLines($TasksPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "更新しました: $TasksPath"
