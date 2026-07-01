<#
.SYNOPSIS
Clears the current PSLedger journal from the session.

.DESCRIPTION
Removes the session-level default journal path and unloads any per-journal
extensions that were loaded via Set-LedgerCurrentJournal.

.EXAMPLE
Clear-LedgerCurrentJournal

Clears the current journal. Commands will require -JournalPath again.

.EXAMPLE
Set-LedgerCurrentJournal -Path .\MinFirma.ledger
# ... work with MinFirma ...
Clear-LedgerCurrentJournal
Set-LedgerCurrentJournal -Path .\AnnatBolag.ledger

Switch from one journal to another.
#>
function Clear-LedgerCurrentJournal {
    [CmdletBinding()]
    param ()

    Remove-LedgerJournalExtensions
    $script:CurrentJournalPath = $null
    $script:CurrentFiscalYear = $null
}
