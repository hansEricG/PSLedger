<#
.SYNOPSIS
Posts a supplier invoice to the ledger, creating a bookkeeping verification.

.DESCRIPTION
Creates a verification for a Draft supplier invoice: each cost account is debited
with its net amount, each input-VAT account is debited with its VAT, and the
payable account (2440 Leverantörsskulder) is credited with the gross total. The
fiscal year is resolved from the invoice date unless one is supplied explicitly.

After posting, the invoice status becomes 'Booked' and the verification number
and fiscal year are recorded on the invoice so the payable can always be
reconciled against the ledger.

The operation refuses to run twice for the same invoice (an already-posted
invoice throws).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the supplier invoice to post.

.PARAMETER FiscalYear
Optional. The fiscal year to post the verification into. If omitted, the fiscal
year containing the invoice date is used.

.PARAMETER PassThru
If specified, returns the updated supplier invoice object. By default the command
produces no output.

.EXAMPLE
Invoke-LedgerSupplierInvoicePosting -JournalPath .\MinFirma.ledger -InvoiceNumber 1

Posts supplier invoice 1, creating a verification such as:
  5010 Lokalhyra          +8000
  2640 Ingående moms      +2000
  2440 Leverantörsskulder -10000

.EXAMPLE
Get-LedgerSupplierInvoice -Status Draft | ForEach-Object { Invoke-LedgerSupplierInvoicePosting -InvoiceNumber $_.InvoiceNumber }

Posts every draft supplier invoice in the current journal.
#>
function Invoke-LedgerSupplierInvoicePosting {
    [CmdletBinding()]
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

    $invoiceDir = Get-LedgerSupplierInvoiceDirectory -JournalPath $JournalPath
    $filePath = Join-Path $invoiceDir (Get-LedgerSupplierInvoiceFileName -InvoiceNumber $InvoiceNumber)
    if (-not (Test-Path $filePath)) {
        throw "Supplier invoice $InvoiceNumber does not exist."
    }

    $invoice = Read-LedgerSupplierInvoiceFile -Path $filePath

    if ($invoice.Status -ne 'Draft') {
        throw "Supplier invoice $InvoiceNumber is already posted (status '$($invoice.Status)', verification $($invoice.BookedVerification))."
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

    # Debit cost accounts (net) and input VAT.
    foreach ($row in $invoice.Rows) {
        & $addAmount $row.Account $row.Amount
        if ($row.VatAmount -ne 0) {
            & $addAmount $row.VatAccount $row.VatAmount
        }
    }

    # Credit the payable with the gross total.
    & $addAmount $invoice.PayableAccount (-$invoice.Total)

    $entryRows = foreach ($account in $accountSums.Keys) {
        @{ Account = $account; Amount = [Math]::Round([decimal]$accountSums[$account], 2) }
    }

    $description = "Leverantörsfaktura $InvoiceNumber - $($invoice.Description)"

    $verification = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
        -Date $invoice.InvoiceDate -Description $description -Rows @($entryRows) -PassThru

    $invoice.Status = 'Booked'
    $invoice.BookedVerification = $verification.VerificationNumber
    $invoice.BookedFiscalYear = $FiscalYear
    Save-LedgerSupplierInvoiceFile -Invoice $invoice

    if ($PassThru) {
        Get-LedgerSupplierInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
    }
}
