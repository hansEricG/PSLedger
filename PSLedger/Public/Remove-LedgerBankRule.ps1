<#
.SYNOPSIS
Removes a bank rule (konteringsregel).

.DESCRIPTION
Removes the bank rule with the given pattern. Transactions already posted by
the rule are not affected.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Pattern
The pattern of the rule to remove. Accepts pipeline input by property name.

.EXAMPLE
Remove-LedgerBankRule -JournalPath .\MinFirma.ledger -Pattern 'Bankavgift'

Removes the rule for bank fees.

.EXAMPLE
Get-LedgerBankRule | Where-Object Account -eq '6212' | Remove-LedgerBankRule

Removes all rules that post to 6212 (Mobiltelefon).
#>
function Remove-LedgerBankRule {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Pattern
    )
    begin {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
    }
    process {
        $rules = @(Read-LedgerBankRules -JournalPath $JournalPath)
        if (-not ($rules | Where-Object { $_.Pattern -eq $Pattern })) {
            throw "Bank rule '$Pattern' does not exist."
        }
        if (-not $PSCmdlet.ShouldProcess("Bank rule '$Pattern'", 'Remove')) { return }
        Save-LedgerBankRules -JournalPath $JournalPath -Rules @($rules | Where-Object { $_.Pattern -ne $Pattern })
    }
}
