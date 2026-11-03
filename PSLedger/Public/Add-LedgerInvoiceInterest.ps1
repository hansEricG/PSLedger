<#
.SYNOPSIS
Calculates and books late-payment interest (dröjsmålsränta) on a posted, unpaid
customer invoice.

.DESCRIPTION
Books late-payment interest as an actual bookkeeping charge on the invoice: the
invoice's receivable account is debited and an interest income account is
credited with the interest amount (no VAT). The interest is appended to the
invoice's charges, which increases the invoice total and the open receivable, so
the accounts receivable continues to reconcile against the general ledger.

The interest amount is either supplied explicitly with -Amount, or calculated
from an annual rate as:

    interest = remaining amount * AnnualRate * daysOverdue / 365

where daysOverdue is the number of days from the invoice due date to the charge
date. Supply either -AnnualRate or -Amount.

Only a posted, unpaid invoice (status Booked or Partial) can be charged interest.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the invoice to charge interest on.

.PARAMETER AnnualRate
The annual interest rate as a fraction (e.g. 0.105 for 10.5 %). The interest is
calculated on the invoice's remaining amount for the number of days the invoice
is overdue. Ignored when -Amount is given.

.PARAMETER Amount
An explicit interest amount to book, overriding the calculation. Must be greater
than zero.

.PARAMETER Date
The date the interest is calculated to and booked. Defaults to today.

.PARAMETER Account
The interest income account. Defaults to '8310' (Ränteintäkter).

.PARAMETER FiscalYear
Optional. The fiscal year to post the verification into. If omitted, the fiscal
year containing the charge date is used.

.PARAMETER ChargeId
Optional stable identity for the interest charge. Supply the same ChargeId to
safely retry a call that may have been interrupted: completed interest is not
booked again, and an unfinished charge is completed with its originally planned
amount. Without a ChargeId every call books new interest, and an interrupted call
blocks further changes to the invoice until it is resumed with the ChargeId shown
in the error.

.PARAMETER PassThru
If specified, returns the updated invoice object.

.EXAMPLE
Add-LedgerInvoiceInterest -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -AnnualRate 0.105 -Date '2024-06-01'

Calculates late-payment interest at 10.5 % on invoice 1's remaining amount for the
days it is overdue and books it (debit 1510, credit 8310).

.EXAMPLE
Add-LedgerInvoiceInterest -InvoiceNumber 1 -Amount 250

Books an explicit 250 kr interest charge on invoice 1.

.EXAMPLE
$chargeId = [guid]::NewGuid()
Add-LedgerInvoiceInterest -JournalPath .\Volvo.ledger -InvoiceNumber 12 -AnnualRate 0.105 -Date '2024-06-01' -ChargeId $chargeId

Books interest with a stable identity, so the same command can be repeated after
an interruption without booking the interest twice.
#>
function Add-LedgerInvoiceInterest {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared charge writer performs ShouldProcess; common parameters are forwarded.')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$InvoiceNumber,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [decimal]$AnnualRate,

        [Parameter()]
        [decimal]$Amount,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [string]$Account = '8310',

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [ValidateScript({ if ($_ -eq [guid]::Empty) { throw 'ChargeId must not be an empty GUID.' }; $true })]
        [guid]$ChargeId,

        [Parameter()]
        [switch]$PassThru
    )
    process {
        $parameters = @{} + $PSBoundParameters
        $parameters.Remove('PassThru')
        $parameters.JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        if (-not (Add-LedgerInvoiceChargeInternal @parameters -Type 'Interest')) {
            return
        }

        if ($PassThru) {
            Get-LedgerInvoice -JournalPath $parameters.JournalPath -InvoiceNumber $InvoiceNumber
        }
    }
}
