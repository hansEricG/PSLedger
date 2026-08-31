<#
.SYNOPSIS
Lists payslips in the journal.

.DESCRIPTION
Reads payslips from the journal's 'payslips/' directory and returns an object for
each with its metadata and computed amounts (NetPay, EmployerContribution,
TotalEmployerCost). The employee's name is resolved from the employee register and
added as EmployeeName.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER PayslipNumber
Optional. If specified, returns only the payslip with this number.

.PARAMETER Status
Optional. If specified, returns only payslips with this status (Draft or Booked).

.PARAMETER EmployeeNumber
Optional. If specified, returns only payslips for this employee.

.EXAMPLE
Get-LedgerPayslip -JournalPath .\MinFirma.ledger

Lists all payslips.

.EXAMPLE
Get-LedgerPayslip -JournalPath .\MinFirma.ledger -Status Draft

Lists all unposted payslips.

.EXAMPLE
Get-LedgerPayslip -JournalPath .\MinFirma.ledger -PayslipNumber 1

Returns the details of payslip number 1.
#>
function Get-LedgerPayslip {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [int]$PayslipNumber,

        [Parameter()]
        [ValidateSet('Draft', 'Booked')]
        [string]$Status,

        [Parameter()]
        [string]$EmployeeNumber
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $payslipDir = Get-LedgerPayslipDirectory -JournalPath $JournalPath
    if (-not (Test-Path $payslipDir)) { return }

    $files = if ($PSBoundParameters.ContainsKey('PayslipNumber')) {
        $filePath = Join-Path $payslipDir (Get-LedgerPayslipFileName -PayslipNumber $PayslipNumber)
        if (Test-Path $filePath) { @(Get-Item $filePath) } else { @() }
    }
    else {
        @(Get-ChildItem -Path $payslipDir -Filter 'pay*.txt' -File |
            Sort-Object { [int]($_.BaseName -replace '^pay', '') })
    }

    # Build a lookup of employee numbers to names once.
    $employeeNames = @{}
    foreach ($e in @(Get-LedgerEmployee -JournalPath $JournalPath)) {
        $employeeNames[$e.EmployeeNumber] = $e.Name
    }

    foreach ($file in $files) {
        $payslip = Read-LedgerPayslipFile -Path $file.FullName

        if ($PSBoundParameters.ContainsKey('Status') -and $payslip.Status -ne $Status) { continue }
        if ($PSBoundParameters.ContainsKey('EmployeeNumber') -and $payslip.EmployeeNumber -ne $EmployeeNumber) { continue }

        $name = if ($employeeNames.ContainsKey($payslip.EmployeeNumber)) { $employeeNames[$payslip.EmployeeNumber] } else { '' }
        $payslip | Add-Member -NotePropertyName 'EmployeeName' -NotePropertyValue $name -PassThru
    }
}
