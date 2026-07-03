BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
}

Describe 'Add-LedgerAppropriation' {
    Context 'Function metadata' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command Add-LedgerAppropriation
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should support ShouldProcess' {
            $cmd = Get-Command Add-LedgerAppropriation
            $cmd.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }

        It 'Should have mandatory Amount parameter of type decimal' {
            $param = (Get-Command Add-LedgerAppropriation).Parameters['Amount']
            $param.ParameterType | Should -Be ([decimal])
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should have a Type parameter that validates the reserve type' {
            $param = (Get-Command Add-LedgerAppropriation).Parameters['Type']
            $validate = $param.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] })
            $validate.ValidValues | Should -Contain 'Periodiseringsfond'
            $validate.ValidValues | Should -Contain 'Overavskrivning'
        }

        It 'Should have a Reverse switch parameter' {
            $param = (Get-Command Add-LedgerAppropriation).Parameters['Reverse']
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'appropriation.ledger'
            New-LedgerJournal -Path $jp -Name 'Appropriation AB' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2110' -AccountName 'Periodiseringsfonder'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '8811' -AccountName 'Avsättning till periodiseringsfond'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '8819' -AccountName 'Återföring från periodiseringsfond'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2150' -AccountName 'Ackumulerade överavskrivningar'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '8850' -AccountName 'Förändring av överavskrivningar'
        }

        It 'Should allocate to a tax allocation reserve (debit 8811, credit 2110)' {
            $result = Add-LedgerAppropriation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Type Periodiseringsfond -Amount 50000
            $result.ReserveAccount | Should -Be '2110'
            $result.AppropriationAccount | Should -Be '8811'
            $result.Reverse | Should -BeFalse

            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $entry = $entries | Where-Object { $_.Description -eq 'Avsättning till periodiseringsfond' }
            ($entry.Rows | Where-Object { $_.Account -eq '8811' }).Amount | Should -Be 50000
            ($entry.Rows | Where-Object { $_.Account -eq '2110' }).Amount | Should -Be -50000
        }

        It 'Should reverse a tax allocation reserve (debit 2110, credit 8819)' {
            $result = Add-LedgerAppropriation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Type Periodiseringsfond -Amount 30000 -Reverse
            $result.AppropriationAccount | Should -Be '8819'
            $result.Reverse | Should -BeTrue

            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $entry = $entries | Where-Object { $_.Description -eq 'Återföring från periodiseringsfond' }
            ($entry.Rows | Where-Object { $_.Account -eq '2110' }).Amount | Should -Be 30000
            ($entry.Rows | Where-Object { $_.Account -eq '8819' }).Amount | Should -Be -30000
        }

        It 'Should book excess depreciation (debit 8850, credit 2150)' {
            $result = Add-LedgerAppropriation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Type Overavskrivning -Amount 15000
            $result.ReserveAccount | Should -Be '2150'
            $result.AppropriationAccount | Should -Be '8850'

            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $entry = $entries | Where-Object { $_.Description -eq 'Förändring av överavskrivningar' }
            ($entry.Rows | Where-Object { $_.Account -eq '8850' }).Amount | Should -Be 15000
            ($entry.Rows | Where-Object { $_.Account -eq '2150' }).Amount | Should -Be -15000
        }

        It 'Should reverse excess depreciation (debit 2150, credit 8850)' {
            $result = Add-LedgerAppropriation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Type Overavskrivning -Amount 5000 -Reverse
            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $entry = $entries | Where-Object { $_.Description -eq 'Återföring av överavskrivningar' }
            ($entry.Rows | Where-Object { $_.Account -eq '2150' }).Amount | Should -Be 5000
            ($entry.Rows | Where-Object { $_.Account -eq '8850' }).Amount | Should -Be -5000
        }

        It 'Should allow overriding the accounts' {
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2120' -AccountName 'Periodiseringsfond 2020'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '8810' -AccountName 'Förändring av periodiseringsfond'
            $result = Add-LedgerAppropriation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Type Periodiseringsfond -Amount 1000 `
                -ReserveAccount '2120' -AppropriationAccount '8810'
            $result.ReserveAccount | Should -Be '2120'
            $result.AppropriationAccount | Should -Be '8810'
        }

        It 'Should throw if amount is zero or negative' {
            { Add-LedgerAppropriation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Type Periodiseringsfond -Amount 0 } |
                Should -Throw '*must be positive*'
        }

        It 'Should not create a verification with -WhatIf' {
            $before = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12').Count
            Add-LedgerAppropriation -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Type Periodiseringsfond -Amount 1000 -WhatIf
            $after = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12').Count
            $after | Should -Be $before
        }
    }
}
