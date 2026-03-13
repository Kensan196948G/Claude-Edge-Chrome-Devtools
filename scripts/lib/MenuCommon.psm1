function Normalize-MenuRecentToolFilter {
    param([string]$ToolFilter = '')

    if ([string]::IsNullOrWhiteSpace($ToolFilter) -or $ToolFilter -eq 'all') {
        return ''
    }

    if ($ToolFilter -in @('claude', 'codex', 'copilot')) {
        return $ToolFilter
    }

    return ''
}

function Normalize-MenuRecentSortMode {
    param([string]$SortMode = 'success')

    if ($SortMode -in @('success', 'timestamp', 'elapsed')) {
        return $SortMode
    }

    return 'success'
}

function Get-MenuRecentFilterSummary {
    param(
        [string]$ToolFilter = '',
        [string]$SearchQuery = '',
        [string]$SortMode = 'success'
    )

    return [pscustomobject]@{
        tool = if ([string]::IsNullOrWhiteSpace($ToolFilter)) { 'all' } else { $ToolFilter }
        search = if ([string]::IsNullOrWhiteSpace($SearchQuery)) { 'none' } else { $SearchQuery }
        sort = Normalize-MenuRecentSortMode -SortMode $SortMode
    }
}

Export-ModuleMember -Function Normalize-MenuRecentToolFilter
Export-ModuleMember -Function Normalize-MenuRecentSortMode
Export-ModuleMember -Function Get-MenuRecentFilterSummary
