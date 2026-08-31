<#
.SYNOPSIS
Registers a payment against a posted customer invoice.

.DESCRIPTION
Records a payment for a Booked or Partial invoice: the cash/bank account is
debited and the accounts-receivable account is credited with the payment amount.
The fiscal year is resolved from the payment date unless one is supplied.

Partial payments are supported — when the accumulated payments are still less
than the invoice total the status becomes 'Partial'; once the invoice is fully
paid it becomes 'Paid'. The payment is recorded on the invoice together with the
verification it created so the receivable can be reconciled against the ledger.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the invoice being paid. It must have been posted first with
Invoke-LedgerInvoicePosting.

.PARAMETER Date
The payment date. Defaults to today.

.PARAMETER Amount
The amount received. Defaults to the invoice's remaining unpaid amount. Must be
greater than zero and not exceed the remaining amount.

.PARAMETER Account
The cash or bank account the payment is received into. Defaults to '1930'
(Företagskonto/checkkonto).

.PARAMETER FiscalYear
Optional. The fiscal year to post the payment verification into. If omitted, the
fiscal year containing the payment date is used.

.PARAMETER PassThru
If specified, returns the updated invoice object. By default the command
produces no output.

.EXAMPLE
Add-LedgerInvoicePayment -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Date '2024-04-10'

Registers full payment of invoice 1 into the default bank account 1930.

.EXAMPLE
Add-LedgerInvoicePayment -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' -Account '1910'

Registers a partial cash payment of 5 000 kr into account 1910 (Kassa), leaving
the invoice in 'Partial' status.
#>
function Add-LedgerInvoicePayment {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [decimal]$Amount,

        [Parameter()]
        [string]$Account = '1930',

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $invoiceDir = Get-LedgerInvoiceDirectory -JournalPath $JournalPath
    $filePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
    if (-not (Test-Path $filePath)) {
        throw "Invoice $InvoiceNumber does not exist."
    }

    $invoice = Read-LedgerInvoiceFile -Path $filePath

    if ($invoice.Status -eq 'Draft') {
        throw "Invoice $InvoiceNumber has not been posted. Post it first with Invoke-LedgerInvoicePosting."
    }
    if ($invoice.Status -eq 'Paid') {
        throw "Invoice $InvoiceNumber is already fully paid."
    }

    if (-not $PSBoundParameters.ContainsKey('Amount')) {
        $Amount = $invoice.RemainingAmount
    }
    if ($Amount -le 0) {
        throw "Payment amount must be greater than zero."
    }
    if ($Amount -gt $invoice.RemainingAmount) {
        throw "Payment amount $Amount exceeds the remaining amount $($invoice.RemainingAmount) on invoice $InvoiceNumber."
    }

    # Resolve the fiscal year from the payment date unless one was supplied.
    if (-not $FiscalYear) {
        $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $Date
        if (-not $FiscalYear) {
            throw "No fiscal year covers the payment date $($Date.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
        }
    }

    $rows = @(
        @{ Account = $Account; Amount = $Amount }
        @{ Account = $invoice.ReceivableAccount; Amount = -$Amount }
    )
    $description = "Betalning kundfaktura $InvoiceNumber"

    if (-not $PSCmdlet.ShouldProcess("Invoice $InvoiceNumber", "Register payment of $Amount")) {
        return
    }

    $verification = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
        -Date $Date -Description $description -Rows $rows -PassThru

    $invoice.Payments += [PSCustomObject]@{
        Date               = $Date
        Amount             = $Amount
        VerificationNumber = $verification.VerificationNumber
        FiscalYear         = $FiscalYear
    }

    $paid = ($invoice.Payments | Measure-Object -Property Amount -Sum).Sum
    $invoice.Status = if ([Math]::Round($invoice.Total - $paid, 2) -le 0) { 'Paid' } else { 'Partial' }

    Save-LedgerInvoiceFile -Invoice $invoice

    if ($PassThru) {
        Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
    }
}
