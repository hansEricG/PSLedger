BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
}

Describe 'Add-LedgerTaxEntry' {
    Context 'Function metadata' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command Add-LedgerTaxEntry
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should support ShouldProcess' {
            $cmd = Get-Command Add-LedgerTaxEntry
            $cmd.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }

        It 'Should have mandatory Amount parameter of type decimal' {
            $param = (Get-Command Add-LedgerTaxEntry).Parameters['Amount']
            $param.ParameterType | Should -Be ([decimal])
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should have an EstimatedTax alias on Amount' {
            $param = (Get-Command Add-LedgerTaxEntry).Parameters['Amount']
            $param.Aliases | Should -Contain 'EstimatedTax'
        }

        It 'Should have mandatory Date parameter of type datetime' {
            $param = (Get-Command Add-LedgerTaxEntry).Parameters['Date']
            $param.ParameterType | Should -Be ([datetime])
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'taxentry.ledger'
            New-LedgerJournal -Path $jp -Name 'TaxEntry AB' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '4010' -AccountName 'Inköp'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '8910' -AccountName 'Skatt på årets resultat'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2510' -AccountName 'Skatteskulder'

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

        It 'Should book a direct tax amount' {
            $result = Add-LedgerTaxEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Amount 12360
            $result.Amount | Should -Be 12360
            $result.TaxAccount | Should -Be '8910'
            $result.LiabilityAccount | Should -Be '2510'
        }

        It 'Should debit the tax account and credit the liability account' {
            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $entry = $entries | Where-Object { $_.Rows.Account -contains '8910' }
            $entry | Should -Not -BeNullOrEmpty
            $debit = $entry.Rows | Where-Object { $_.Account -eq '8910' }
            $credit = $entry.Rows | Where-Object { $_.Account -eq '2510' }
            $debit.Amount | Should -Be 12360
            $credit.Amount | Should -Be -12360
        }

        It 'Should default the description to Skatt på årets resultat' {
            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $entry = $entries | Where-Object { $_.Rows.Account -contains '8910' }
            $entry.Description | Should -Be 'Skatt på årets resultat'
        }

        It 'Should throw if amount is zero or negative' {
            { Add-LedgerTaxEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Amount 0 } | Should -Throw '*must be positive*'
        }

        It 'Should not create a verification with -WhatIf' {
            $before = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12').Count
            Add-LedgerTaxEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Amount 5000 -WhatIf
            $after = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12').Count
            $after | Should -Be $before
        }

        It 'Should accept tax estimate from the pipeline' {
            $jp2 = Join-Path $TestDrive 'taxpipe.ledger'
            New-LedgerJournal -Path $jp2 -Name 'Pipe AB' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp2 -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $jp2 -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $jp2 -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $jp2 -AccountNumber '4010' -AccountName 'Inköp'
            Add-LedgerAccount -JournalPath $jp2 -AccountNumber '8910' -AccountName 'Skatt på årets resultat'
            Add-LedgerAccount -JournalPath $jp2 -AccountNumber '2510' -AccountName 'Skatteskulder'
            Add-LedgerEntry -JournalPath $jp2 -FiscalYear '2024-01_2024-12' -Date '2024-06-01' `
                -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 100000 }
                @{ Account = '3010'; Amount = -100000 }
            )
            Add-LedgerEntry -JournalPath $jp2 -FiscalYear '2024-01_2024-12' -Date '2024-06-02' `
                -Description 'Inköp' -Rows @(
                @{ Account = '4010'; Amount = 40000 }
                @{ Account = '1910'; Amount = -40000 }
            )

            $result = Get-LedgerTaxEstimate -JournalPath $jp2 -FiscalYear '2024-01_2024-12' |
                Add-LedgerTaxEntry -JournalPath $jp2 -Date '2024-12-31'
            $result.Amount | Should -Be 12360
            $result.FiscalYear | Should -Be '2024-01_2024-12'
        }
    }
}
