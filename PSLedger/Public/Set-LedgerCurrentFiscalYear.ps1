<#
.SYNOPSIS
Sets the current PSLedger fiscal year for the session.

.DESCRIPTION
Sets a session-level default fiscal year so that other PSLedger commands can be
called without specifying -FiscalYear every time. The fiscal year is validated
against the current (or specified) journal — it must be an existing fiscal year
directory (matching yyyy-MM_yyyy-MM).

The current fiscal year is cleared automatically when the current journal is
changed with Set-LedgerCurrentJournal or cleared with Clear-LedgerCurrentJournal,
since fiscal year names are specific to a journal.

.PARAMETER FiscalYear
The name of an existing fiscal year (e.g. '2024-01_2024-12').

.PARAMETER JournalPath
The path to an existing journal directory. Defaults to the current journal set
via Set-LedgerCurrentJournal.

.EXAMPLE
Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12'

Sets the 2024 fiscal year as the session default. Subsequent commands like
Get-LedgerBalance can be called without -FiscalYear.

.EXAMPLE
Set-LedgerCurrentJournal -Path .\AB-Konsult.ledger
Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12'
Get-LedgerIncomeStatement

Sets both the journal and fiscal year, then runs a report without specifying
either path or year.
#>
function Set-LedgerCurrentFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [Parameter()]
        [string]$JournalPath
    )

    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $yearPath = Join-Path $JournalPath $FiscalYear
    if (-not (Test-Path $yearPath -PathType Container)) {
        throw "Fiscal year not found in journal: $FiscalYear"
    }

    $script:CurrentFiscalYear = $FiscalYear
}
