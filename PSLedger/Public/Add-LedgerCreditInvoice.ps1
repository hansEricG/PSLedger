<#
.SYNOPSIS
Creates a credit invoice (kreditfaktura) that reverses a posted customer invoice.

.DESCRIPTION
Creates a new credit-note invoice with negated rows for an existing, posted
invoice and books a reversing verification: the receivable account is credited
with the gross total, and revenue and VAT are debited back. Both the original
invoice and the new credit note are marked with status 'Credited' so the
accounts receivable reconciles to zero for the pair.

Only an invoice with status 'Booked' (posted but unpaid) can be credited:
- a 'Draft' invoice has no verification to reverse — post it first, or just delete it;
- an invoice with payments ('Partial'/'Paid') must have its payments handled first;
- an already 'Credited' invoice cannot be credited again.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the posted invoice to credit.

.PARAMETER Date
The date of the credit note and its reversing verification. Defaults to today.

.PARAMETER FiscalYear
Optional. The fiscal year to post the reversal into. If omitted, the fiscal year
containing -Date is used.

.PARAMETER PassThru
If specified, returns the created credit-note invoice object. By default the
command produces no output.

.EXAMPLE
Add-LedgerCreditInvoice -JournalPath .\MinFirma.ledger -InvoiceNumber 1

Credits invoice 1, creating a credit note and a reversing verification such as:
  1510 Kundfordringar  -12500
  3010 Försäljning     +10000
  2610 Utgående moms    +2500

.EXAMPLE
Add-LedgerCreditInvoice -InvoiceNumber 5 -Date '2024-04-30' -PassThru

Credits invoice 5 as of 30 April 2024 and returns the created credit note.
#>
function Add-LedgerCreditInvoice {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

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

    $original = Read-LedgerInvoiceFile -Path $filePath

    switch ($original.Status) {
        'Booked' { }
        'Draft' { throw "Invoice $InvoiceNumber is not posted. Post it first with Invoke-LedgerInvoicePosting, or delete the draft." }
        'Credited' { throw "Invoice $InvoiceNumber has already been credited." }
        default { throw "Invoice $InvoiceNumber has payments (status '$($original.Status)') and cannot be credited. Handle the payments first." }
    }

    # Resolve the fiscal year from the credit-note date unless one was supplied.
    if (-not $FiscalYear) {
        $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $Date
        if (-not $FiscalYear) {
            throw "No fiscal year covers the date $($Date.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
        }
    }

    # Build the reversing verification: negate the original posting.
    $accountSums = [ordered]@{}
    $addAmount = {
        param($account, $amount)
        if ($accountSums.Contains($account)) { $accountSums[$account] += $amount }
        else { $accountSums[$account] = $amount }
    }

    & $addAmount $original.ReceivableAccount (-$original.Total)
    foreach ($row in $original.Rows) {
        & $addAmount $row.Account $row.Amount
        if ($row.VatAmount -ne 0) {
            & $addAmount $row.VatAccount $row.VatAmount
        }
    }

    $entryRows = foreach ($account in $accountSums.Keys) {
        @{ Account = $account; Amount = [Math]::Round([decimal]$accountSums[$account], 2) }
    }

    # Allocate the next journal-wide invoice number for the credit note.
    $existing = Get-ChildItem -Path $invoiceDir -Filter 'inv*.txt' -File -ErrorAction SilentlyContinue
    if ($existing) {
        $maxNum = $existing |
            ForEach-Object { if ($_.BaseName -match '^inv(\d+)$') { [int]$Matches[1] } } |
            Measure-Object -Maximum |
            Select-Object -ExpandProperty Maximum
        $creditNumber = $maxNum + 1
    }
    else {
        $creditNumber = 1
    }

    $description = "Kreditfaktura $creditNumber - kreditering av faktura $InvoiceNumber"

    if (-not $PSCmdlet.ShouldProcess("Invoice $InvoiceNumber", "Create credit invoice $creditNumber")) {
        return
    }

    # Snapshot the original invoice and track the files this call creates so a
    # failure part-way through the multi-file booking can be rolled back, leaving
    # no half-applied credit (a booked verification without the paired invoice
    # status updates, or vice versa).
    $originalSnapshot = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    $creditNotePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $creditNumber)
    $verification = $null

    try {
        $verification = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
            -Date $Date -Description $description -Rows @($entryRows) -PassThru

        # Persist the credit note with negated rows.
        $creditRows = foreach ($row in $original.Rows) {
            [PSCustomObject]@{
                Account    = $row.Account
                Amount     = - [decimal]$row.Amount
                VatRate    = $row.VatRate
                VatAccount = $row.VatAccount
                VatAmount  = - [decimal]$row.VatAmount
            }
        }

        $creditNote = [PSCustomObject]@{
            InvoiceNumber      = $creditNumber
            CustomerNumber     = $original.CustomerNumber
            InvoiceDate        = $Date
            DueDate            = $Date
            Description        = "Kreditfaktura för faktura $InvoiceNumber"
            Status             = 'Credited'
            ReceivableAccount  = $original.ReceivableAccount
            BookedVerification = $verification.VerificationNumber
            BookedFiscalYear   = $FiscalYear
            Rows               = @($creditRows)
            Payments           = @()
            FilePath           = $creditNotePath
        }
        Save-LedgerInvoiceFile -Invoice $creditNote

        # Mark the original as credited so the receivable nets to zero.
        $original.Status = 'Credited'
        Save-LedgerInvoiceFile -Invoice $original
    }
    catch {
        # Undo any partial writes: remove the reversing verification and the
        # credit note, and restore the original invoice to its pre-call content.
        if ($verification) {
            $verPath = Join-Path (Join-Path $JournalPath $FiscalYear) ('ver' + $verification.VerificationNumber.ToString('0000') + '.txt')
            if (Test-Path -LiteralPath $verPath) {
                Remove-Item -LiteralPath $verPath -Force -ErrorAction SilentlyContinue
            }
        }
        if (Test-Path -LiteralPath $creditNotePath) {
            Remove-Item -LiteralPath $creditNotePath -Force -ErrorAction SilentlyContinue
        }
        Set-Content -LiteralPath $filePath -Value $originalSnapshot -NoNewline -Encoding UTF8
        throw
    }

    if ($PassThru) {
        Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $creditNumber
    }
}
