<#
.SYNOPSIS
Registers a payment against a posted customer invoice.

.DESCRIPTION
Debits the cash/bank account and credits accounts receivable for a Booked or
Partial invoice. The payment is recorded with its verification; the invoice
becomes Partial or Paid according to its remaining amount.

Use a stable PaymentId for safe retries. Reusing the ID resumes its saved plan
or returns the current invoice without recording a completed payment again.
Changed inputs are rejected. Without an ID each call starts a new payment;
an unfinished payment blocks new payments and reports the ID to resume.
Keep payment plans after completion and in backups.

A matching saved verification may finish the payment after year closure,
but a new verification is never created in a closed year.

.PARAMETER JournalPath
Path to the journal. If omitted, uses the current journal.

.PARAMETER InvoiceNumber
Number of the posted customer invoice being paid.

.PARAMETER Date
Payment date. Defaults to today, or the saved date when retrying a PaymentId.

.PARAMETER Amount
Positive payment amount, not exceeding the remaining amount. Defaults to the
remaining amount, or the saved amount when retrying a PaymentId.

.PARAMETER Account
Cash/bank account. Defaults to 1930, or the saved account on a PaymentId retry.

.PARAMETER FiscalYear
Optional fiscal year. Otherwise resolved from the payment date or saved plan.

.PARAMETER PaymentId
Optional non-empty GUID identifying the payment in this journal. Generate it
once with New-Guid and retain it before the first attempt. Different IDs allow
separate payments with identical dates and amounts.

.PARAMETER PassThru
Returns the current invoice object. Otherwise produces no output.

.EXAMPLE
Add-LedgerInvoicePayment -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Date '2024-04-10'

Registers full payment into bank account 1930.

.EXAMPLE
$paymentId = New-Guid
Add-LedgerInvoicePayment -JournalPath .\Volvo.ledger -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' -PaymentId $paymentId
Add-LedgerInvoicePayment -JournalPath .\Volvo.ledger -InvoiceNumber 1 -PaymentId $paymentId -PassThru

Registers a partial payment, then safely resumes or retrieves it without
recording a second payment.
#>
function Add-LedgerInvoicePayment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared payment writer performs ShouldProcess; common parameters are forwarded.')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()] [string]$JournalPath,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [int]$InvoiceNumber,
        [Parameter()] [datetime]$Date = (Get-Date).Date,
        [Parameter()] [decimal]$Amount,
        [Parameter()] [string]$Account = '1930',
        [Parameter()] [string]$FiscalYear,
        [Parameter()]
        [ValidateScript({ if ($_ -eq [guid]::Empty) { throw 'PaymentId must not be an empty GUID.' }; $true })]
        [guid]$PaymentId,
        [Parameter()] [switch]$PassThru
    )
    process {
        Add-LedgerInvoicePaymentInternal @PSBoundParameters
    }
}
