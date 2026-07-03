BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
}

Describe 'Add-LedgerDepreciation' {
    Context 'Function metadata' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command Add-LedgerDepreciation
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should support ShouldProcess' {
            $cmd = Get-Command Add-LedgerDepreciation
            $cmd.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter' {
            $param = (Get-Command Add-LedgerDepreciation).Parameters['JournalPath']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeFalse
        }

        It 'Should have mandatory Date parameter of type datetime' {
            $param = (Get-Command Add-LedgerDepreciation).Parameters['Date']
            $param.ParameterType | Should -Be ([datetime])
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should have mandatory ExpenseAccount parameter' {
            $param = (Get-Command Add-LedgerDepreciation).Parameters['ExpenseAccount']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should have mandatory AccumulatedDepreciationAccount parameter' {
            $param = (Get-Command Add-LedgerDepreciation).Parameters['AccumulatedDepreciationAccount']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should have an Amount parameter of type decimal' {
            $param = (Get-Command Add-LedgerDepreciation).Parameters['Amount']
            $param.ParameterType | Should -Be ([decimal])
        }

        It 'Should have a UsefulLifeYears parameter of type int' {
            $param = (Get-Command Add-LedgerDepreciation).Parameters['UsefulLifeYears']
            $param.ParameterType | Should -Be ([int])
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'depreciation.ledger'
            New-LedgerJournal -Path $jp -Name 'Depreciation AB' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '7832' -AccountName 'Avskrivningar på inventarier'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1229' -AccountName 'Ackumulerade avskrivningar på inventarier'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '7831' -AccountName 'Avskrivningar på maskiner'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1219' -AccountName 'Ackumulerade avskrivningar på maskiner'
        }

        It 'Should book a direct depreciation amount' {
            $result = Add-LedgerDepreciation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -ExpenseAccount '7832' `
                -AccumulatedDepreciationAccount '1229' -Amount 20000

            $result.Amount | Should -Be 20000
            $result.ExpenseAccount | Should -Be '7832'
            $result.AccumulatedDepreciationAccount | Should -Be '1229'
        }

        It 'Should debit expense and credit accumulated depreciation' {
            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $entry = $entries | Where-Object { $_.Rows.Account -contains '7832' }
            $entry | Should -Not -BeNullOrEmpty
            $debit = $entry.Rows | Where-Object { $_.Account -eq '7832' }
            $credit = $entry.Rows | Where-Object { $_.Account -eq '1229' }
            $debit.Amount | Should -Be 20000
            $credit.Amount | Should -Be -20000
        }

        It 'Should default the description to Planenlig avskrivning' {
            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $entry = $entries | Where-Object { $_.Rows.Account -contains '7832' }
            $entry.Description | Should -Be 'Planenlig avskrivning'
        }

        It 'Should calculate straight-line depreciation from acquisition cost and useful life' {
            $result = Add-LedgerDepreciation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Description 'Avskrivning maskiner' -ExpenseAccount '7831' `
                -AccumulatedDepreciationAccount '1219' -AcquisitionCost 250000 -UsefulLifeYears 5

            $result.Amount | Should -Be 50000
            $result.Description | Should -Be 'Avskrivning maskiner'
        }

        It 'Should round calculated depreciation to two decimals' {
            $result = Add-LedgerDepreciation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -ExpenseAccount '7831' `
                -AccumulatedDepreciationAccount '1219' -AcquisitionCost 10000 -UsefulLifeYears 3

            $result.Amount | Should -Be 3333.33
        }

        It 'Should throw if direct amount is zero or negative' {
            { Add-LedgerDepreciation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -ExpenseAccount '7832' `
                -AccumulatedDepreciationAccount '1229' -Amount 0 } |
                Should -Throw '*must be positive*'
        }

        It 'Should throw if acquisition cost is zero or negative' {
            { Add-LedgerDepreciation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -ExpenseAccount '7831' `
                -AccumulatedDepreciationAccount '1219' -AcquisitionCost 0 -UsefulLifeYears 5 } |
                Should -Throw '*AcquisitionCost must be positive*'
        }

        It 'Should throw if useful life is zero or negative' {
            { Add-LedgerDepreciation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -ExpenseAccount '7831' `
                -AccumulatedDepreciationAccount '1219' -AcquisitionCost 100000 -UsefulLifeYears 0 } |
                Should -Throw '*UsefulLifeYears must be positive*'
        }

        It 'Should not create a verification with -WhatIf' {
            $before = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12').Count
            Add-LedgerDepreciation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -ExpenseAccount '7832' `
                -AccumulatedDepreciationAccount '1229' -Amount 5000 -WhatIf
            $after = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12').Count
            $after | Should -Be $before
        }
    }
}
