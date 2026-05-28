<#
.SYNOPSIS
Returns the first (oldest) fiscal year in a journal.

.DESCRIPTION
Scans the journal for fiscal year directories and returns the one with the
earliest start date.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.EXAMPLE
Get-LedgerFirstFiscalYear

Returns the oldest fiscal year from the current journal.

.EXAMPLE
Get-LedgerFirstFiscalYear | Get-LedgerBalance

Gets the trial balance for the first fiscal year using pipeline.
#>
function Get-LedgerFirstFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $years = Get-LedgerFiscalYear -JournalPath $JournalPath
    if ($years) {
        $years | Select-Object -First 1
    }
}
