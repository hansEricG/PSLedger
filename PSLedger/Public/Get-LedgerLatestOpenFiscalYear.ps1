<#
.SYNOPSIS
Returns the latest open fiscal year in a journal.

.DESCRIPTION
Scans the journal for fiscal year directories and returns the most recent one
that has Status = Open.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.EXAMPLE
Get-LedgerLatestOpenFiscalYear

Returns the most recent open fiscal year from the current journal.

.EXAMPLE
Get-LedgerLatestOpenFiscalYear | Add-LedgerEntry -Date '2024-06-15' -Description 'Försäljning' -Rows $rows

Adds an entry to the latest open fiscal year using pipeline.
#>
function Get-LedgerLatestOpenFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $years = Get-LedgerFiscalYear -JournalPath $JournalPath |
        Where-Object { $_.Status -eq 'Open' }
    if ($years) {
        $years | Select-Object -Last 1
    }
}
