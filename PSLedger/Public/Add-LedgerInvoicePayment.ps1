<#
.SYNOPSIS
Registers a payment against a posted customer invoice.

.DESCRIPTION
Records a payment for a Booked or Partial invoice: the cash/bank account is
debited and the accounts-receivable account is credited with the payment amount.
The fiscal year is resolved from the payment date unless one is supplied.

Partial payments are supported — when the accumulated payments are still less
than the invoice total the status becomes 'Partial'; once the invoice is fully
paid it becomes 'Paid'. The payment is recorded on the invoice together with the
verification it created so the receivable can be reconciled against the ledger.

Use a stable PaymentId for safe retries, including when the previous call may
already have completed. A saved plan reserves the verification number and
records the payment inputs. Reusing the ID resumes that plan or returns the
current invoice without recording the payment again. Changed inputs are rejected.
Without an ID, each call starts a new payment; an unfinished payment blocks new
payments and reports the ID to resume. Keep payment plans after completion.
A matching saved verification can finish the payment after year closure; no
new verification is created in a closed year.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the invoice being paid. It must have been posted first with
Invoke-LedgerInvoicePosting.

.PARAMETER Date
The payment date. Defaults to today.

.PARAMETER Amount
The amount received. Defaults to the invoice's remaining unpaid amount. Must be
greater than zero and not exceed the remaining amount.

.PARAMETER Account
The cash or bank account the payment is received into. Defaults to '1930'
(Företagskonto/checkkonto).

.PARAMETER FiscalYear
Optional. The fiscal year to post the payment verification into. If omitted, the
fiscal year containing the payment date is used.

.PARAMETER PassThru
If specified, returns the updated invoice object. By default the command
produces no output.

.PARAMETER PaymentId
Optional non-empty GUID identifying this payment across retries in this journal.
Generate it once with New-Guid and retain it before calling this command.
Omitted payment inputs on a retry use the saved plan. Different IDs allow
separate payments with identical dates and amounts.

.EXAMPLE
Add-LedgerInvoicePayment -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Date '2024-04-10'

Registers full payment of invoice 1 into the default bank account 1930.

.EXAMPLE
Add-LedgerInvoicePayment -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' -Account '1910'

Registers a partial cash payment of 5 000 kr into account 1910 (Kassa), leaving
the invoice in 'Partial' status.

.EXAMPLE
$paymentId = New-Guid
Add-LedgerInvoicePayment -JournalPath .\Volvo.ledger -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' -PaymentId $paymentId
Add-LedgerInvoicePayment -JournalPath .\Volvo.ledger -InvoiceNumber 1 -PaymentId $paymentId -PassThru

