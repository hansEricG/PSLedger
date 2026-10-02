<#
.SYNOPSIS
Updates an employee in the journal's employee register.

.DESCRIPTION
Updates the Name, PersonalNumber, SalaryAccount and/or TaxRate of an existing
employee in employees.txt. Only the fields you supply are changed; the others
keep their current values. The employee must already exist.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER EmployeeNumber
The number of the employee to update.

.PARAMETER Name
The new employee name.

.PARAMETER PersonalNumber
The new personal number. Pass an empty string to clear it.

.PARAMETER SalaryAccount
The new default salary cost account.

.PARAMETER TaxRate
The new default preliminary tax rate as a decimal (e.g. 0.30 for 30%).

.PARAMETER PassThru
If specified, returns the created/updated employee. By default the command
produces no output.

.EXAMPLE
Set-LedgerEmployee -JournalPath .\MinFirma.ledger -EmployeeNumber '1' -TaxRate 0.32

Updates only the default tax rate for employee 1.

.EXAMPLE
Set-LedgerEmployee -JournalPath .\MinFirma.ledger -EmployeeNumber '1' -Name 'Anna Andersson-Ek' -SalaryAccount '7010'

Renames employee 1 and books future pay to the salaried-staff account 7010.
#>
function Set-LedgerEmployee {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$EmployeeNumber,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$PersonalNumber,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SalaryAccount,

        [Parameter()]
        [ValidateRange(0, 1)]
        [decimal]$TaxRate,

        [Parameter()]
        [switch]$PassThru
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

        if (-not (Test-Path $JournalPath -PathType Container)) {
            throw "Journal not found: $JournalPath"
        }

        $EmployeeFile = Join-Path $JournalPath 'employees.txt'
        if (-not (Test-Path $EmployeeFile)) {
            throw "Employee '$EmployeeNumber' does not exist."
        }

        $updateName = $PSBoundParameters.ContainsKey('Name')
        $updatePnr = $PSBoundParameters.ContainsKey('PersonalNumber')
        $updateAccount = $PSBoundParameters.ContainsKey('SalaryAccount')
        $updateTax = $PSBoundParameters.ContainsKey('TaxRate')

        if (-not ($updateName -or $updatePnr -or $updateAccount -or $updateTax)) {
            throw "Nothing to update. Specify -Name, -PersonalNumber, -SalaryAccount and/or -TaxRate."
        }

        $lines = @(Get-Content $EmployeeFile -Encoding UTF8)
        $found = $false
        $newLines = foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split "`t"
            if ($parts[0] -eq $EmployeeNumber) {
                $found = $true
                $curName = if ($parts.Count -ge 2) { $parts[1] } else { '' }
                $curPnr = if ($parts.Count -ge 3) { $parts[2] } else { '' }
                $curAccount = if ($parts.Count -ge 4) { $parts[3] } else { '7210' }
                $curTax = if ($parts.Count -ge 5) { $parts[4] } else { '0' }

                if ($updateName) { $curName = ConvertTo-LedgerTextField $Name }
                if ($updatePnr) { $curPnr = ConvertTo-LedgerTextField $PersonalNumber }
                if ($updateAccount) { Assert-LedgerKeyField -Name 'SalaryAccount' -Value $SalaryAccount; $curAccount = $SalaryAccount }
                if ($updateTax) { $curTax = Format-LedgerInvoiceAmount -Value $TaxRate }

                "$EmployeeNumber`t$curName`t$curPnr`t$curAccount`t$curTax"
            }
            else {
                $line
            }
        }

        if (-not $found) {
            throw "Employee '$EmployeeNumber' does not exist."
        }

        if ($PSCmdlet.ShouldProcess($EmployeeNumber, "Update employee")) {
            Set-LedgerFileContent -Path $EmployeeFile -Value $newLines
            if ($PassThru) {
                Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber $EmployeeNumber
            }
        }
    }
}
