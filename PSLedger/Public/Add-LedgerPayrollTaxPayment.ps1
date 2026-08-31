<#
.SYNOPSIS
Books the payment of withheld employee tax and employer contributions to the tax
account (skattekontot).

.DESCRIPTION
Creates a verification that settles the payroll liabilities built up when payslips
are posted: the tax liability account (2710 Personalskatt) and the employer
contribution liability account (2730 Arbetsgivaravgift skuld) are debited, and the
payment account (1930 Företagskonto by default) is credited with the total.

By default the amounts are the outstanding balances of the two liability accounts
in the fiscal year, so the accounts are settled to zero and the payroll
liabilities reconcile against the ledger. Supply -TaxAmount and/or
-EmployerContributionAmount to pay specific amounts instead.

The fiscal year is resolved from the payment date unless one is supplied
explicitly.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Date
The date of the payment.

.PARAMETER FiscalYear
Optional. The fiscal year to post into and read the outstanding balances from. If
omitted, the fiscal year containing the payment date is used.

.PARAMETER TaxAmount
Optional. The amount of withheld tax to pay. Defaults to the outstanding balance
of the tax liability account.

.PARAMETER EmployerContributionAmount
Optional. The amount of employer contributions to pay. Defaults to the outstanding
balance of the employer contribution liability account.

.PARAMETER TaxLiabilityAccount
The tax liability account to debit. Defaults to '2710' (Personalskatt).

.PARAMETER EmployerContributionLiabilityAccount
The employer contribution liability account to debit. Defaults to '2730'
(Arbetsgivaravgift skuld).

.PARAMETER Account
The account the payment is credited to. Defaults to '1930' (Företagskonto).

.PARAMETER Description
Description for the verification. Defaults to 'Betalning av personalskatt och
arbetsgivaravgifter'.

.EXAMPLE
Add-LedgerPayrollTaxPayment -JournalPath .\MinFirma.ledger -Date '2024-04-12'

Pays the full outstanding withheld tax and employer contributions on 2024-04-12,
settling accounts 2710 and 2730 to zero.

.EXAMPLE
Add-LedgerPayrollTaxPayment -Date '2024-04-12' -TaxAmount 9000 -EmployerContributionAmount 9426

Pays specific amounts of withheld tax and employer contributions.
#>
function Add-LedgerPayrollTaxPayment {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [datetime]$Date,

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [decimal]$TaxAmount,

        [Parameter()]
        [decimal]$EmployerContributionAmount,

        [Parameter()]
        [string]$TaxLiabilityAccount = '2710',

        [Parameter()]
        [string]$EmployerContributionLiabilityAccount = '2730',

        [Parameter()]
        [string]$Account = '1930',

        [Parameter()]
        [string]$Description = 'Betalning av personalskatt och arbetsgivaravgifter'
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    # Resolve the fiscal year from the payment date unless one was supplied.
    if (-not $FiscalYear) {
        $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $Date
        if (-not $FiscalYear) {
            throw "No fiscal year covers the payment date $($Date.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
        }
    }

    # Read the outstanding liability balances for defaults. A liability that is
    # owed has a negative (credit) balance, so the amount owed is its negation.
    $balances = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)
    $balanceOf = {
        param($account)
        $row = $balances | Where-Object { $_.AccountNumber -eq $account }
        if ($row) { [decimal]$row.Balance } else { [decimal]0 }
    }

    if ($PSBoundParameters.ContainsKey('TaxAmount')) {
        $tax = [Math]::Round([decimal]$TaxAmount, 2)
    }
    else {
        $owed = -(& $balanceOf $TaxLiabilityAccount)
        $tax = if ($owed -gt 0) { [Math]::Round($owed, 2) } else { [decimal]0 }
    }

    if ($PSBoundParameters.ContainsKey('EmployerContributionAmount')) {
        $employer = [Math]::Round([decimal]$EmployerContributionAmount, 2)
    }
    else {
        $owed = -(& $balanceOf $EmployerContributionLiabilityAccount)
        $employer = if ($owed -gt 0) { [Math]::Round($owed, 2) } else { [decimal]0 }
    }

    if ($tax -lt 0) { throw "TaxAmount must not be negative. Got: $tax" }
    if ($employer -lt 0) { throw "EmployerContributionAmount must not be negative. Got: $employer" }

    $total = [Math]::Round($tax + $employer, 2)
    if ($total -le 0) {
        throw "Nothing to pay: the outstanding tax and employer contributions are zero. Specify -TaxAmount and/or -EmployerContributionAmount to force a payment."
    }

    if (-not $PSCmdlet.ShouldProcess($FiscalYear, "Pay payroll taxes of $total")) {
        return
    }

    # Debit the liabilities, credit the payment account.
    $entryRows = @()
    if ($tax -ne 0) { $entryRows += @{ Account = $TaxLiabilityAccount; Amount = $tax } }
    if ($employer -ne 0) { $entryRows += @{ Account = $EmployerContributionLiabilityAccount; Amount = $employer } }
    $entryRows += @{ Account = $Account; Amount = -$total }

    $verification = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
        -Date $Date -Description $Description -Rows @($entryRows) -PassThru

    [PSCustomObject]@{
        FiscalYear                 = $FiscalYear
        Date                       = $Date
        Description                = $Description
        TaxAmount                  = $tax
        EmployerContributionAmount = $employer
        Total                      = $total
        Account                    = $Account
        VerificationNumber         = $verification.VerificationNumber
    }
}
