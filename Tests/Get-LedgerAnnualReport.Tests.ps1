BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
}

Describe 'Get-LedgerAnnualReport' {
    Context 'Function metadata' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command Get-LedgerAnnualReport
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter' {
            $param = (Get-Command Get-LedgerAnnualReport).Parameters['JournalPath']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeFalse
        }

        It 'Should have a NoComparison switch parameter' {
            $param = (Get-Command Get-LedgerAnnualReport).Parameters['NoComparison']
            $param.ParameterType | Should -Be ([switch])
        }

        It 'Should accept FiscalYear from the pipeline with a Name alias' {
            $param = (Get-Command Get-LedgerAnnualReport).Parameters['FiscalYear']
            $param.Aliases | Should -Contain 'Name'
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'annual.ledger'
            New-LedgerJournal -Path $jp -Name 'Annual AB' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2023-01-01' -EndDate '2023-12-31'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '4010' -AccountName 'Inköp'

            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-06-01' `
                -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 80000 }
                @{ Account = '3010'; Amount = -80000 }
            )
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-06-02' `
                -Description 'Inköp' -Rows @(
                @{ Account = '4010'; Amount = 30000 }
                @{ Account = '1910'; Amount = -30000 }
            )
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-06-01' `
                -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 100000 }
                @{ Account = '3010'; Amount = -100000 }
            )
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-06-02' `
                -Description 'Inköp' -Rows @(
                @{ Account = '4010'; Amount = 40000 }
                @{ Account = '1910'; Amount = -40000 }
            )
        }

        It 'Should include both income statement and balance sheet lines' {
            $report = @(Get-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12')
            ($report | Where-Object { $_.Statement -eq 'IncomeStatement' }) | Should -Not -BeNullOrEmpty
            ($report | Where-Object { $_.Statement -eq 'BalanceSheet' }) | Should -Not -BeNullOrEmpty
        }

        It 'Should report the current year net sales' {
            $report = @(Get-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $netSales = $report | Where-Object { $_.Statement -eq 'IncomeStatement' -and $_.Group -eq 'NetSales' }
            $netSales.Amount | Should -Be 100000
        }

        It 'Should include the previous year comparison amount' {
            $report = @(Get-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $netSales = $report | Where-Object { $_.Statement -eq 'IncomeStatement' -and $_.Group -eq 'NetSales' }
            $netSales.ComparisonAmount | Should -Be 80000
            $netSales.ComparisonFiscalYear | Should -Be '2023-01_2023-12'
        }

        It 'Should omit comparison figures with -NoComparison' {
            $report = @(Get-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12' -NoComparison)
            $netSales = $report | Where-Object { $_.Statement -eq 'IncomeStatement' -and $_.Group -eq 'NetSales' }
            $netSales.ComparisonAmount | Should -BeNullOrEmpty
            $netSales.ComparisonFiscalYear | Should -BeNullOrEmpty
        }

        It 'Should have no comparison for the first fiscal year' {
            $report = @(Get-LedgerAnnualReport -JournalPath $jp -FiscalYear '2023-01_2023-12')
            $netSales = $report | Where-Object { $_.Statement -eq 'IncomeStatement' -and $_.Group -eq 'NetSales' }
            $netSales.Amount | Should -Be 80000
            $netSales.ComparisonFiscalYear | Should -BeNullOrEmpty
        }

        It 'Should report balance sheet totals for the current year' {
            $report = @(Get-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $totalAssets = $report | Where-Object { $_.Statement -eq 'BalanceSheet' -and $_.Group -eq 'TotalAssets' }
            $totalAssets.Amount | Should -Be 60000
        }
    }
}
