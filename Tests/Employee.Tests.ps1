BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force

    function New-EmployeeTestJournal {
        param([string]$Root)
        $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $path -Name 'Lön AB' -CompanyType AB | Out-Null
        Import-LedgerChart -JournalPath $path -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $path -StartDate '2024-01-01' -EndDate '2024-12-31'
        return $path
    }
}

Describe 'Add-LedgerEmployee' {
    BeforeAll {
        $Command = Get-Command -Name 'Add-LedgerEmployee'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }
        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
        It 'Should have mandatory EmployeeNumber and Name parameters' {
            foreach ($p in 'EmployeeNumber', 'Name') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-EmployeeTestJournal -Root $TestDrive
        }

        It 'Should add an employee with the default salary account and tax rate' {
            Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name 'Anna Andersson'
            $e = Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1'
            $e.Name | Should -Be 'Anna Andersson'
            $e.SalaryAccount | Should -Be '7210'
            $e.TaxRate | Should -Be 0
        }

        It 'Should store all optional fields' {
            Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '2' -Name 'Bengt Bengtsson' -PersonalNumber '19850101-1234' -SalaryAccount '7010' -TaxRate 0.30
            $e = Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '2'
            $e.PersonalNumber | Should -Be '19850101-1234'
            $e.SalaryAccount | Should -Be '7010'
            $e.TaxRate | Should -Be 0.30
        }

        It 'Should reject a duplicate employee number' {
            Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name 'A'
            { Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name 'B' } | Should -Throw '*already exists*'
        }
    }
}

Describe 'Get-LedgerEmployee' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-EmployeeTestJournal -Root $TestDrive
            Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name 'Anna'
            Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '2' -Name 'Bengt'
        }

        It 'Should list all employees' {
            @(Get-LedgerEmployee -JournalPath $JournalPath).Count | Should -Be 2
        }

        It 'Should filter by employee number' {
            (Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '2').Name | Should -Be 'Bengt'
        }

        It 'Should return nothing for an empty register' {
            $empty = New-EmployeeTestJournal -Root $TestDrive
            @(Get-LedgerEmployee -JournalPath $empty).Count | Should -Be 0
        }
    }
}

Describe 'Set-LedgerEmployee' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-EmployeeTestJournal -Root $TestDrive
            Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name 'Anna' -SalaryAccount '7210' -TaxRate 0.30
        }

        It 'Should update only the specified field' {
            Set-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -TaxRate 0.32
            $e = Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1'
            $e.TaxRate | Should -Be 0.32
            $e.Name | Should -Be 'Anna'
            $e.SalaryAccount | Should -Be '7210'
        }

        It 'Should update multiple fields' {
            Set-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name 'Anna Ek' -SalaryAccount '7010'
            $e = Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1'
            $e.Name | Should -Be 'Anna Ek'
            $e.SalaryAccount | Should -Be '7010'
        }

        It 'Should throw for an unknown employee' {
            { Set-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '999' -Name 'X' } | Should -Throw '*does not exist*'
        }

        It 'Should throw when nothing is specified to update' {
            { Set-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' } | Should -Throw '*Nothing to update*'
        }
    }
}
