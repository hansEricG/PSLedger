BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerImpairment' {
    BeforeAll {
        $Command = Get-Command -Name 'Add-LedgerImpairment'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should support ShouldProcess' {
            Test-TDDSupportsShouldProcess -Command $Command | Should -BeTrue
        }

        It 'Should have mandatory ExpenseAccount and AdjustmentAccount parameters' {
            foreach ($p in 'ExpenseAccount', 'AdjustmentAccount') {
                $Command.Parameters[$p].ParameterType.Name | Should -Be 'String'
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'Should have DirectAmount and Holding parameter sets' {
            $Command.ParameterSets.Name | Should -Contain 'DirectAmount'
            $Command.ParameterSets.Name | Should -Contain 'Holding'
            $Command.Parameters['Amount'].ParameterType.Name | Should -Be 'Decimal'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $jp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            $fy = '2024-01_2024-12'
            New-LedgerJournal -Path $jp -Name 'Aktier AB' -OrgNumber '556000-0004' -CompanyType 'AB'
            foreach ($a in @(
                    @('1350', 'Andelar och värdepapper i andra företag'), @('1359', 'Ackumulerade nedskrivningar'),
                    @('1930', 'Företagskonto'), @('8271', 'Nedskrivning av andelar i andra företag'))) {
                Add-LedgerAccount -JournalPath $jp -AccountNumber $a[0] -AccountName $a[1]
            }
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy -Date '2024-02-01' -Description 'Köp aktier' -Rows @(
                @{ Account = '1350'; Amount = 150000 }, @{ Account = '1930'; Amount = -150000 })

            function Get-Bal ([string]$Account) {
                $row = Get-LedgerBalance -JournalPath $jp -FiscalYear $fy | Where-Object AccountNumber -eq $Account
                if ($row) { [decimal]$row.Balance } else { [decimal]0 }
            }
        }

        It 'Should book a direct amount on the fiscal year end date' {
            $r = Add-LedgerImpairment -JournalPath $jp -FiscalYear $fy -ExpenseAccount 8271 -AdjustmentAccount 1359 -Amount 12000
            $r.Amount | Should -Be 12000
            $r.Date | Should -Be ([datetime]'2024-12-31')
            $r.Holding | Should -BeNullOrEmpty
            Get-Bal '8271' | Should -Be 12000
            Get-Bal '1359' | Should -Be -12000
        }

        It 'Should use -Date and -Description when given' {
            $r = Add-LedgerImpairment -JournalPath $jp -FiscalYear $fy -ExpenseAccount 8271 -AdjustmentAccount 1359 `
                -Amount 500 -Date '2024-11-30' -Description 'Nedskrivning Investor B'
            $entry = Get-LedgerEntry -JournalPath $jp -FiscalYear $fy -VerificationNumber $r.VerificationNumber
            $entry.Description | Should -Be 'Nedskrivning Investor B'
            $r.Date | Should -Be ([datetime]'2024-11-30')
        }

        It 'Should throw for a non-positive amount' {
            { Add-LedgerImpairment -JournalPath $jp -FiscalYear $fy -ExpenseAccount 8271 -AdjustmentAccount 1359 -Amount 0 } |
                Should -Throw '*positive*'
        }

        It 'Should write a holding down to market value and update its BookValue' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 200 -BookValue 120000
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Volvo B' -Quantity 100 -Price 300 -BookValue 30000
            $r = Add-LedgerImpairment -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' `
                -ExpenseAccount 8271 -AdjustmentAccount 1359

            $r.Amount | Should -Be 20000
            $r.Holding | Should -Be 'Investor B'
            Get-Bal '1359' | Should -Be -20000
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy -Name 'Investor B').BookValue | Should -Be 100000
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy -Name 'Volvo B').BookValue | Should -Be 30000
            $entry = Get-LedgerEntry -JournalPath $jp -FiscalYear $fy -VerificationNumber $r.VerificationNumber
            $entry.Description | Should -Be 'Nedskrivning Investor B till marknadsvärde'
        }

        It 'Should use the account book value for a sole holding without BookValue' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 280
            $r = Add-LedgerImpairment -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' `
                -ExpenseAccount 8271 -AdjustmentAccount 1359
            $r.Amount | Should -Be 10000
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy).BookValue | Should -Be 140000
        }

        It 'Should accept a holding from the pipeline' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 280
            $r = Get-LedgerHolding -JournalPath $jp -FiscalYear $fy |
                Add-LedgerImpairment -JournalPath $jp -ExpenseAccount 8271 -AdjustmentAccount 1359
            $r.Amount | Should -Be 10000
        }

        It 'Should throw when a holding without BookValue shares its account' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 200
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Volvo B' -Quantity 100 -Price 300
            { Add-LedgerImpairment -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' `
                    -ExpenseAccount 8271 -AdjustmentAccount 1359 } | Should -Throw '*BookValue*'
        }

        It 'Should throw when the holding is not below book value' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 320
            { Add-LedgerImpairment -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' `
                    -ExpenseAccount 8271 -AdjustmentAccount 1359 } | Should -Throw '*not below*'
        }

        It 'Should throw when the holding does not exist' {
            { Add-LedgerImpairment -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Saknas AB' `
                    -ExpenseAccount 8271 -AdjustmentAccount 1359 } | Should -Throw '*not found*'
        }

        It 'Should neither book nor change the holding with -WhatIf' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 200 -BookValue 120000
            Add-LedgerImpairment -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' `
                -ExpenseAccount 8271 -AdjustmentAccount 1359 -WhatIf
            Get-Bal '1359' | Should -Be 0
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy).BookValue | Should -Be 120000
        }
    }
}
