<#
.SYNOPSIS
Creates a recurring entry template in the journal.

.DESCRIPTION
Stores a recurring entry template that can be automatically generated at
regular intervals using Invoke-LedgerRecurringEntry. Templates are stored
as text files in a 'recurring/' subdirectory of the journal.

Supported schedules: 'monthly'.

.PARAMETER JournalPath
Path to the journal (.ledger directory).

.PARAMETER Name
Unique name for the recurring entry template (used as filename).

.PARAMETER Description
Description applied to generated verifications.

.PARAMETER Schedule
Recurrence schedule. Currently supports 'monthly'.

.PARAMETER DayOfMonth
Day of month on which to generate the entry (1-28).

.PARAMETER StartDate
First date from which the template is active.

.PARAMETER EndDate
Last date until which the template is active (inclusive).

.PARAMETER Rows
Array of row hashtables, each with Account and Amount keys.

.EXAMPLE
New-LedgerRecurringEntry -JournalPath .\ab.ledger -Name 'Hyra' `
    -Description 'Hyra kontor månadsvis' -Schedule 'monthly' -DayOfMonth 1 `
    -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
    @{ Account = '5010'; Amount = 8000 }
    @{ Account = '2440'; Amount = -8000 }
)

Creates a monthly recurring entry for office rent.

.EXAMPLE
New-LedgerRecurringEntry -JournalPath .\ab.ledger -Name 'Telefon' `
    -Description 'Telefonabonnemang' -Schedule 'monthly' -DayOfMonth 15 `
    -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
    @{ Account = '6210'; Amount = 500 }
    @{ Account = '2640'; Amount = 125 }
    @{ Account = '2440'; Amount = -625 }
)

Creates a monthly recurring entry for a phone subscription with VAT.
#>
function New-LedgerRecurringEntry {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateSet('monthly')]
        [string]$Schedule,

        [Parameter(Mandatory)]
        [ValidateRange(1, 28)]
        [int]$DayOfMonth,

        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [Parameter(Mandatory)]
        [datetime]$EndDate,

        [Parameter(Mandatory)]
        [hashtable[]]$Rows
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $recurringDir = Join-Path $JournalPath 'recurring'
    if (-not (Test-Path $recurringDir)) {
        New-Item -Path $recurringDir -ItemType Directory | Out-Null
    }

    $filePath = Join-Path $recurringDir "$Name.txt"
    if (Test-Path $filePath) {
        throw "Recurring entry '$Name' already exists."
    }

    # Validate balance
    $sum = ($Rows | ForEach-Object { [decimal]$_.Amount } | Measure-Object -Sum).Sum
    if ($sum -ne 0) {
        throw "Rows do not balance. Sum: $sum"
    }

    $lines = @(
        "Name:`t$Name"
        "Description:`t$Description"
        "Schedule:`t$Schedule"
        "DayOfMonth:`t$DayOfMonth"
        "StartDate:`t$($StartDate.ToString('yyyy-MM-dd'))"
        "EndDate:`t$($EndDate.ToString('yyyy-MM-dd'))"
        "LastGenerated:`t"
        "Rows:"
    )
    foreach ($row in $Rows) {
        $lines += "$($row.Account)`t$($row.Amount)"
    }

    $lines | Set-Content -Path $filePath -Encoding UTF8
}