Registers a partial payment once, then safely resumes or retrieves it using
the same saved ID. The second call does not create another payment.
#>
function Add-LedgerInvoicePayment {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$InvoiceNumber,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [decimal]$Amount,

        [Parameter()]
        [string]$Account = '1930',

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [ValidateScript({ if ($_ -eq [guid]::Empty) { throw 'PaymentId must not be an empty GUID.' }; $true })]
        [guid]$PaymentId,

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
            if ($invoice.InvoiceNumber -ne $InvoiceNumber) {
                throw "Invoice $InvoiceNumber has an inconsistent identity."
            }
            $id = if ($PSBoundParameters.ContainsKey('PaymentId')) { $PaymentId } else { [guid]::NewGuid() }
            $operationPath = Join-Path $JournalPath 'invoices' 'payments' "$id.txt"
            $operation = if (Test-Path -LiteralPath $operationPath) { Read-LedgerInvoicePosting -Path $operationPath -Payment }
            $paymentAmount = $Amount
            $paymentDate = $Date
            $paymentAccount = $Account
            $paymentYear = $FiscalYear
            if ($operation) {
                if ($operation.InvoiceNumber -ne $InvoiceNumber -or
                    ($PSBoundParameters.ContainsKey('Amount') -and $Amount -ne $operation.PaymentAmount) -or
                    ($PSBoundParameters.ContainsKey('Date') -and $Date.Date -ne $operation.PaymentDate) -or
                    ($PSBoundParameters.ContainsKey('Account') -and $Account -ne $operation.PaymentAccount) -or
                    ($FiscalYear -and $FiscalYear -ne $operation.FiscalYear)) {
                    throw "PaymentId $id has a saved plan with different payment inputs. Use its original inputs to retry."
                }
                $paymentAmount = $operation.PaymentAmount
                $paymentDate = $operation.PaymentDate
                $paymentAccount = $operation.PaymentAccount
                $paymentYear = $operation.FiscalYear
                $verificationPath = Join-Path $JournalPath $paymentYear ('ver{0:D4}.txt' -f $operation.VerificationNumber)
                if (Get-LedgerRecordedInvoicePayment -Invoice $invoice -Operation $operation) {
                    Assert-LedgerInvoicePaymentVerification -JournalPath $JournalPath -Invoice $invoice -Operation $operation
                    Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $paymentYear
                    if ($PassThru) { Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber }
                    return
                }
                if ((Get-LedgerContentHash -Path $filePath) -ne $operation.InvoiceHash) {
                    throw "Invoice $InvoiceNumber has changed since payment $id was planned. Recovery stopped."
                }
            }
            Assert-LedgerNoPendingInvoicePayment -JournalPath $JournalPath -Invoice $invoice -ExceptPaymentId $id

            if ($invoice.Status -eq 'Draft') {
                throw "Invoice $InvoiceNumber has not been posted. Post it first with Invoke-LedgerInvoicePosting."
            }
            if ($invoice.Status -eq 'Paid') {
                throw "Invoice $InvoiceNumber is already fully paid."
            }
            if ($invoice.Status -notin 'Booked', 'Partial') {
                throw "Invoice $InvoiceNumber is not an open receivable (status '$($invoice.Status)')."
            }

            if (-not $operation -and -not $PSBoundParameters.ContainsKey('Amount')) {
                $paymentAmount = $invoice.RemainingAmount
            }
            if ($paymentAmount -le 0) {
                throw "Payment amount must be greater than zero."
            }
            if ($paymentAmount -gt $invoice.RemainingAmount) {
                throw "Payment amount $paymentAmount exceeds the remaining amount $($invoice.RemainingAmount) on invoice $InvoiceNumber."
            }

            # Resolve the fiscal year from the payment date unless one was supplied.
            if (-not $paymentYear) {
                $paymentYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $paymentDate
                if (-not $paymentYear) {
                    throw "No fiscal year covers the payment date $($paymentDate.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
                }
            }

            $paymentAmount = [decimal]::Parse($paymentAmount.ToString('0.############################',
                    [Globalization.CultureInfo]::InvariantCulture), [Globalization.CultureInfo]::InvariantCulture)
            $rows = @(
                @{ Account = $paymentAccount; Amount = $paymentAmount }
                @{ Account = $invoice.ReceivableAccount; Amount = -$paymentAmount }
            )
            $description = "Betalning kundfaktura $InvoiceNumber"
            $entryParameters = @{
                JournalPath = $JournalPath; FiscalYear = $paymentYear; Date = $paymentDate
                Description = $description; Rows = $rows; OperationId = $id
            }
            $existingVerification = $operation -and (Test-Path -LiteralPath $verificationPath)
            if ($existingVerification) { Assert-LedgerInvoicePaymentVerification -JournalPath $JournalPath -Invoice $invoice -Operation $operation }
            $unsealedNumber = if ($existingVerification) { $operation.VerificationNumber } else { 0 }
            Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $paymentYear -UnsealedVerification $unsealedNumber
            if (-not $existingVerification) {
                if ($paymentAccount -notmatch '^\d+$') { throw "Invalid payment account '$paymentAccount'." }
                $lines = @(Get-LedgerVerificationLines @entryParameters)
                $hash = Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
                if ($operation -and $hash -ne $operation.VerificationHash) { throw "Payment $id no longer produces its saved verification plan. Recovery stopped." }
                if (-not $operation) {
                    $operation = [pscustomobject]@{
                        OperationId = $id; InvoiceNumber = $InvoiceNumber; FiscalYear = $paymentYear
                        VerificationNumber = Get-LedgerNextVerificationNumber -JournalPath $JournalPath -FiscalYear $paymentYear
                        InvoiceHash = Get-LedgerContentHash -Path $filePath; VerificationHash = $hash
                        PaymentDate = $paymentDate.Date; PaymentAmount = $paymentAmount; PaymentAccount = $paymentAccount
                    }
                }
            }

            if (-not $PSCmdlet.ShouldProcess("Invoice $InvoiceNumber", "Register payment of $paymentAmount (PaymentId $id)")) {
                return
            }

            if (-not (Test-Path -LiteralPath $operationPath)) {
                Save-LedgerInvoicePosting -Path $operationPath -Operation $operation -Payment
            }
            try {
                if (-not $existingVerification) {
                    Write-LedgerVerification @entryParameters -ReservedNumber $operation.VerificationNumber -Confirm:$false
                }
                Complete-LedgerInvoicePostingVerification -JournalPath $JournalPath -Operation $operation
                if ((Get-LedgerContentHash -Path $filePath) -ne $operation.InvoiceHash) {
                    throw "Invoice $InvoiceNumber changed during payment. Its saved verification was not removed."
                }

                $invoice.Payments += [PSCustomObject]@{
                    Date               = $operation.PaymentDate
                    Amount             = $paymentAmount
                    VerificationNumber = $operation.VerificationNumber
                    FiscalYear         = $paymentYear
                }

                $paid = ($invoice.Payments | Measure-Object -Property Amount -Sum).Sum
                $invoice.Status = if ([Math]::Round($invoice.Total - $paid, 2) -le 0) { 'Paid' } else { 'Partial' }

                Save-LedgerInvoiceFile -Invoice $invoice
            }
            catch {
                throw [InvalidOperationException]::new(
                    "Could not confirm completion of payment $id for invoice $InvoiceNumber. Keep '$operationPath' and retry Add-LedgerInvoicePayment -JournalPath '$JournalPath' -InvoiceNumber $InvoiceNumber -PaymentId '$id'. $($_.Exception.Message)",
                    $_.Exception)
            }

            if ($PassThru) {
                Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
            }
        }
        finally { Exit-LedgerJournalLock -Lock $journalLock }
    }
}
