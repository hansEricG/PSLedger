BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
}

Describe 'Get-LedgerTaxEstimate' {
    Context 'Function metadata' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command Get-LedgerTaxEstimate
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter' {
            $param = (Get-Command Get-LedgerTaxEstimate).Parameters['JournalPath']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeFalse
        }

        It 'Should have a TaxRate parameter of type decimal' {
            $param = (Get-Command Get-LedgerTaxEstimate).Parameters['TaxRate']
            $param.ParameterType | Should -Be ([decimal])
        }

        It 'Should have NonDeductibleExpenses and NonTaxableIncome parameters' {
            $params = (Get-Command Get-LedgerTaxEstimate).Parameters
            $params.ContainsKey('NonDeductibleExpenses') | Should -BeTrue
            $params.ContainsKey('NonTaxableIncome') | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'tax.ledger'
            New-LedgerJournal -Path $jp -Name 'Tax AB' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '4010' -AccountName 'Inköp'

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

        It 'Should compute the result before tax from the ledger' {
            $est = Get-LedgerTaxEstimate -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $est.ResultBeforeTax | Should -Be 60000
        }

        It 'Should use the default tax rate of 0.206' {
            $est = Get-LedgerTaxEstimate -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $est.TaxRate | Should -Be 0.206
        }

        It 'Should estimate tax rounded to whole kronor' {
            $est = Get-LedgerTaxEstimate -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $est.EstimatedTax | Should -Be 12360
        }

        It 'Should add back non-deductible expenses' {
            $est = Get-LedgerTaxEstimate -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -NonDeductibleExpenses 10000
            $est.TaxableResult | Should -Be 70000
            $est.EstimatedTax | Should -Be 14420
        }

        It 'Should subtract non-taxable income' {
            $est = Get-LedgerTaxEstimate -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -NonTaxableIncome 20000
            $est.TaxableResult | Should -Be 40000
            $est.EstimatedTax | Should -Be 8240
        }

        It 'Should honour a custom tax rate' {
            $est = Get-LedgerTaxEstimate -JournalPath $jp -FiscalYear '2024-01_2024-12' -TaxRate 0.22
            $est.EstimatedTax | Should -Be 13200
        }

        It 'Should give zero tax for a negative taxable result' {
            $est = Get-LedgerTaxEstimate -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -NonTaxableIncome 100000
            $est.TaxableResult | Should -Be -40000
            $est.EstimatedTax | Should -Be 0
        }
    }
}
