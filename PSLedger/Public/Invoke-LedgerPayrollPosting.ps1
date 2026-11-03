<#
.SYNOPSIS
Posts a payslip to the ledger, creating a bookkeeping verification.

.DESCRIPTION
Creates a verification for a Draft payslip: the salary cost account is debited
with the gross salary, the tax liability account (2710 Personalskatt) is credited
with the withheld tax, the net pay account (1930 Företagskonto) is credited with
the net pay, and the employer contribution is booked as both a cost (7510
Arbetsgivaravgifter) and a liability (2730 Arbetsgivaravgift skuld). The fiscal
year is resolved from the pay date unless one is supplied explicitly.

For a gross salary of 30 000 kr, 9 000 kr tax and 31.42% employer contribution the
verification is:
  7210 Löner                     +30000
  2710 Personalskatt              -9000
  1930 Företagskonto             -21000
  7510 Arbetsgivaravgifter        +9426
  2730 Arbetsgivaravgift skuld    -9426

After posting, the payslip status becomes 'Booked' and the verification number and
fiscal year are recorded on the payslip. The operation refuses to run twice for
the same payslip (an already-posted payslip throws).

Posting is safely resumable. Before the verification is written, an immutable
plan in payslips/posting/ reserves the verification number. If the command is
interrupted, run it again for the same payslip: it completes the saved posting
without creating a second verification. A saved verification can be completed
even after the fiscal year is closed, but a missing one is never created there.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER PayslipNumber
The number of the payslip to post.

.PARAMETER FiscalYear
Optional. The fiscal year to post the verification into. If omitted, the fiscal
year containing the pay date is used.

.PARAMETER PassThru
If specified, returns the updated payslip object. By default the command produces
no output.

.EXAMPLE
Invoke-LedgerPayrollPosting -JournalPath .\MinFirma.ledger -PayslipNumber 1

Posts payslip 1, creating the salary verification.

.EXAMPLE
Get-LedgerPayslip -Status Draft | ForEach-Object { Invoke-LedgerPayrollPosting -PayslipNumber $_.PayslipNumber }

