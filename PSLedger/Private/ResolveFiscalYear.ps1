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
