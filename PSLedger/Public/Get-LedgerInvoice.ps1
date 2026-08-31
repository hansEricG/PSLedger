<#
.SYNOPSIS
Lists customer invoices in the journal.

.DESCRIPTION
Reads invoices from the journal's 'invoices/' directory and returns an object for
each with its metadata, revenue rows, payments and computed totals (NetTotal,
VatTotal, Total, PaidAmount, RemainingAmount). The customer's name is resolved
from the customer register and added as CustomerName.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
Optional. If specified, returns only the invoice with this number.

.PARAMETER Status
Optional. If specified, returns only invoices with this status (Draft, Booked,
Partial or Paid).

.PARAMETER CustomerNumber
Optional. If specified, returns only invoices for this customer.

.PARAMETER Unpaid
If specified, returns only invoices that are not fully paid (status Booked or
Partial). Draft invoices are excluded because they have not been posted.

.EXAMPLE
Get-LedgerInvoice -JournalPath .\MinFirma.ledger

Lists all invoices.

.EXAMPLE
Get-LedgerInvoice -JournalPath .\MinFirma.ledger -Unpaid

Lists all posted but not fully paid invoices (the open receivables).

.EXAMPLE
Get-LedgerInvoice -JournalPath .\MinFirma.ledger -InvoiceNumber 1

Returns the details of invoice number 1.
#>
function Get-LedgerInvoice {
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
        [string]$CustomerNumber,

        [Parameter()]
        [switch]$Unpaid
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $invoiceDir = Get-LedgerInvoiceDirectory -JournalPath $JournalPath
    if (-not (Test-Path $invoiceDir)) { return }

    $files = if ($PSBoundParameters.ContainsKey('InvoiceNumber')) {
        $filePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
        if (Test-Path $filePath) { @(Get-Item $filePath) } else { @() }
    }
    else {
        @(Get-ChildItem -Path $invoiceDir -Filter 'inv*.txt' -File |
            Sort-Object { [int]($_.BaseName -replace '^inv', '') })
    }

    # Build a lookup of customer numbers to names once.
    $customerNames = @{}
    foreach ($c in @(Get-LedgerCustomer -JournalPath $JournalPath)) {
        $customerNames[$c.CustomerNumber] = $c.Name
    }

    foreach ($file in $files) {
        $invoice = Read-LedgerInvoiceFile -Path $file.FullName

        if ($PSBoundParameters.ContainsKey('Status') -and $invoice.Status -ne $Status) { continue }
        if ($PSBoundParameters.ContainsKey('CustomerNumber') -and $invoice.CustomerNumber -ne $CustomerNumber) { continue }
        if ($Unpaid -and $invoice.Status -notin @('Booked', 'Partial')) { continue }

        $name = if ($customerNames.ContainsKey($invoice.CustomerNumber)) { $customerNames[$invoice.CustomerNumber] } else { '' }
        $invoice | Add-Member -NotePropertyName 'CustomerName' -NotePropertyValue $name -PassThru
    }
}
