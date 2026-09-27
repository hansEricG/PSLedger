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
            New-LedgerJournal -Path $jp -Name 'Aktier AB' -OrgNumber '556000-0004' -CompanyType 'AB'
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

        It 'Should report ReportInput as the market value source' {
            $note = Get-LedgerShareholdingNote -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $note.MarketValueSource | Should -Be 'ReportInput'
        }
    }

    Context 'Holdings' {
        BeforeEach {
            $hp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            $hy = '2024-01_2024-12'
            New-LedgerJournal -Path $hp -Name 'Aktier AB' -OrgNumber '556000-0004' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $hp -AccountNumber '1350' -AccountName 'Andelar i värdepapper'
            Add-LedgerAccount -JournalPath $hp -AccountNumber '1810' -AccountName 'Andelar i börsnoterade företag'
            Add-LedgerAccount -JournalPath $hp -AccountNumber '1930' -AccountName 'Företagskonto'
            New-LedgerFiscalYear -JournalPath $hp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerEntry -JournalPath $hp -FiscalYear $hy -Date '2024-02-01' -Description 'Köp värdepapper' -Rows @(
                @{ Account = '1350'; Amount = 200000 }, @{ Account = '1810'; Amount = 10000 }, @{ Account = '1930'; Amount = -210000 })
            Set-LedgerHolding -JournalPath $hp -FiscalYear $hy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 265.40
            Set-LedgerHolding -JournalPath $hp -FiscalYear $hy -Account 1350 -Name 'Vanguard FTSE All-World' -Quantity 100 -Price 100 -Currency USD -FxRate 10
            Set-LedgerHolding -JournalPath $hp -FiscalYear $hy -Account 1810 -Name 'Spiltan Räntefond' -Quantity 1000 -Price 11.83
        }

        It 'Should use the holdings total within the account range' {
            $note = Get-LedgerShareholdingNote -JournalPath $hp -FiscalYear $hy
            $note.MarketValue | Should -Be 232700
            $note.MarketValueSource | Should -Be 'Holdings'
        }

        It 'Should use the holdings of a custom account range' {
            $note = Get-LedgerShareholdingNote -JournalPath $hp -FiscalYear $hy -FromAccount 1800 -ToAccount 1899
            $note.MarketValue | Should -Be 11830
            $note.BookValue | Should -Be 10000
        }

        It 'Should prefer the holdings over SecuritiesMarketValue and warn when they differ' {
            Set-LedgerReportInput -JournalPath $hp -FiscalYear $hy -SecuritiesMarketValue '300000'
            $note = Get-LedgerShareholdingNote -JournalPath $hp -FiscalYear $hy -WarningVariable w -WarningAction SilentlyContinue
            $note.MarketValue | Should -Be 232700
            ($w -join ' ') | Should -Match 'differs from the holdings total'
        }

        It 'Should still let -MarketValue override the holdings' {
            $note = Get-LedgerShareholdingNote -JournalPath $hp -FiscalYear $hy -MarketValue 1
            $note.MarketValue | Should -Be 1
            $note.MarketValueSource | Should -Be 'Parameter'
        }

        It 'Should warn when an account is below book value' {
            Set-LedgerHolding -JournalPath $hp -FiscalYear $hy -Account 1810 -Name 'Spiltan Räntefond' -Price 9
            $null = Get-LedgerShareholdingNote -JournalPath $hp -FiscalYear $hy -FromAccount 1800 -ToAccount 1899 -WarningVariable w -WarningAction SilentlyContinue
            ($w -join ' ') | Should -Match 'Account 1810: market value 9000.00 is below book value 10000.00'
            ($w -join ' ') | Should -Match 'lägsta värdets princip'
        }

        It 'Should warn when a single holding is below its book value' {
            Set-LedgerHolding -JournalPath $hp -FiscalYear $hy -Account 1350 -Name 'Vanguard FTSE All-World' -BookValue 110000
            $null = Get-LedgerShareholdingNote -JournalPath $hp -FiscalYear $hy -WarningVariable w -WarningAction SilentlyContinue
            ($w -join ' ') | Should -Match "Holding 'Vanguard FTSE All-World' \(1350\).*nedskrivning, K2"
            ($w -join ' ') | Should -Not -Match 'Account 1350'
        }

        It 'Should not warn when all holdings are above book value' {
            $null = Get-LedgerShareholdingNote -JournalPath $hp -FiscalYear $hy -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -BeNullOrEmpty
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
            New-LedgerJournal -Path $jp -Name 'Personal AB' -OrgNumber '556000-0004' -CompanyType 'AB'
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
            New-LedgerJournal -Path $pj -Name 'Personal AB' -OrgNumber '556000-0004' -CompanyType 'AB'
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
