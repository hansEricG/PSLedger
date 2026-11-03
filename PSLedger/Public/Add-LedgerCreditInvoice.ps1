<#
.SYNOPSIS
Creates a credit invoice (kreditfaktura) that reverses a posted customer invoice.

.DESCRIPTION
Creates a new credit-note invoice with negated rows for an existing, posted
invoice and books a reversing verification: the receivable account is credited
with the gross total, and revenue and VAT are debited back. Booked fees and
interest on the invoice are reversed too: their income accounts are debited and
the credit note carries the negated charges. Both the original
invoice and the new credit note are marked with status 'Credited' so the
accounts receivable reconciles to zero for the pair.

Only an invoice with status 'Booked' (posted but unpaid) can be credited:
- a 'Draft' invoice has no verification to reverse — post it first, or just delete it;
- an invoice with payments ('Partial'/'Paid') must have its payments handled first;
- an already 'Credited' invoice cannot be credited again.

Crediting is safely resumable. Before the verification is written, an immutable
plan in invoices/credits/ reserves the credit-note number and verification
number. If the command is interrupted, run it again for the same invoice: it
completes the saved credit (verification, credit note and status) without
creating a second credit note or verification. Other changes to the invoice are
blocked until the credit is completed.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the posted invoice to credit.

.PARAMETER Date
The date of the credit note and its reversing verification. Defaults to today.
When an interrupted credit is resumed, the planned date is used.

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

