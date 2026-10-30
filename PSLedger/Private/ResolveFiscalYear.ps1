function Resolve-LedgerFiscalYear {
    <#
    .SYNOPSIS
    Resolves a fiscal year name from a parameter or defaults to the latest fiscal year.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$JournalPath
    )

    if ($FiscalYear) {
        return $FiscalYear
    }

    # Fall back to the session's current fiscal year, if set
    if ($script:CurrentFiscalYear) {
        return $script:CurrentFiscalYear
    }

    # Find latest fiscal year by scanning directory
    $yearDirs = Get-ChildItem -Path $JournalPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}_\d{4}-\d{2}$' } |
        Sort-Object Name

    if (-not $yearDirs) {
        throw "No fiscal years found in journal: $JournalPath"
    }

    # Return the last one (sorted lexicographically = chronologically for yyyy-MM format)
    return $yearDirs[-1].Name
}

function Assert-LedgerFiscalYearOpen {
    <#
    .SYNOPSIS
    Throws when the fiscal year's year.txt marks it as Closed.

    .DESCRIPTION
    The shared guard for commands that change a fiscal year's verifications,
    attachments, documents, opening balance or holdings.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$YearDir,
        [Parameter(Mandatory)] [string]$FiscalYear,
        [Parameter(Mandatory)] [string]$Action
    )
    $yearFile = Join-Path $YearDir 'year.txt'
    if (Test-Path $yearFile -PathType Leaf) {
        foreach ($line in (Get-Content $yearFile)) {
            if ($line -match '^Status:\s*Closed') {
                throw "Fiscal year $FiscalYear is Closed. Cannot $Action."
            }
        }
    }
}
