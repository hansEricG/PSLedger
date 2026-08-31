<#
.SYNOPSIS
Lists supplier invoices in the journal.

.DESCRIPTION
Reads supplier invoices from the journal's 'supplierinvoices/' directory and
returns an object for each with its metadata, cost rows, payments and computed
totals (NetTotal, VatTotal, Total, PaidAmount, RemainingAmount). The supplier's
name is resolved from the supplier register and added as SupplierName.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
Optional. If specified, returns only the supplier invoice with this number.

.PARAMETER Status
Optional. If specified, returns only invoices with this status (Draft, Booked,
Partial or Paid).

.PARAMETER SupplierNumber
Optional. If specified, returns only invoices from this supplier.

.PARAMETER Unpaid
If specified, returns only invoices that are not fully paid (status Booked or
Partial). Draft invoices are excluded because they have not been posted.

.EXAMPLE
Get-LedgerSupplierInvoice -JournalPath .\MinFirma.ledger

Lists all supplier invoices.

.EXAMPLE
Get-LedgerSupplierInvoice -JournalPath .\MinFirma.ledger -Unpaid

Lists all posted but not fully paid supplier invoices (the open payables).

.EXAMPLE
Get-LedgerSupplierInvoice -JournalPath .\MinFirma.ledger -InvoiceNumber 1

Returns the details of supplier invoice number 1.
#>
function Get-LedgerSupplierInvoice {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [int]$InvoiceNumber,

        [Parameter()]
        [ValidateSet('Draft', 'Booked', 'Partial', 'Paid')]
        [string]$Status,

        [Parameter()]
        [string]$SupplierNumber,

        [Parameter()]
        [switch]$Unpaid
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $invoiceDir = Get-LedgerSupplierInvoiceDirectory -JournalPath $JournalPath
    if (-not (Test-Path $invoiceDir)) { return }

    $files = if ($PSBoundParameters.ContainsKey('InvoiceNumber')) {
        $filePath = Join-Path $invoiceDir (Get-LedgerSupplierInvoiceFileName -InvoiceNumber $InvoiceNumber)
        if (Test-Path $filePath) { @(Get-Item $filePath) } else { @() }
    }
    else {
        @(Get-ChildItem -Path $invoiceDir -Filter 'sup*.txt' -File |
            Sort-Object { [int]($_.BaseName -replace '^sup', '') })
    }

    # Build a lookup of supplier numbers to names once.
    $supplierNames = @{}
    foreach ($s in @(Get-LedgerSupplier -JournalPath $JournalPath)) {
        $supplierNames[$s.SupplierNumber] = $s.Name
    }

    foreach ($file in $files) {
        $invoice = Read-LedgerSupplierInvoiceFile -Path $file.FullName

        if ($PSBoundParameters.ContainsKey('Status') -and $invoice.Status -ne $Status) { continue }
        if ($PSBoundParameters.ContainsKey('SupplierNumber') -and $invoice.SupplierNumber -ne $SupplierNumber) { continue }
        if ($Unpaid -and $invoice.Status -notin @('Booked', 'Partial')) { continue }

        $name = if ($supplierNames.ContainsKey($invoice.SupplierNumber)) { $supplierNames[$invoice.SupplierNumber] } else { '' }
        $invoice | Add-Member -NotePropertyName 'SupplierName' -NotePropertyValue $name -PassThru
    }
}
