<#
.SYNOPSIS
Books a reminder fee or late-payment compensation (påminnelseavgift /
förseningsersättning) on a posted, unpaid customer invoice.

.DESCRIPTION
Records a fee as an actual bookkeeping charge on the invoice: the invoice's
receivable account is debited and an income account is credited with the fee
amount (no VAT). The fee is appended to the invoice's charges, which increases
the invoice total and the open receivable, so the accounts receivable continues
to reconcile against the general ledger.

Use this to book a statutory reminder fee (påminnelseavgift, max 60 kr) or the
late-payment compensation for business debts (förseningsersättning, 450 kr).
Neither is subject to VAT.

Only a posted, unpaid invoice (status Booked or Partial) can be charged a fee.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the invoice to charge.

.PARAMETER Amount
The fee amount. Must be greater than zero.

.PARAMETER Date
The date the fee is booked. Defaults to today.

.PARAMETER Account
The income account the fee is credited to. Defaults to '3590' (Övriga
sidointäkter).

.PARAMETER FiscalYear
Optional. The fiscal year to post the verification into. If omitted, the fiscal
year containing the charge date is used.

.PARAMETER PassThru
If specified, returns the updated invoice object.

.EXAMPLE
Add-LedgerInvoiceFee -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Amount 60

Books a 60 kr reminder fee on invoice 1 (debit 1510, credit 3590).

.EXAMPLE
Add-LedgerInvoiceFee -InvoiceNumber 1 -Amount 450 -Date '2024-05-20' -Account '3590'

Books the 450 kr statutory late-payment compensation (förseningsersättning) for a
business invoice.
#>
function Add-LedgerInvoiceFee {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber,

        [Parameter(Mandatory)]
        [decimal]$Amount,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [string]$Account = '3590',

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not $PSCmdlet.ShouldProcess("Invoice $InvoiceNumber", "Book fee of $Amount")) {
        return
    }

    Add-LedgerInvoiceChargeInternal -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber `
        -Type 'Fee' -Amount $Amount -Account $Account -Date $Date -FiscalYear $FiscalYear

    if ($PassThru) {
        Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
    }
}
