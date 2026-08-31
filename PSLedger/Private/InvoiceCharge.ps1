# Helper for booking a late charge (reminder fee, late-payment compensation or
# late-payment interest) onto a posted customer invoice. A charge debits the
# invoice's receivable account and credits an income account, and is appended to
# the invoice's 'Charges:' section so it increases the invoice total (and thus the
# open receivable) while staying reconciled against the general ledger.

function Add-LedgerInvoiceChargeInternal {
    <#
    .SYNOPSIS
    Books a late charge on a posted, unpaid invoice and records it on the invoice.

    .DESCRIPTION
    Debits the invoice's receivable account and credits the supplied income
    account with the charge amount (no VAT), then appends the charge to the
    invoice's Charges section. Returns the updated invoice store object.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber,

        [Parameter(Mandatory)]
        [ValidateSet('Fee', 'Interest')]
        [string]$Type,

        [Parameter(Mandatory)]
        [decimal]$Amount,

        [Parameter(Mandatory)]
        [string]$Account,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [string]$FiscalYear
    )

    $invoiceDir = Get-LedgerInvoiceDirectory -JournalPath $JournalPath
    $filePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
    if (-not (Test-Path $filePath)) {
        throw "Invoice $InvoiceNumber does not exist."
    }

    $invoice = Read-LedgerInvoiceFile -Path $filePath

    if ($invoice.Status -eq 'Draft') {
        throw "Invoice $InvoiceNumber has not been posted. Post it first with Invoke-LedgerInvoicePosting."
    }
    if ($invoice.Status -notin @('Booked', 'Partial')) {
        throw "Invoice $InvoiceNumber is not an open receivable (status '$($invoice.Status)'). Charges can only be booked on posted, unpaid invoices."
    }
    if ($Amount -le 0) {
        throw "Charge amount must be greater than zero."
    }

    if (-not $FiscalYear) {
        $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $Date
        if (-not $FiscalYear) {
            throw "No fiscal year covers the charge date $($Date.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
        }
    }

    $label = if ($Type -eq 'Interest') { 'Dröjsmålsränta' } else { 'Påminnelseavgift' }
    $description = "$label kundfaktura $InvoiceNumber"

    $entryRows = @(
        @{ Account = $invoice.ReceivableAccount; Amount = $Amount }
        @{ Account = $Account; Amount = -$Amount }
    )

    $verification = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
        -Date $Date -Description $description -Rows $entryRows -PassThru

    $invoice.Charges += [PSCustomObject]@{
        Date               = $Date
        Type               = $Type
        Amount             = $Amount
        Account            = $Account
        VerificationNumber = $verification.VerificationNumber
        FiscalYear         = $FiscalYear
    }

    Save-LedgerInvoiceFile -Invoice $invoice
}