Credits invoice 5 as of 30 April 2024 and returns the created credit note. If the
call is interrupted, repeating it completes the same credit note. Any booked
reminder fee or interest on invoice 5 is reversed as well (e.g. debit 3590).
#>
function Add-LedgerCreditInvoice {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$InvoiceNumber,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

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

            $original = Read-LedgerInvoiceFile -Path $filePath
            if ($original.InvoiceNumber -ne $InvoiceNumber) {
                throw "Invoice $InvoiceNumber has an inconsistent identity."
            }
            $operationPath = Get-LedgerInvoiceCreditPath -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
            $operation = if (Test-Path -LiteralPath $operationPath) { Read-LedgerInvoiceCreditOperation -Path $operationPath } else { $null }
            $creditDate = $Date.Date
            $creditYear = $FiscalYear
            if ($operation) {
                if (($PSBoundParameters.ContainsKey('Date') -and $Date.Date -ne $operation.CreditDate) -or
                    ($FiscalYear -and $FiscalYear -ne $operation.FiscalYear)) {
                    throw "Invoice $InvoiceNumber has a saved credit plan dated $($operation.CreditDate.ToString('yyyy-MM-dd')) in $($operation.FiscalYear). Use its original inputs to retry."
                }
                $creditDate = $operation.CreditDate
                $creditYear = $operation.FiscalYear
                $creditNotePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $operation.CreditInvoiceNumber)
                if ($original.Status -eq 'Credited') {
                    if (-not (Test-Path -LiteralPath $creditNotePath)) {
                        throw "Invoice $InvoiceNumber is credited, but its planned credit invoice $($operation.CreditInvoiceNumber) is missing. Recovery stopped."
                    }
                    Assert-LedgerCreditNote -CreditNote (Read-LedgerInvoiceFile -Path $creditNotePath) -Original $original -Operation $operation
                    $verificationPath = Join-Path $JournalPath $creditYear ('ver{0:D4}.txt' -f $operation.VerificationNumber)
                    Assert-LedgerInvoicePostingVerification -Path $verificationPath -Operation $operation
                    Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $creditYear
                    if ($PassThru -and -not $WhatIfPreference) {
                        Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $operation.CreditInvoiceNumber
                    }
                    return
                }
                if ((Get-LedgerContentHash -Path $filePath) -ne $operation.InvoiceHash) {
                    throw "Invoice $InvoiceNumber has changed since its credit was planned. Recovery stopped."
                }
            }
            Assert-LedgerNoPendingInvoicePayment -JournalPath $JournalPath -Invoice $original -ExceptCredit

            switch ($original.Status) {
                'Booked' { }
                'Draft' { throw "Invoice $InvoiceNumber is not posted. Post it first with Invoke-LedgerInvoicePosting, or delete the draft." }
                'Credited' { throw "Invoice $InvoiceNumber has already been credited." }
                default { throw "Invoice $InvoiceNumber has payments (status '$($original.Status)') and cannot be credited. Handle the payments first." }
            }

            # Resolve the fiscal year from the credit-note date unless one was supplied.
            if (-not $creditYear) {
                $creditYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $creditDate
                if (-not $creditYear) {
                    throw "No fiscal year covers the date $($creditDate.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
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
            foreach ($charge in $original.Charges) {
                & $addAmount $charge.Account $charge.Amount
            }

            $entryRows = foreach ($account in $accountSums.Keys) {
                @{ Account = $account; Amount = [Math]::Round([decimal]$accountSums[$account], 2) }
            }

            $creditNumber = if ($operation) { $operation.CreditInvoiceNumber } else { Get-LedgerNextInvoiceNumber -JournalPath $JournalPath }
            $creditNotePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $creditNumber)
            $operationId = if ($operation) { $operation.OperationId } else { [guid]::NewGuid() }
            $entryParameters = @{
                JournalPath = $JournalPath; FiscalYear = $creditYear; Date = $creditDate
                Description = "Kreditfaktura $creditNumber - kreditering av faktura $InvoiceNumber"
                Rows = @($entryRows); OperationId = $operationId
            }
            $existingVerification = $false
            if ($operation) {
                $verificationPath = Join-Path $JournalPath $creditYear ('ver{0:D4}.txt' -f $operation.VerificationNumber)
                $existingVerification = Test-Path -LiteralPath $verificationPath
                if ($existingVerification) { Assert-LedgerInvoicePostingVerification -Path $verificationPath -Operation $operation }
            }
            elseif (Test-Path -LiteralPath $creditNotePath) {
                throw "Credit invoice number $creditNumber is already in use. Recovery stopped."
            }
            $unsealedNumber = if ($existingVerification) { $operation.VerificationNumber } else { 0 }
            Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $creditYear -UnsealedVerification $unsealedNumber
            if (-not $existingVerification) {
                $lines = @(Get-LedgerVerificationLines @entryParameters)
                $hash = Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
                if ($operation -and $hash -ne $operation.VerificationHash) {
                    throw "Invoice $InvoiceNumber no longer produces the saved credit verification plan. Recovery stopped."
                }
                if (-not $operation) {
                    $operation = [pscustomobject]@{
                        OperationId = $operationId; InvoiceNumber = $InvoiceNumber; CreditInvoiceNumber = $creditNumber
                        FiscalYear = $creditYear
                        VerificationNumber = Get-LedgerNextVerificationNumber -JournalPath $JournalPath -FiscalYear $creditYear
                        InvoiceHash = Get-LedgerContentHash -Path $filePath; VerificationHash = $hash; CreditDate = $creditDate
                    }
                }
            }

            if (-not $PSCmdlet.ShouldProcess("Invoice $InvoiceNumber", "Create credit invoice $creditNumber")) {
                return
            }

            if (-not (Test-Path -LiteralPath $operationPath)) {
                Save-LedgerInvoiceCreditOperation -Path $operationPath -Operation $operation
            }
            try {
                if (-not $existingVerification) {
                    Write-LedgerVerification @entryParameters -ReservedNumber $operation.VerificationNumber -Confirm:$false
                }
                Complete-LedgerInvoicePostingVerification -JournalPath $JournalPath -Operation $operation
                if ((Get-LedgerContentHash -Path $filePath) -ne $operation.InvoiceHash) {
                    throw "Invoice $InvoiceNumber changed during crediting. Its saved verification was not removed."
                }

                if (Test-Path -LiteralPath $creditNotePath) {
                    Assert-LedgerCreditNote -CreditNote (Read-LedgerInvoiceFile -Path $creditNotePath) -Original $original -Operation $operation
                }
                else {
                    # Persist the credit note with negated rows.
                    $creditRows = foreach ($row in $original.Rows) {
                        [PSCustomObject]@{
                            Account     = $row.Account
                            Amount      = - [decimal]$row.Amount
                            VatRate     = $row.VatRate
                            VatAccount  = $row.VatAccount
                            VatAmount   = - [decimal]$row.VatAmount
                            Description = $row.Description
                            Quantity    = if ($null -ne $row.Quantity) { - [decimal]$row.Quantity } else { $null }
                            Unit        = $row.Unit
                            UnitPrice   = $row.UnitPrice
                        }
                    }
                    Save-LedgerInvoiceFile -Invoice ([PSCustomObject]@{
                            InvoiceNumber      = $creditNumber
                            CustomerNumber     = $original.CustomerNumber
                            InvoiceDate        = $creditDate
                            DueDate            = $creditDate
                            Description        = "Kreditfaktura för faktura $InvoiceNumber"
                            Status             = 'Credited'
                            ReceivableAccount  = $original.ReceivableAccount
                            BookedVerification = $operation.VerificationNumber
                            BookedFiscalYear   = $creditYear
                            Rows               = @($creditRows)
                            Payments           = @()
                            Charges            = @(foreach ($charge in $original.Charges) {
                                    [PSCustomObject]@{
                                        Date = $creditDate; Type = $charge.Type; Amount = - [decimal]$charge.Amount
                                        Account = $charge.Account; VerificationNumber = $operation.VerificationNumber; FiscalYear = $creditYear
                                    }
                                })
                            FilePath           = $creditNotePath
                        })
                }

                # Mark the original as credited so the receivable nets to zero.
                $original.Status = 'Credited'
                Save-LedgerInvoiceFile -Invoice $original
            }
            catch {
                throw [InvalidOperationException]::new(
                    "Could not confirm completion of the credit of invoice $InvoiceNumber. Keep '$operationPath' and its reserved numbers; rerun Add-LedgerCreditInvoice -JournalPath '$JournalPath' -InvoiceNumber $InvoiceNumber to recover safely. $($_.Exception.Message)",
                    $_.Exception)
            }

            if ($PassThru) {
                Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $creditNumber
            }
        }
        finally { Exit-LedgerJournalLock -Lock $journalLock }
    }
}
