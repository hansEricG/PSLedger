BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerShareholdingNote' {
    BeforeAll {
        $Command = Get-Command -Name 'Get-LedgerShareholdingNote'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a MarketValue parameter of type Decimal' {
            $Command.Parameters['MarketValue'].ParameterType.Name | Should -Be 'Decimal'
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'shares.ledger'
            New-LedgerJournal -Path $jp -Name 'Aktier AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1350' -AccountName 'Andelar i värdepapper'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1930' -AccountName 'Företagskonto'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-02-01' -Description 'Köp värdepapper' -Rows @(
                @{ Account = '1350'; Amount = 277579 }, @{ Account = '1930'; Amount = -277579 })
        }

        It 'Should report the carrying amount from the balance' {
            $note = Get-LedgerShareholdingNote -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $note.BookValue | Should -Be 277579
        }

        It 'Should use the recorded market value' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear '2024-01_2024-12' -SecuritiesMarketValue '300000'
            $note = Get-LedgerShareholdingNote -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $note.MarketValue | Should -Be 300000
        }

        It 'Should let -MarketValue override the recorded value' {
            $note = Get-LedgerShareholdingNote -JournalPath $jp -FiscalYear '2024-01_2024-12' -MarketValue 250000
            $note.MarketValue | Should -Be 250000
        }

        It 'Should honour a custom account range' {
            $note = Get-LedgerShareholdingNote -JournalPath $jp -FiscalYear '2024-01_2024-12' -FromAccount 1800 -ToAccount 1899
            $note.BookValue | Should -Be 0
        }
    }
}

Describe 'Get-LedgerEmployeeNote' {
    BeforeAll {
        $Command = Get-Command -Name 'Get-LedgerEmployeeNote'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'emp.ledger'
            New-LedgerJournal -Path $jp -Name 'Personal AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
        }

        It 'Should default to zero employees with the standard statement' {
            $note = Get-LedgerEmployeeNote -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $note.AverageEmployees | Should -Be 0
            $note.Statement | Should -Match 'inte haft några anställda'
        }

        It 'Should use the recorded average employees' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear '2024-01_2024-12' -AverageEmployees '3'
            $note = Get-LedgerEmployeeNote -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $note.AverageEmployees | Should -Be 3
            $note.Statement | Should -Match 'Medelantalet anställda'
        }

        It 'Should let -AverageEmployees override the recorded value' {
            $note = Get-LedgerEmployeeNote -JournalPath $jp -FiscalYear '2024-01_2024-12' -AverageEmployees 5
            $note.AverageEmployees | Should -Be 5
        }
    }

    Context 'Payroll integration' {
        BeforeAll {
            $pj = Join-Path $TestDrive 'payrollnote.ledger'
            New-LedgerJournal -Path $pj -Name 'Personal AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            Import-LedgerChart -JournalPath $pj -Template 'BAS-Smaforetag'
            New-LedgerFiscalYear -JournalPath $pj -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerEmployee -JournalPath $pj -EmployeeNumber '1' -Name 'Anna' -TaxRate 0.30
            New-LedgerPayslip -JournalPath $pj -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-03-25' | Out-Null
            Invoke-LedgerPayrollPosting -JournalPath $pj -PayslipNumber 1
        }

        It 'Should derive the average employees from posted payslips' {
            $note = Get-LedgerEmployeeNote -JournalPath $pj -FiscalYear '2024-01_2024-12'
            $note.AverageEmployees | Should -Be 1
            $note.Statement | Should -Match 'Medelantalet anställda'
        }

        It 'Should sum the personnel costs booked to 7000-7699' {
            $note = Get-LedgerEmployeeNote -JournalPath $pj -FiscalYear '2024-01_2024-12'
            $note.PersonnelCosts | Should -Be 39426
        }
    }
}
