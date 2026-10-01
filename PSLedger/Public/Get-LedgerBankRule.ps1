<#
.SYNOPSIS
Lists the bank rules (konteringsregler).

.DESCRIPTION
Returns the bank rules used by Invoke-LedgerBankMatching in priority order
(the first matching rule wins).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Pattern
Optional. Return only the rule with this pattern.

.EXAMPLE
Get-LedgerBankRule -JournalPath .\MinFirma.ledger

Lists all bank rules.

.EXAMPLE
Get-LedgerBankRule | Format-Table Priority, Pattern, Account, Description, VatRate

Shows the rules as a table in the order they are tried.
#>
function Get-LedgerBankRule {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$Pattern
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
    Read-LedgerBankRules -JournalPath $JournalPath | Where-Object { -not $Pattern -or $_.Pattern -eq $Pattern }
}
