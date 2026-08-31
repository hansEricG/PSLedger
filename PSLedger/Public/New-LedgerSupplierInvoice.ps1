<#
.SYNOPSIS
Creates a new supplier invoice (leverantörsfaktura) in the journal.

.DESCRIPTION
Creates a sequentially numbered supplier invoice file (sup0001.txt, sup0002.txt,
etc.) in the journal's 'supplierinvoices/' directory. A supplier invoice records
what a supplier has billed but is not yet posted to the ledger — use
Invoke-LedgerSupplierInvoicePosting to create the bookkeeping verification, and
Add-LedgerSupplierPayment to register payments.

Supplier invoices are the accounts-payable mirror of customer invoices: each row
is a cost line with a net amount (excluding VAT), an optional (input) VAT rate and
the account VAT is booked to (e.g. 2640). The gross total is booked to the payable
account (2440 Leverantörsskulder) when posted.

Supplier invoices live at the journal level (not inside a fiscal year) because an
invoice may be paid in a later fiscal year than the one it was received in.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER SupplierNumber
The number of the supplier billing us. Must exist in the supplier register
(see Add-LedgerSupplier).

.PARAMETER Date
The invoice date. Defaults to today.

.PARAMETER DueDate
The date the invoice is due. If omitted, it is calculated from the invoice date
plus the supplier's default payment terms.

.PARAMETER Description
A description of what is being billed.

.PARAMETER Rows
An array of hashtables describing the cost rows. Each row must have:
- Account: the cost account (e.g. '5010')
- Amount: the net amount excluding VAT (positive)
and may optionally have:
- VatRate: the input VAT rate as a decimal (e.g. 0.25 for 25%); defaults to 0
- VatAccount: the account input VAT is booked to (e.g. '2640'); required when
  VatRate is greater than 0

.PARAMETER PayableAccount
The accounts-payable account the invoice total is booked to when posted.
Defaults to '2440' (Leverantörsskulder).

.PARAMETER SupplierInvoiceNo
Optional. The supplier's own invoice number, recorded for reference.

.PARAMETER Reference
Optional. A payment reference (e.g. the supplier's OCR) recorded for the payment.

.PARAMETER PassThru
If specified, returns the created supplier invoice object. By default the command
produces no output.

.EXAMPLE
$rows = @(
    @{ Account = '5010'; Amount = 8000; VatRate = 0.25; VatAccount = '2640' }
)
New-LedgerSupplierInvoice -JournalPath .\MinFirma.ledger -SupplierNumber '100' -Date '2024-03-15' -Description 'Lokalhyra mars' -Rows $rows

Creates a supplier invoice for 8 000 kr plus 25% input VAT from supplier 100.

.EXAMPLE
$rows = @(
    @{ Account = '6110'; Amount = 1200; VatRate = 0.25; VatAccount = '2640' }
)
New-LedgerSupplierInvoice -JournalPath .\MinFirma.ledger -SupplierNumber 'L012' -Description 'Kontorsmateriel' -SupplierInvoiceNo 'F-99123' -Reference '1234567' -Rows $rows -PassThru

Creates a supplier invoice recording the supplier's invoice number and payment
reference, and returns the created object.
#>
function New-LedgerSupplierInvoice {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$SupplierNumber,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [datetime]$DueDate,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [hashtable[]]$Rows,

        [Parameter()]
        [string]$PayableAccount = '2440',

        [Parameter()]
        [string]$SupplierInvoiceNo,

        [Parameter()]
        [string]$Reference,

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    # Validate the supplier exists.
    $supplier = Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber $SupplierNumber
    if (-not $supplier) {
        throw "Supplier '$SupplierNumber' does not exist. Add it with Add-LedgerSupplier first."
    }

    # Validate and normalise rows.
    if ($Rows.Count -eq 0) {
        throw "A supplier invoice must have at least one row."
    }
    $normalizedRows = foreach ($row in $Rows) {
        if (-not $row.ContainsKey('Account') -or [string]::IsNullOrWhiteSpace([string]$row.Account)) {
            throw "Each supplier invoice row must have an Account."
        }
        if (-not $row.ContainsKey('Amount')) {
            throw "Each supplier invoice row must have an Amount."
        }
        $amount = [decimal]$row.Amount
        if ($amount -le 0) {
            throw "Supplier invoice row amount for account $($row.Account) must be greater than zero."
        }
        $vatRate = if ($row.ContainsKey('VatRate') -and $row.VatRate) { [decimal]$row.VatRate } else { [decimal]0 }
        $vatAccount = if ($row.ContainsKey('VatAccount')) { [string]$row.VatAccount } else { '' }
        if ($vatRate -gt 0 -and [string]::IsNullOrWhiteSpace($vatAccount)) {
            throw "Row for account $($row.Account) has VatRate $vatRate but no VatAccount."
        }
        [PSCustomObject]@{
            Account    = [string]$row.Account
            Amount     = $amount
            VatRate    = $vatRate
            VatAccount = $vatAccount
            VatAmount  = [Math]::Round($amount * $vatRate, 2)
        }
    }
    $normalizedRows = @($normalizedRows)

    # Calculate the due date from supplier payment terms when not supplied.
    if (-not $PSBoundParameters.ContainsKey('DueDate')) {
        $DueDate = $Date.AddDays($supplier.PaymentTermsDays)
    }

    $invoiceDir = Get-LedgerSupplierInvoiceDirectory -JournalPath $JournalPath -Create

    # Determine the next supplier invoice number by scanning existing files.
    $existing = Get-ChildItem -Path $invoiceDir -Filter 'sup*.txt' -File -ErrorAction SilentlyContinue
    if ($existing) {
        $maxNum = $existing |
            ForEach-Object { if ($_.BaseName -match '^sup(\d+)$') { [int]$Matches[1] } } |
            Measure-Object -Maximum |
            Select-Object -ExpandProperty Maximum
        $nextNum = $maxNum + 1
    }
    else {
        $nextNum = 1
    }

    $filePath = Join-Path $invoiceDir (Get-LedgerSupplierInvoiceFileName -InvoiceNumber $nextNum)

    $invoice = [PSCustomObject]@{
        InvoiceNumber      = $nextNum
        SupplierNumber     = $SupplierNumber
        SupplierInvoiceNo  = if ($PSBoundParameters.ContainsKey('SupplierInvoiceNo')) { $SupplierInvoiceNo } else { '' }
        InvoiceDate        = $Date
        DueDate            = $DueDate
        Description        = $Description
        Status             = 'Draft'
        PayableAccount     = $PayableAccount
        Reference          = if ($PSBoundParameters.ContainsKey('Reference')) { $Reference } else { '' }
        BookedVerification = $null
        BookedFiscalYear   = ''
        Rows               = $normalizedRows
        Payments           = @()
        FilePath           = $filePath
    }

    Save-LedgerSupplierInvoiceFile -Invoice $invoice

    if ($PassThru) {
        Get-LedgerSupplierInvoice -JournalPath $JournalPath -InvoiceNumber $nextNum
    }
}
