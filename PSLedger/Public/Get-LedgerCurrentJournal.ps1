<#
.SYNOPSIS
Returns metadata for the current session journal.

.DESCRIPTION
Returns a PSCustomObject with the company information (Path, Name, OrgNumber)
for the journal set via Set-LedgerCurrentJournal, without needing to specify a
path. Throws if no current journal has been set.

.EXAMPLE
Set-LedgerCurrentJournal -Path .\MinFirma.ledger
Get-LedgerCurrentJournal

Returns metadata for the current session journal.

.EXAMPLE
$journal = Get-LedgerCurrentJournal
Write-Output "Company: $($journal.Name) ($($journal.OrgNumber))"

Captures the current journal metadata into a variable.
#>
function Get-LedgerCurrentJournal {
    [CmdletBinding()]
    param ()

    if (-not $script:CurrentJournalPath) {
        throw "No current journal set. Use Set-LedgerCurrentJournal first."
    }

    Get-LedgerJournal -Path $script:CurrentJournalPath
}
