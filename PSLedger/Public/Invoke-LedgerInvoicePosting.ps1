<#
.SYNOPSIS
Posts a customer invoice to the ledger, creating a bookkeeping verification.

.DESCRIPTION
Creates a verification for a Draft invoice: the accounts-receivable account is
debited with the gross total, each revenue account is credited with its net
amount and each VAT account is credited with its VAT. The fiscal year is resolved
from the invoice date unless one is supplied explicitly.

After posting, the invoice status becomes 'Booked' and the verification number
and fiscal year are recorded on the invoice so the receivable can always be
reconciled against the ledger.

The operation refuses to run twice for the same invoice (an already-posted
invoice throws).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the invoice to post.

.PARAMETER FiscalYear
Optional. The fiscal year to post the verification into. If omitted, the fiscal
year containing the invoice date is used.

.PARAMETER PassThru
If specified, returns the updated invoice object. By default the command
produces no output.

.EXAMPLE
Invoke-LedgerInvoicePosting -JournalPath .\MinFirma.ledger -InvoiceNumber 1

Posts invoice 1, creating a verification such as:
  1510 Kundfordringar  +12500
  3010 Försäljning      -10000
  2610 Utgående moms     -2500

.EXAMPLE
Get-LedgerInvoice -Status Draft | ForEach-Object { Invoke-LedgerInvoicePosting -InvoiceNumber $_.InvoiceNumber }

Posts every draft invoice in the current journal.
#>
function Invoke-LedgerInvoicePosting {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber,

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

    if ($invoice.Status -ne 'Draft') {
        throw "Invoice $InvoiceNumber is already posted (status '$($invoice.Status)', verification $($invoice.BookedVerification))."
    }

    # Resolve the fiscal year from the invoice date unless one was supplied.
    if (-not $FiscalYear) {
        $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $invoice.InvoiceDate
        if (-not $FiscalYear) {
            throw "No fiscal year covers the invoice date $($invoice.InvoiceDate.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
        }
    }

    # Aggregate amounts per account so the verification is compact.
    $accountSums = [ordered]@{}
    $addAmount = {
        param($account, $amount)
        if ($accountSums.Contains($account)) {
            $accountSums[$account] += $amount
        }
        else {
            $accountSums[$account] = $amount
        }
    }

    # Debit the receivable with the gross total.
    & $addAmount $invoice.ReceivableAccount $invoice.Total

    # Credit revenue (net) and VAT.
    foreach ($row in $invoice.Rows) {
        & $addAmount $row.Account (-$row.Amount)
        if ($row.VatAmount -ne 0) {
            & $addAmount $row.VatAccount (-$row.VatAmount)
        }
    }

    $entryRows = foreach ($account in $accountSums.Keys) {
        @{ Account = $account; Amount = [Math]::Round([decimal]$accountSums[$account], 2) }
    }

    $description = "Kundfaktura $InvoiceNumber - $($invoice.Description)"

    if (-not $PSCmdlet.ShouldProcess("Invoice $InvoiceNumber", "Post to fiscal year $FiscalYear")) {
        return
    }

    $verification = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
        -Date $invoice.InvoiceDate -Description $description -Rows @($entryRows) -PassThru

    $invoice.Status = 'Booked'
    $invoice.BookedVerification = $verification.VerificationNumber
    $invoice.BookedFiscalYear = $FiscalYear
    Save-LedgerInvoiceFile -Invoice $invoice

    if ($PassThru) {
        Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
    }
}
