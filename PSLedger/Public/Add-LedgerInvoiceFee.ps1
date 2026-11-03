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

.PARAMETER ChargeId
Optional stable identity for the fee. Supply the same ChargeId to safely retry a
call that may have been interrupted: a completed fee is not booked again and an
unfinished one is completed. Without a ChargeId every call books a new fee, and
an interrupted call blocks further changes to the invoice until it is resumed
with the ChargeId shown in the error.

.PARAMETER PassThru
If specified, returns the updated invoice object.

.EXAMPLE
Add-LedgerInvoiceFee -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Amount 60

Books a 60 kr reminder fee on invoice 1 (debit 1510, credit 3590).

.EXAMPLE
Add-LedgerInvoiceFee -InvoiceNumber 1 -Amount 450 -Date '2024-05-20' -Account '3590'

Books the 450 kr statutory late-payment compensation (förseningsersättning) for a
business invoice.

.EXAMPLE
$chargeId = [guid]::NewGuid()
Add-LedgerInvoiceFee -JournalPath .\Volvo.ledger -InvoiceNumber 12 -Amount 450 -ChargeId $chargeId

Books late-payment compensation with a stable identity. Repeating the same
command after an interruption completes the fee instead of booking it twice.
#>
function Add-LedgerInvoiceFee {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared charge writer performs ShouldProcess; common parameters are forwarded.')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
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
        [ValidateScript({ if ($_ -eq [guid]::Empty) { throw 'ChargeId must not be an empty GUID.' }; $true })]
        [guid]$ChargeId,

        [Parameter()]
        [switch]$PassThru
    )
    process {
        $parameters = @{} + $PSBoundParameters
        $parameters.Remove('PassThru')
        $parameters.JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        if (-not (Add-LedgerInvoiceChargeInternal @parameters -Type 'Fee')) {
            return
        }

        if ($PassThru) {
            Get-LedgerInvoice -JournalPath $parameters.JournalPath -InvoiceNumber $InvoiceNumber
        }
    }
}
