<#
.SYNOPSIS
Lists employees in the journal's employee register.

.DESCRIPTION
Reads employees.txt and returns a PSCustomObject for each employee with the
EmployeeNumber, Name, PersonalNumber, SalaryAccount and TaxRate properties.
Optionally filter to a single employee by number.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER EmployeeNumber
Optional. If specified, returns only the employee with this number.

.EXAMPLE
Get-LedgerEmployee -JournalPath .\MinFirma.ledger

Returns all employees.

.EXAMPLE
Get-LedgerEmployee -JournalPath .\MinFirma.ledger -EmployeeNumber '1'

Returns only employee number 1.
#>
function Get-LedgerEmployee {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$EmployeeNumber
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $EmployeeFile = Join-Path $JournalPath 'employees.txt'
    if (-not (Test-Path $EmployeeFile)) { return }

    $employees = foreach ($Line in (Get-Content $EmployeeFile -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($Line)) { continue }
        $parts = $Line -split "`t"
        [PSCustomObject]@{
            EmployeeNumber = $parts[0]
            Name           = if ($parts.Count -ge 2) { $parts[1] } else { '' }
            PersonalNumber = if ($parts.Count -ge 3) { $parts[2] } else { '' }
            SalaryAccount  = if ($parts.Count -ge 4 -and $parts[3]) { $parts[3] } else { '7210' }
            TaxRate        = if ($parts.Count -ge 5 -and $parts[4]) { ConvertFrom-LedgerInvoiceAmount -Text $parts[4] } else { [decimal]0 }
        }
    }

    if ($PSBoundParameters.ContainsKey('EmployeeNumber')) {
        $employees | Where-Object { $_.EmployeeNumber -eq $EmployeeNumber }
    }
    else {
        $employees
    }
}
