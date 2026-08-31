BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerMultiYearOverview' {
    BeforeAll {
        $CommandName = 'Get-LedgerMultiYearOverview'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have a Years parameter of type Int32' {
            $Param = $Command.Parameters['Years']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'Int32'
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'multiyear.ledger'
            New-LedgerJournal -Path $jp -Name 'Flerår AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '3010' -AccountName 'Försäljning'

            foreach ($y in @('2022-01-01','2023-01-01','2024-01-01')) {
                $end = ([datetime]$y).AddYears(1).AddDays(-1).ToString('yyyy-MM-dd')
                New-LedgerFiscalYear -JournalPath $jp -StartDate $y -EndDate $end
            }
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2022-01_2022-12' -Date '2022-06-01' -Description 'Fsg' -Rows @(
                @{ Account = '1910'; Amount = 10000 }, @{ Account = '3010'; Amount = -10000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-06-01' -Description 'Fsg' -Rows @(
                @{ Account = '1910'; Amount = 20000 }, @{ Account = '3010'; Amount = -20000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-06-01' -Description 'Fsg' -Rows @(
                @{ Account = '1910'; Amount = 30000 }, @{ Account = '3010'; Amount = -30000 })
        }

        It 'Should return three rows by default' {
            $rows = @(Get-LedgerMultiYearOverview -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $rows.Count | Should -Be 3
        }

        It 'Should return the newest year first' {
            $rows = @(Get-LedgerMultiYearOverview -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $rows[0].FiscalYear | Should -Be '2024-01_2024-12'
            $rows[2].FiscalYear | Should -Be '2022-01_2022-12'
        }

        It 'Should report net sales per year' {
            $rows = @(Get-LedgerMultiYearOverview -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $rows[0].NetSales | Should -Be 30000
            $rows[1].NetSales | Should -Be 20000
            $rows[2].NetSales | Should -Be 10000
        }

        It 'Should limit rows to the requested number of years' {
            $rows = @(Get-LedgerMultiYearOverview -JournalPath $jp -FiscalYear '2024-01_2024-12' -Years 2)
            $rows.Count | Should -Be 2
            $rows[0].FiscalYear | Should -Be '2024-01_2024-12'
            $rows[1].FiscalYear | Should -Be '2023-01_2023-12'
        }

        It 'Should return fewer rows when history is short' {
            $rows = @(Get-LedgerMultiYearOverview -JournalPath $jp -FiscalYear '2022-01_2022-12')
            $rows.Count | Should -Be 1
        }

        It 'Should label a calendar-year fiscal year with its year' {
            $rows = @(Get-LedgerMultiYearOverview -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $rows[0].YearLabel | Should -Be '2024'
        }
    }

    Context 'Behavior with broken fiscal year' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'broken.ledger'
            New-LedgerJournal -Path $jp -Name 'Brutet AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-09-01' -EndDate '2025-08-31'
        }

        It 'Should label a broken fiscal year with both calendar years' {
            $rows = @(Get-LedgerMultiYearOverview -JournalPath $jp -FiscalYear '2024-09_2025-08')
            $rows[0].YearLabel | Should -Be '2024/2025'
        }
    }
}
