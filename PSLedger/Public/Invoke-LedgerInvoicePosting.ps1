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

Before writing, the command saves an immutable posting plan under
invoices/posting/ with a reserved verification number and content hashes.
If interrupted, run the same command again: it reuses and, if needed, seals
the matching saved verification before completing the invoice status. Changed
inputs, a conflicting verification or integrity errors stop recovery.

A matching existing verification may be completed even after its fiscal year
has closed; a new verification is never created in a closed year. Already-posted
invoices still throw, so repeating a completed operation cannot post it twice.

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

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$InvoiceNumber,

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [switch]$PassThru
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $journalLock = $null
        try {
            $journalLock = Enter-LedgerJournalLock -JournalPath $JournalPath
            Assert-LedgerJournalSchema -Path $JournalPath -Write

            $invoiceDir = Get-LedgerInvoiceDirectory -JournalPath $JournalPath
            $filePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
            if (-not (Test-Path $filePath)) {
                throw "Invoice $InvoiceNumber does not exist."
            }

            $invoice = Read-LedgerInvoiceFile -Path $filePath

            if ($invoice.Status -ne 'Draft') {
                throw "Invoice $InvoiceNumber is already posted (status '$($invoice.Status)', verification $($invoice.BookedVerification))."
            }
            if ($invoice.InvoiceNumber -ne $InvoiceNumber -or $invoice.BookedVerification -or $invoice.BookedFiscalYear) {
                throw "Draft invoice $InvoiceNumber has inconsistent identity or posting references. Inspect it before posting."
            }

            $operationPath = Get-LedgerInvoicePostingPath -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
            $operation = if (Test-Path -LiteralPath $operationPath) { Read-LedgerInvoicePosting -Path $operationPath } else { $null }
            $invoiceHash = Get-LedgerContentHash -Path $filePath
            $postingYear = $FiscalYear
            if ($operation) {
                if ($invoiceHash -ne $operation.InvoiceHash) {
                    throw "Invoice $InvoiceNumber has changed since its posting plan was saved. Recovery stopped without modifying the invoice or verification."
                }
                if ($postingYear -and $postingYear -ne $operation.FiscalYear) {
                    throw "Invoice $InvoiceNumber has a posting plan for $($operation.FiscalYear), not $postingYear."
                }
                $postingYear = $operation.FiscalYear
            }

            # Resolve the fiscal year from the invoice date unless one was supplied.
            if (-not $postingYear) {
                $postingYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $invoice.InvoiceDate
                if (-not $postingYear) {
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
            $operationId = if ($operation) { $operation.OperationId } else { [guid]::NewGuid() }
            $entryParameters = @{
                JournalPath = $JournalPath; FiscalYear = $postingYear; Date = $invoice.InvoiceDate
                Description = $description; Rows = @($entryRows); OperationId = $operationId
            }
            $existingVerification = $false
            if ($operation) {
                $verificationPath = Join-Path $JournalPath $postingYear ('ver' + $operation.VerificationNumber.ToString('0000') + '.txt')
                $existingVerification = Test-Path -LiteralPath $verificationPath
                if ($existingVerification) {
                    Assert-LedgerInvoicePostingVerification -Path $verificationPath -Operation $operation
                }
            }
            $unsealedNumber = if ($existingVerification) { $operation.VerificationNumber } else { 0 }
            Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $postingYear -UnsealedVerification $unsealedNumber
            if (-not $existingVerification) {
                $lines = @(Get-LedgerVerificationLines @entryParameters)
                $verificationHash = Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
                if ($operation -and $verificationHash -ne $operation.VerificationHash) {
                    throw "Invoice $InvoiceNumber no longer produces the saved verification plan. Recovery stopped."
                }
                if (-not $operation) {
                    $operation = [pscustomobject]@{
                        OperationId = $operationId
                        InvoiceNumber = $InvoiceNumber
                        FiscalYear = $postingYear
                        VerificationNumber = Get-LedgerNextVerificationNumber -JournalPath $JournalPath -FiscalYear $postingYear
                        InvoiceHash = $invoiceHash
                        VerificationHash = $verificationHash
                    }
                }
            }

            if (-not $PSCmdlet.ShouldProcess("Invoice $InvoiceNumber", "Post to fiscal year $postingYear")) {
                return
            }

            if (-not (Test-Path -LiteralPath $operationPath)) {
                Save-LedgerInvoicePosting -Path $operationPath -Operation $operation
            }
            try {
                if (-not $existingVerification) {
                    Write-LedgerVerification @entryParameters -ReservedNumber $operation.VerificationNumber -Confirm:$false
                }
                Complete-LedgerInvoicePostingVerification -JournalPath $JournalPath -Operation $operation
                if ((Get-LedgerContentHash -Path $filePath) -ne $operation.InvoiceHash) {
                    throw "Invoice $InvoiceNumber changed during posting. Its saved verification was not removed."
                }

                $invoice.Status = 'Booked'
                $invoice.BookedVerification = $operation.VerificationNumber
                $invoice.BookedFiscalYear = $postingYear
                Save-LedgerInvoiceFile -Invoice $invoice
            }
            catch {
                throw [System.InvalidOperationException]::new(
                    "Could not confirm completion of invoice $InvoiceNumber posting. Keep '$operationPath' and its reserved verification; rerun Invoke-LedgerInvoicePosting for this invoice to recover safely. $($_.Exception.Message)",
                    $_.Exception)
            }

            if ($PassThru) {
                Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
            }
        }
        finally { Exit-LedgerJournalLock -Lock $journalLock }
    }
}
