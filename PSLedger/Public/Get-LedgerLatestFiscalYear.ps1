<#
.SYNOPSIS
Returns the latest (most recent) fiscal year in a journal.

.DESCRIPTION
Scans the journal for fiscal year directories and returns the one with the
latest start date, regardless of its open/closed status.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.EXAMPLE
Get-LedgerLatestFiscalYear

Returns the most recent fiscal year from the current journal.

.EXAMPLE
Get-LedgerLatestFiscalYear | Get-LedgerEntry

Gets all entries from the latest fiscal year using pipeline.
#>
function Get-LedgerLatestFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $years = Get-LedgerFiscalYear -JournalPath $JournalPath
    if ($years) {
        $years | Select-Object -Last 1
    }
}
