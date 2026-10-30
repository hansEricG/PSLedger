<#
.SYNOPSIS
Registers a payment of a posted supplier invoice.

.DESCRIPTION
Records a payment for a Booked or Partial supplier invoice: the payable account
(2440 Leverantörsskulder) is debited and the cash/bank account is credited with
the payment amount. The fiscal year is resolved from the payment date unless one
is supplied.

Partial payments are supported — when the accumulated payments are still less
than the invoice total the status becomes 'Partial'; once the invoice is fully
paid it becomes 'Paid'. The payment is recorded on the invoice together with the
verification it created so the payable can be reconciled against the ledger.

Use a stable PaymentId for safe retries. Reusing the ID resumes its saved plan
or returns the current supplier invoice without recording a completed payment
again. Different IDs permit identical real partial payments. Without an ID,
each call starts a new payment; an unfinished payment blocks new payments and
reports the ID to resume. Keep plans after completion and in backups.
A matching saved verification may finish payment after year closure, but no
new verification is created in a closed year.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the supplier invoice being paid. It must have been posted first
with Invoke-LedgerSupplierInvoicePosting.

.PARAMETER Date
The payment date. Defaults to today.

.PARAMETER Amount
The amount paid. Defaults to the invoice's remaining unpaid amount. Must be
greater than zero and not exceed the remaining amount.

.PARAMETER Account
The cash or bank account the payment is made from. Defaults to '1930'
(Företagskonto/checkkonto).

.PARAMETER FiscalYear
Optional. The fiscal year to post the payment verification into. If omitted, the
fiscal year containing the payment date is used.

.PARAMETER PassThru
If specified, returns the updated supplier invoice object. By default the command
produces no output.

.PARAMETER PaymentId
Optional non-empty GUID identifying this payment across retries. Generate and
retain it before the first attempt. IDs are unique across customer and supplier
payments in the journal. Omitted retry inputs use the saved plan.

.EXAMPLE
Add-LedgerSupplierPayment -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Date '2024-04-10'

Registers full payment of supplier invoice 1 from the default bank account 1930.

.EXAMPLE
Add-LedgerSupplierPayment -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' -Account '1910'

Registers a partial cash payment of 5 000 kr from account 1910 (Kassa), leaving
the invoice in 'Partial' status.

.EXAMPLE
$paymentId = New-Guid
Add-LedgerSupplierPayment -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' -PaymentId $paymentId
Add-LedgerSupplierPayment -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -PaymentId $paymentId -PassThru

Registers a partial payment to a supplier, then safely resumes or retrieves
that payment without recording another one.
#>
function Add-LedgerSupplierPayment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared payment writer performs ShouldProcess; common parameters are forwarded.')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
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
        [ValidateScript({ if ($_ -eq [guid]::Empty) { throw 'PaymentId must not be an empty GUID.' }; $true })]
        [guid]$PaymentId,

        [Parameter()]
        [switch]$PassThru
    )
    process {
        Add-LedgerInvoicePaymentInternal @PSBoundParameters -InvoiceType Supplier
    }
}
