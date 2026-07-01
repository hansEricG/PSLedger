<#
.SYNOPSIS
Removes a recurring entry template from the journal.

.DESCRIPTION
Deletes the recurring entry template file from the journal's 'recurring/'
directory. This does not affect any verifications already generated from the
template.

.PARAMETER JournalPath
Path to the journal (.ledger directory).

.PARAMETER Name
Name of the recurring entry template to remove.

.EXAMPLE
Remove-LedgerRecurringEntry -JournalPath .\ab.ledger -Name 'Hyra'

Removes the recurring entry template named 'Hyra'.

.EXAMPLE
Get-LedgerRecurringEntry -JournalPath .\ab.ledger | Where-Object { $_.EndDate -lt (Get-Date) } | ForEach-Object { Remove-LedgerRecurringEntry -JournalPath .\ab.ledger -Name $_.Name }

Removes all expired recurring entry templates.
#>
function Remove-LedgerRecurringEntry {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$Name
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $recurringDir = Join-Path $JournalPath 'recurring'
    $filePath = Join-Path $recurringDir "$Name.txt"

    if (-not (Test-Path $filePath)) {
        throw "Recurring entry '$Name' not found."
    }

    Remove-Item -Path $filePath -Force
}
