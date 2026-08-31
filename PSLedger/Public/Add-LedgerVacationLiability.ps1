<#
.SYNOPSIS
Books the change in the vacation pay liability (semesterlöneskuld).

.DESCRIPTION
Creates a verification that records the change in the accrued vacation pay
liability for a period. When the liability increases the change account (7290
Förändring av semesterlöneskuld) is debited and the liability account (2920
Upplupna semesterlöner) is credited; when it decreases the entry is reversed.

Supply -Amount as the change in the liability: a positive amount increases the
liability (a cost), a negative amount decreases it (releases a cost). To book to
a target closing balance instead, use -TargetBalance and the change is derived
from the current balance of the liability account in the fiscal year.

With -IncludeEmployerContributions the estimated employer social security
contributions on the vacation pay liability are booked as well: the contribution
cost account (7519 Sociala avgifter för semester- och löneskulder, defaulting to
7510) is debited and the contribution liability account (2940 Upplupna
arbetsgivaravgifter) is credited with the change times the contribution rate.

The fiscal year is resolved from the date unless one is supplied explicitly.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Date
The date of the entry (typically a period or year end).

.PARAMETER Amount
The change in the vacation pay liability. Positive increases the liability
(a cost); negative decreases it. Mutually exclusive with -TargetBalance.

.PARAMETER TargetBalance
The desired closing balance of the vacation pay liability account. The change is
computed as TargetBalance minus the account's current balance. Mutually exclusive
with -Amount.

.PARAMETER FiscalYear
Optional. The fiscal year to post into. If omitted, the fiscal year containing
the date is used.

.PARAMETER IncludeEmployerContributions
Also book the estimated employer contributions on the change in the vacation pay
liability.

.PARAMETER EmployerContributionRate
The employer contribution rate used with -IncludeEmployerContributions. Defaults
to 0.3142 (31.42 %).

.PARAMETER LiabilityAccount
The vacation pay liability account to credit (increase). Defaults to '2920'
(Upplupna semesterlöner).

.PARAMETER ChangeAccount
The cost account for the change in the liability. Defaults to '7290' (Förändring
av semesterlöneskuld).

.PARAMETER EmployerContributionAccount
The cost account for employer contributions on vacation pay. Defaults to '7510'
(Arbetsgivaravgifter). Use '7519' (Sociala avgifter för semester- och
löneskulder) if it exists in your chart of accounts.

.PARAMETER EmployerContributionLiabilityAccount
The liability account for employer contributions on vacation pay. Defaults to
'2940' (Upplupna arbetsgivaravgifter).

.PARAMETER Description
Description for the verification. Defaults to 'Förändring av semesterlöneskuld'.

.EXAMPLE
Add-LedgerVacationLiability -JournalPath .\MinFirma.ledger -Date '2024-12-31' -Amount 45000

Books an increase of the vacation pay liability of 45 000 kr: debit 7290,
credit 2920.

.EXAMPLE
Add-LedgerVacationLiability -Date '2024-12-31' -TargetBalance 120000 -IncludeEmployerContributions

Adjusts the vacation pay liability so account 2920 closes at 120 000 kr and also
books the employer contributions on the change to 7519/2940.
#>
function Add-LedgerVacationLiability {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Amount')]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [datetime]$Date,

        [Parameter(Mandatory, ParameterSetName = 'Amount')]
        [decimal]$Amount,

        [Parameter(Mandatory, ParameterSetName = 'TargetBalance')]
        [decimal]$TargetBalance,

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [switch]$IncludeEmployerContributions,

        [Parameter()]
        [ValidateRange(0, 1)]
        [decimal]$EmployerContributionRate = 0.3142,

        [Parameter()]
        [string]$LiabilityAccount = '2920',

        [Parameter()]
        [string]$ChangeAccount = '7290',

        [Parameter()]
        [string]$EmployerContributionAccount = '7510',

        [Parameter()]
        [string]$EmployerContributionLiabilityAccount = '2940',

        [Parameter()]
        [string]$Description = 'Förändring av semesterlöneskuld'
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    # Resolve the fiscal year from the date unless one was supplied.
    if (-not $FiscalYear) {
        $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $Date
        if (-not $FiscalYear) {
            throw "No fiscal year covers the date $($Date.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
        }
    }

    # Determine the change in the liability. For -TargetBalance the change is the
    # difference from the account's current (credit, i.e. negative) balance
    # expressed as a positive liability.
    if ($PSCmdlet.ParameterSetName -eq 'TargetBalance') {
        $balances = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)
        $row = $balances | Where-Object { $_.AccountNumber -eq $LiabilityAccount }
        $currentLiability = if ($row) { -[decimal]$row.Balance } else { [decimal]0 }
        $change = [Math]::Round([decimal]$TargetBalance - $currentLiability, 2)
    }
    else {
        $change = [Math]::Round([decimal]$Amount, 2)
    }

    if ($change -eq 0) {
        throw "Nothing to book: the change in the vacation pay liability is zero."
    }

    $employerChange = if ($IncludeEmployerContributions) {
        [Math]::Round($change * $EmployerContributionRate, 2)
    }
    else {
        [decimal]0
    }

    if (-not $PSCmdlet.ShouldProcess($FiscalYear, "Book vacation pay liability change of $change")) {
        return
    }

    # A positive change increases the liability: debit the change (cost) account
    # and credit the liability. A negative change reverses both signs.
    $entryRows = @(
        @{ Account = $ChangeAccount; Amount = $change }
        @{ Account = $LiabilityAccount; Amount = -$change }
    )
    if ($employerChange -ne 0) {
        $entryRows += @{ Account = $EmployerContributionAccount; Amount = $employerChange }
        $entryRows += @{ Account = $EmployerContributionLiabilityAccount; Amount = -$employerChange }
    }

    $verification = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
        -Date $Date -Description $Description -Rows @($entryRows) -PassThru

    [PSCustomObject]@{
        FiscalYear                 = $FiscalYear
        Date                       = $Date
        Description                = $Description
        Change                     = $change
        LiabilityAccount           = $LiabilityAccount
        ChangeAccount              = $ChangeAccount
        EmployerContribution       = $employerChange
        VerificationNumber         = $verification.VerificationNumber
    }
}
