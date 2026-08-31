<#
.SYNOPSIS
Lists suppliers in the journal's supplier register.

.DESCRIPTION
Reads suppliers.txt and returns a PSCustomObject for each supplier with the
SupplierNumber, Name, OrgNumber, Email and PaymentTermsDays properties.
Optionally filter to a single supplier by number.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER SupplierNumber
Optional. If specified, returns only the supplier with this number.

.EXAMPLE
Get-LedgerSupplier -JournalPath .\MinFirma.ledger

Returns all suppliers.

.EXAMPLE
Get-LedgerSupplier -JournalPath .\MinFirma.ledger -SupplierNumber '100'

Returns only supplier number 100.
#>
function Get-LedgerSupplier {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$SupplierNumber
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $SupplierFile = Join-Path $JournalPath 'suppliers.txt'
    if (-not (Test-Path $SupplierFile)) { return }

    $suppliers = foreach ($Line in (Get-Content $SupplierFile -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($Line)) { continue }
        $parts = $Line -split "`t"
        [PSCustomObject]@{
            SupplierNumber   = $parts[0]
            Name             = if ($parts.Count -ge 2) { $parts[1] } else { '' }
            OrgNumber        = if ($parts.Count -ge 3) { $parts[2] } else { '' }
            Email            = if ($parts.Count -ge 4) { $parts[3] } else { '' }
            PaymentTermsDays = if ($parts.Count -ge 5 -and $parts[4]) { [int]$parts[4] } else { 30 }
        }
    }

    if ($PSBoundParameters.ContainsKey('SupplierNumber')) {
        $suppliers | Where-Object { $_.SupplierNumber -eq $SupplierNumber }
    }
    else {
        $suppliers
    }
}
