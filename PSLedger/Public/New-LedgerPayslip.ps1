<#
.SYNOPSIS
Creates a new payslip (lönespecifikation) in the journal.

.DESCRIPTION
Creates a sequentially numbered payslip file (pay0001.txt, pay0002.txt, etc.) in
the journal's 'payslips/' directory. A payslip records an employee's gross salary,
the preliminary tax withheld and the employer's social security contributions for
a pay period, but is not yet posted to the ledger — use Invoke-LedgerPayrollPosting
to create the bookkeeping verification.

The preliminary tax is resolved in this order: an explicit -TaxAmount, otherwise
-TaxRate times the gross salary, otherwise the employee's default tax rate. The
net pay is the gross salary minus the tax. The employer contribution is the gross
salary times -EmployerContributionRate (default 0.3142, the standard Swedish
arbetsgivaravgift).

Payslips live at the journal level (not inside a fiscal year) because a pay period
may be posted in a later fiscal year than the one it was created in.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER EmployeeNumber
The number of the employee being paid. Must exist in the employee register
(see Add-LedgerEmployee).

.PARAMETER GrossSalary
The gross (pre-tax) cash salary for the period. Must be greater than zero.

.PARAMETER PayDate
The pay (disbursement) date. Defaults to today.

.PARAMETER PeriodStart
Optional. The first day of the pay period.

.PARAMETER PeriodEnd
Optional. The last day of the pay period.

.PARAMETER Description
A description of the payslip. Defaults to 'Lön'.

.PARAMETER TaxAmount
The preliminary tax to withhold, as an amount. Mutually exclusive with -TaxRate.

.PARAMETER TaxRate
The preliminary tax to withhold, as a decimal rate of the gross salary (e.g. 0.30
for 30%). Mutually exclusive with -TaxAmount. If neither is given, the employee's
default tax rate is used.

.PARAMETER EmployerContributionRate
The employer social security contribution rate as a decimal. Defaults to 0.3142.

.PARAMETER SalaryAccount
The salary cost account the gross pay is debited to. Defaults to the employee's
SalaryAccount (7210 unless changed).

.PARAMETER TaxLiabilityAccount
The account the withheld tax is credited to. Defaults to '2710' (Personalskatt).

.PARAMETER NetPayAccount
The account the net pay is credited to (disbursement). Defaults to '1930'
(Företagskonto).

.PARAMETER EmployerContributionAccount
The cost account the employer contribution is debited to. Defaults to '7510'
(Arbetsgivaravgifter).

.PARAMETER EmployerContributionLiabilityAccount
The account the employer contribution is credited to. Defaults to '2730'
(Arbetsgivaravgift skuld).

.PARAMETER PassThru
If specified, returns the created payslip object. By default the command produces
no output.

.EXAMPLE
New-LedgerPayslip -JournalPath .\MinFirma.ledger -EmployeeNumber '1' -GrossSalary 30000 -TaxRate 0.30 -PayDate '2024-03-25'

Creates a payslip for 30 000 kr gross with 30% preliminary tax.

.EXAMPLE
New-LedgerPayslip -EmployeeNumber '2' -GrossSalary 42000 -TaxAmount 12600 -PeriodStart '2024-03-01' -PeriodEnd '2024-03-31' -Description 'Lön mars 2024' -PassThru

