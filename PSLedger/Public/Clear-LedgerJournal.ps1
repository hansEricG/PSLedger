<#
.SYNOPSIS
Clears the current PSLedger journal from the session.

.DESCRIPTION
Removes the session-level default journal path and unloads any per-journal
extensions that were loaded via Set-LedgerJournal.

.EXAMPLE
Clear-LedgerJournal

Clears the current journal. Commands will require -JournalPath again.

.EXAMPLE
Set-LedgerJournal -Path .\MinFirma.ledger
# ... work with MinFirma ...
Clear-LedgerJournal
Set-LedgerJournal -Path .\AnnatBolag.ledger

Switch from one journal to another.
#>
function Clear-LedgerJournal {
    [CmdletBinding()]
    param ()

    Remove-LedgerJournalExtensions
    $script:CurrentJournalPath = $null
}
