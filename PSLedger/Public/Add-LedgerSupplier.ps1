<#
.SYNOPSIS
Adds a supplier to the journal's supplier register.

.DESCRIPTION
Adds a supplier entry to the journal's suppliers.txt file. Suppliers are the
issuers of the supplier invoices recorded with New-LedgerSupplierInvoice. Each
supplier has a unique supplier number and a name, plus optional organisation
number, email and default payment terms (in days) used to calculate the due date
of supplier invoices.

The suppliers.txt file is tab-separated with the columns:
SupplierNumber, Name, OrgNumber, Email, PaymentTermsDays.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER SupplierNumber
A unique identifier for the supplier (e.g. '100', 'L001').

.PARAMETER Name
The supplier's name.

.PARAMETER OrgNumber
Optional organisation number (e.g. '556677-8899').

.PARAMETER Email
Optional email address for the supplier.

.PARAMETER PaymentTermsDays
Default number of days from invoice date until a supplier invoice is due.
Defaults to 30 days.

.EXAMPLE
Add-LedgerSupplier -JournalPath .\MinFirma.ledger -SupplierNumber '100' -Name 'Kontorsbolaget AB'

Adds a supplier with the default 30-day payment terms.

.EXAMPLE
Add-LedgerSupplier -JournalPath .\MinFirma.ledger -SupplierNumber 'L012' -Name 'Fortum Sverige AB' -OrgNumber '556006-8420' -Email 'faktura@fortum.se' -PaymentTermsDays 20

Adds a supplier with full contact details and 20-day payment terms.
#>
function Add-LedgerSupplier {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$SupplierNumber,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$OrgNumber,

        [Parameter()]
        [string]$Email,

        [Parameter()]
        [ValidateRange(0, 3650)]
        [int]$PaymentTermsDays = 30
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    if ($SupplierNumber -match "`t") {
        throw "SupplierNumber must not contain a tab character."
    }

    $SupplierFile = Join-Path $JournalPath 'suppliers.txt'

    if (Test-Path $SupplierFile) {
        foreach ($Line in (Get-Content $SupplierFile -Encoding UTF8)) {
            if ($Line -match "^$([regex]::Escape($SupplierNumber))`t") {
                throw "Supplier '$SupplierNumber' already exists."
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($SupplierNumber, 'Add supplier')) {
        "$SupplierNumber`t$Name`t$OrgNumber`t$Email`t$PaymentTermsDays" |
            Add-Content -Path $SupplierFile -Encoding UTF8
    }
}