Creates a payslip with an explicit tax amount and pay period, and returns it.
#>
function New-LedgerPayslip {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$EmployeeNumber,

        [Parameter(Mandatory)]
        [decimal]$GrossSalary,

        [Parameter()]
        [datetime]$PayDate = (Get-Date).Date,

        [Parameter()]
        [datetime]$PeriodStart,

        [Parameter()]
        [datetime]$PeriodEnd,

        [Parameter()]
        [string]$Description = 'Lön',

        [Parameter()]
        [decimal]$TaxAmount,

        [Parameter()]
        [ValidateRange(0, 1)]
        [decimal]$TaxRate,

        [Parameter()]
        [ValidateRange(0, 1)]
        [decimal]$EmployerContributionRate = 0.3142,

        [Parameter()]
        [string]$SalaryAccount,

        [Parameter()]
        [string]$TaxLiabilityAccount = '2710',

        [Parameter()]
        [string]$NetPayAccount = '1930',

        [Parameter()]
        [string]$EmployerContributionAccount = '7510',

        [Parameter()]
        [string]$EmployerContributionLiabilityAccount = '2730',

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    # Validate the employee exists.
    $employee = Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber $EmployeeNumber
    if (-not $employee) {
        throw "Employee '$EmployeeNumber' does not exist. Add it with Add-LedgerEmployee first."
    }

    if ($GrossSalary -le 0) {
        throw "GrossSalary must be greater than zero. Got: $GrossSalary"
    }

    # Resolve the preliminary tax.
    if ($PSBoundParameters.ContainsKey('TaxAmount') -and $PSBoundParameters.ContainsKey('TaxRate')) {
        throw "Specify either -TaxAmount or -TaxRate, not both."
    }
    if ($PSBoundParameters.ContainsKey('TaxAmount')) {
        $tax = [Math]::Round([decimal]$TaxAmount, 2)
    }
    elseif ($PSBoundParameters.ContainsKey('TaxRate')) {
        $tax = [Math]::Round($GrossSalary * $TaxRate, 2)
    }
    else {
        $tax = [Math]::Round($GrossSalary * $employee.TaxRate, 2)
    }

    if ($tax -lt 0) {
        throw "Tax amount must not be negative. Got: $tax"
    }
    if ($tax -gt $GrossSalary) {
        throw "Tax amount ($tax) must not exceed the gross salary ($GrossSalary)."
    }

    # Default the salary account to the employee's account.
    if (-not $PSBoundParameters.ContainsKey('SalaryAccount')) {
        $SalaryAccount = $employee.SalaryAccount
    }

    $payslipDir = Get-LedgerPayslipDirectory -JournalPath $JournalPath -Create

    # Determine the next payslip number by scanning existing files.
    $existing = Get-ChildItem -Path $payslipDir -Filter 'pay*.txt' -File -ErrorAction SilentlyContinue
    if ($existing) {
        $maxNum = $existing |
            ForEach-Object { if ($_.BaseName -match '^pay(\d+)$') { [int]$Matches[1] } } |
            Measure-Object -Maximum |
            Select-Object -ExpandProperty Maximum
        $nextNum = $maxNum + 1
    }
    else {
        $nextNum = 1
    }

    $filePath = Join-Path $payslipDir (Get-LedgerPayslipFileName -PayslipNumber $nextNum)

    $payslip = [PSCustomObject]@{
        PayslipNumber                        = $nextNum
        EmployeeNumber                       = $EmployeeNumber
        PayDate                              = $PayDate
        PeriodStart                          = if ($PSBoundParameters.ContainsKey('PeriodStart')) { $PeriodStart } else { $null }
        PeriodEnd                            = if ($PSBoundParameters.ContainsKey('PeriodEnd')) { $PeriodEnd } else { $null }
        Description                          = $Description
        Status                               = 'Draft'
        GrossSalary                          = [Math]::Round($GrossSalary, 2)
        TaxAmount                            = $tax
        EmployerContributionRate             = $EmployerContributionRate
        SalaryAccount                        = $SalaryAccount
        TaxLiabilityAccount                  = $TaxLiabilityAccount
        NetPayAccount                        = $NetPayAccount
        EmployerContributionAccount          = $EmployerContributionAccount
        EmployerContributionLiabilityAccount = $EmployerContributionLiabilityAccount
        BookedVerification                   = $null
        BookedFiscalYear                     = ''
        FilePath                             = $filePath
    }

    if ($PSCmdlet.ShouldProcess("Employee $EmployeeNumber", "Create payslip $nextNum")) {
        Save-LedgerPayslipFile -Payslip $payslip

        if ($PassThru) {
            Get-LedgerPayslip -JournalPath $JournalPath -PayslipNumber $nextNum
        }
    }
}
