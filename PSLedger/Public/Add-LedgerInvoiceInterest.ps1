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

.PARAMETER PassThru
If specified, returns the updated invoice object.

.EXAMPLE
Add-LedgerInvoiceInterest -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -AnnualRate 0.105 -Date '2024-06-01'

Calculates late-payment interest at 10.5 % on invoice 1's remaining amount for the
days it is overdue and books it (debit 1510, credit 8310).

.EXAMPLE
Add-LedgerInvoiceInterest -InvoiceNumber 1 -Amount 250

Books an explicit 250 kr interest charge on invoice 1.
#>
function Add-LedgerInvoiceInterest {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
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
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $invoiceDir = Get-LedgerInvoiceDirectory -JournalPath $JournalPath
    $filePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
    if (-not (Test-Path $filePath)) {
        throw "Invoice $InvoiceNumber does not exist."
    }
    $invoice = Read-LedgerInvoiceFile -Path $filePath

    if (-not $PSBoundParameters.ContainsKey('Amount')) {
        if (-not $PSBoundParameters.ContainsKey('AnnualRate')) {
            throw "Specify either -AnnualRate (to calculate interest) or -Amount (to book an explicit amount)."
        }
        $daysOverdue = [int]([datetime]$Date - [datetime]$invoice.DueDate).TotalDays
        if ($daysOverdue -le 0) {
            throw "Invoice $InvoiceNumber is not overdue on $($Date.ToString('yyyy-MM-dd')) (due $($invoice.DueDate.ToString('yyyy-MM-dd'))). No interest to charge."
        }
        $Amount = [Math]::Round([decimal]$invoice.RemainingAmount * $AnnualRate * $daysOverdue / 365, 2)
        if ($Amount -le 0) {
            throw "The calculated interest for invoice $InvoiceNumber is zero. Nothing to book."
        }
    }

    Add-LedgerInvoiceChargeInternal -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber `
        -Type 'Interest' -Amount $Amount -Account $Account -Date $Date -FiscalYear $FiscalYear

    if ($PassThru) {
        Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
    }
}
