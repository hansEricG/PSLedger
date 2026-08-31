<#
.SYNOPSIS
Lists customers in the journal's customer register.

.DESCRIPTION
Reads customers.txt and returns a PSCustomObject for each customer with the
CustomerNumber, Name, OrgNumber, Email and PaymentTermsDays properties.
Optionally filter to a single customer by number.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER CustomerNumber
Optional. If specified, returns only the customer with this number.

.EXAMPLE
Get-LedgerCustomer -JournalPath .\MinFirma.ledger

Returns all customers.

.EXAMPLE
Get-LedgerCustomer -JournalPath .\MinFirma.ledger -CustomerNumber '10'

Returns only customer number 10.
#>
function Get-LedgerCustomer {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$CustomerNumber
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $CustomerFile = Join-Path $JournalPath 'customers.txt'
    if (-not (Test-Path $CustomerFile)) { return }

    $customers = foreach ($Line in (Get-Content $CustomerFile -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($Line)) { continue }
        $parts = $Line -split "`t"
        [PSCustomObject]@{
            CustomerNumber   = $parts[0]
            Name             = if ($parts.Count -ge 2) { $parts[1] } else { '' }
            OrgNumber        = if ($parts.Count -ge 3) { $parts[2] } else { '' }
            Email            = if ($parts.Count -ge 4) { $parts[3] } else { '' }
            PaymentTermsDays = if ($parts.Count -ge 5 -and $parts[4]) { [int]$parts[4] } else { 30 }
        }
    }

    if ($PSBoundParameters.ContainsKey('CustomerNumber')) {
        $customers | Where-Object { $_.CustomerNumber -eq $CustomerNumber }
    }
    else {
        $customers
    }
}
