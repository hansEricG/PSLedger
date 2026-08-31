<#
.SYNOPSIS
Adds an employee to the journal's employee register.

.DESCRIPTION
Adds an employee entry to the journal's employees.txt file. Employees are the
recipients of the payslips recorded with New-LedgerPayslip. Each employee has a
unique employee number and a name, plus an optional personal number
(personnummer), the default salary cost account their pay is booked to and a
default preliminary tax rate used when a payslip does not specify the tax.

The employees.txt file is tab-separated with the columns:
EmployeeNumber, Name, PersonalNumber, SalaryAccount, TaxRate.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER EmployeeNumber
A unique identifier for the employee (e.g. '1', 'A001').

.PARAMETER Name
The employee's name.

.PARAMETER PersonalNumber
Optional Swedish personal number (e.g. '19850101-1234').

.PARAMETER SalaryAccount
The salary cost account the employee's gross pay is booked to. Defaults to '7210'
(Löner till kollektivanställda). Use '7010' for salaried staff (tjänstemän).

.PARAMETER TaxRate
The default preliminary tax rate as a decimal (e.g. 0.30 for 30%) used when a
payslip does not specify the tax. Defaults to 0.

.EXAMPLE
Add-LedgerEmployee -JournalPath .\MinFirma.ledger -EmployeeNumber '1' -Name 'Anna Andersson'

Adds an employee with the default salary account and no default tax rate.

.EXAMPLE
Add-LedgerEmployee -JournalPath .\MinFirma.ledger -EmployeeNumber '2' -Name 'Bengt Bengtsson' -PersonalNumber '19850101-1234' -SalaryAccount '7010' -TaxRate 0.30

Adds a salaried employee whose pay is booked to 7010 with a 30% default tax rate.
#>
function Add-LedgerEmployee {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$EmployeeNumber,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$PersonalNumber,

        [Parameter()]
        [string]$SalaryAccount = '7210',

        [Parameter()]
        [ValidateRange(0, 1)]
        [decimal]$TaxRate = 0
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    if ($EmployeeNumber -match "`t") {
        throw "EmployeeNumber must not contain a tab character."
    }

    $EmployeeFile = Join-Path $JournalPath 'employees.txt'

    if (Test-Path $EmployeeFile) {
        foreach ($Line in (Get-Content $EmployeeFile -Encoding UTF8)) {
            if ($Line -match "^$([regex]::Escape($EmployeeNumber))`t") {
                throw "Employee '$EmployeeNumber' already exists."
            }
        }
    }

    $rate = Format-LedgerInvoiceAmount -Value $TaxRate
    if ($PSCmdlet.ShouldProcess($EmployeeNumber, 'Add employee')) {
        "$EmployeeNumber`t$Name`t$PersonalNumber`t$SalaryAccount`t$rate" |
            Add-Content -Path $EmployeeFile -Encoding UTF8
    }
}