Posts every draft payslip in the current journal.
#>
function Invoke-LedgerPayrollPosting {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$PayslipNumber,

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

            $payslipDir = Get-LedgerPayslipDirectory -JournalPath $JournalPath
            $filePath = Join-Path $payslipDir (Get-LedgerPayslipFileName -PayslipNumber $PayslipNumber)
            if (-not (Test-Path $filePath)) {
                throw "Payslip $PayslipNumber does not exist."
            }

            $payslip = Read-LedgerPayslipFile -Path $filePath

            if ($payslip.Status -ne 'Draft') {
                throw "Payslip $PayslipNumber is already posted (status '$($payslip.Status)', verification $($payslip.BookedVerification))."
            }
            if ($payslip.PayslipNumber -ne $PayslipNumber -or $payslip.BookedVerification -or $payslip.BookedFiscalYear) {
                throw "Draft payslip $PayslipNumber has inconsistent identity or posting references. Inspect it before posting."
            }

            $operationPath = Get-LedgerPayslipPostingPath -JournalPath $JournalPath -PayslipNumber $PayslipNumber
            $operation = if (Test-Path -LiteralPath $operationPath) { Read-LedgerPayslipPosting -Path $operationPath } else { $null }
            $payslipHash = Get-LedgerContentHash -Path $filePath
            $postingYear = $FiscalYear
            if ($operation) {
                if ($payslipHash -ne $operation.PayslipHash) {
                    throw "Payslip $PayslipNumber has changed since its posting plan was saved. Recovery stopped without modifying the payslip or verification."
                }
                if ($postingYear -and $postingYear -ne $operation.FiscalYear) {
                    throw "Payslip $PayslipNumber has a posting plan for $($operation.FiscalYear), not $postingYear."
                }
                $postingYear = $operation.FiscalYear
            }

            # Resolve the fiscal year from the pay date unless one was supplied.
            if (-not $postingYear) {
                $postingYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $payslip.PayDate
                if (-not $postingYear) {
                    throw "No fiscal year covers the pay date $($payslip.PayDate.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
                }
            }

            # Aggregate amounts per account so the verification is compact.
            $accountSums = [ordered]@{}
            $addAmount = {
                param($account, $amount)
                if ($accountSums.Contains($account)) { $accountSums[$account] += $amount }
                else { $accountSums[$account] = $amount }
            }

            # Salary: debit cost, credit tax liability, credit net pay to bank.
            & $addAmount $payslip.SalaryAccount $payslip.GrossSalary
            if ($payslip.TaxAmount -ne 0) {
                & $addAmount $payslip.TaxLiabilityAccount (-$payslip.TaxAmount)
            }
            & $addAmount $payslip.NetPayAccount (-$payslip.NetPay)

            # Employer contribution: debit cost, credit liability.
            if ($payslip.EmployerContribution -ne 0) {
                & $addAmount $payslip.EmployerContributionAccount $payslip.EmployerContribution
                & $addAmount $payslip.EmployerContributionLiabilityAccount (-$payslip.EmployerContribution)
            }

            $entryRows = foreach ($account in $accountSums.Keys) {
                @{ Account = $account; Amount = [Math]::Round([decimal]$accountSums[$account], 2) }
            }

            $operationId = if ($operation) { $operation.OperationId } else { [guid]::NewGuid() }
            $entryParameters = @{
                JournalPath = $JournalPath; FiscalYear = $postingYear; Date = $payslip.PayDate
                Description = "Lön $PayslipNumber - $($payslip.Description)"; Rows = @($entryRows); OperationId = $operationId
            }
            $existingVerification = $false
            if ($operation) {
                $verificationPath = Join-Path $JournalPath $postingYear ('ver{0:D4}.txt' -f $operation.VerificationNumber)
                $existingVerification = Test-Path -LiteralPath $verificationPath
                if ($existingVerification) {
                    Assert-LedgerInvoicePostingVerification -Path $verificationPath -Operation $operation -Label 'payslip posting'
                }
            }
            $unsealedNumber = if ($existingVerification) { $operation.VerificationNumber } else { 0 }
            Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $postingYear `
                -UnsealedVerification $unsealedNumber -Label 'Payslip posting'
            if (-not $existingVerification) {
                $lines = @(Get-LedgerVerificationLines @entryParameters)
                $verificationHash = Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
                if ($operation -and $verificationHash -ne $operation.VerificationHash) {
                    throw "Payslip $PayslipNumber no longer produces the saved verification plan. Recovery stopped."
                }
                if (-not $operation) {
                    $operation = [pscustomobject]@{
                        OperationId = $operationId; PayslipNumber = $PayslipNumber; FiscalYear = $postingYear
                        VerificationNumber = Get-LedgerNextVerificationNumber -JournalPath $JournalPath -FiscalYear $postingYear
                        PayslipHash = $payslipHash; VerificationHash = $verificationHash
                    }
                }
            }

            if (-not $PSCmdlet.ShouldProcess("Payslip $PayslipNumber", "Post to fiscal year $postingYear")) {
                return
            }

            if (-not (Test-Path -LiteralPath $operationPath)) {
                Save-LedgerPayslipPosting -Path $operationPath -Operation $operation
            }
            try {
                if (-not $existingVerification) {
                    Write-LedgerVerification @entryParameters -ReservedNumber $operation.VerificationNumber -Confirm:$false
                }
                Complete-LedgerInvoicePostingVerification -JournalPath $JournalPath -Operation $operation -Label 'payslip posting'
                if ((Get-LedgerContentHash -Path $filePath) -ne $operation.PayslipHash) {
                    throw "Payslip $PayslipNumber changed during posting. Its saved verification was not removed."
                }

                $payslip.Status = 'Booked'
                $payslip.BookedVerification = $operation.VerificationNumber
                $payslip.BookedFiscalYear = $postingYear
                Save-LedgerPayslipFile -Payslip $payslip
            }
            catch {
                throw [InvalidOperationException]::new(
                    "Could not confirm completion of payslip $PayslipNumber posting. Keep '$operationPath' and its reserved verification; rerun Invoke-LedgerPayrollPosting -JournalPath '$JournalPath' -PayslipNumber $PayslipNumber to recover safely. $($_.Exception.Message)",
                    $_.Exception)
            }

            if ($PassThru) {
                Get-LedgerPayslip -JournalPath $JournalPath -PayslipNumber $PayslipNumber
            }
        }
        finally { Exit-LedgerJournalLock -Lock $journalLock }
    }
}