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
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$PayslipNumber,

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $payslipDir = Get-LedgerPayslipDirectory -JournalPath $JournalPath
    $filePath = Join-Path $payslipDir (Get-LedgerPayslipFileName -PayslipNumber $PayslipNumber)
    if (-not (Test-Path $filePath)) {
        throw "Payslip $PayslipNumber does not exist."
    }

    $payslip = Read-LedgerPayslipFile -Path $filePath

    if ($payslip.Status -ne 'Draft') {
        throw "Payslip $PayslipNumber is already posted (status '$($payslip.Status)', verification $($payslip.BookedVerification))."
    }

    # Resolve the fiscal year from the pay date unless one was supplied.
    if (-not $FiscalYear) {
        $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $payslip.PayDate
        if (-not $FiscalYear) {
            throw "No fiscal year covers the pay date $($payslip.PayDate.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
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

    $description = "Lön $PayslipNumber - $($payslip.Description)"

    $verification = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
        -Date $payslip.PayDate -Description $description -Rows @($entryRows) -PassThru

    $payslip.Status = 'Booked'
    $payslip.BookedVerification = $verification.VerificationNumber
    $payslip.BookedFiscalYear = $FiscalYear
    Save-LedgerPayslipFile -Payslip $payslip

    if ($PassThru) {
        Get-LedgerPayslip -JournalPath $JournalPath -PayslipNumber $PayslipNumber
    }
}
