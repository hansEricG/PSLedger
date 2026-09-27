BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerHolding' {
    BeforeAll {
        $Command = Get-Command -Name 'Get-LedgerHolding'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have optional String parameters Account and Name' {
            foreach ($p in 'Account', 'Name') {
                $Command.Parameters[$p].ParameterType.Name | Should -Be 'String'
                $Command.Parameters[$p].Attributes.Mandatory | Should -Not -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'holdings.ledger'
            $fy = '2024-01_2024-12'
            New-LedgerJournal -Path $jp -Name 'Aktier AB' -OrgNumber '556000-0004' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1350' -AccountName 'Andelar och värdepapper'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1810' -AccountName 'Andelar i börsnoterade företag'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1930' -AccountName 'Företagskonto'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy -Date '2024-02-01' -Description 'Köp värdepapper' -Rows @(
                @{ Account = '1350'; Amount = 200000 }, @{ Account = '1930'; Amount = -200000 })
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 265.40 -BookValue 100000
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Atlas Copco A' -Quantity 600 -Price 150 -BookValue 100000
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1810 -Name 'Spiltan Räntefond' -Quantity 1000 -Price 11.83
        }

        It 'Should return nothing when no holdings are recorded' {
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2025-01-01' -EndDate '2025-12-31'
            Get-LedgerHolding -JournalPath $jp -FiscalYear '2025-01_2025-12' | Should -BeNullOrEmpty
        }

        It 'Should return all holdings sorted by account and name' {
            $h = @(Get-LedgerHolding -JournalPath $jp -FiscalYear $fy)
            $h.Count | Should -Be 3
            $h.Name | Should -Be @('Atlas Copco A', 'Investor B', 'Spiltan Räntefond')
            $h[0].FiscalYear | Should -Be $fy
        }

        It 'Should compute market value, difference and whether it is below book value' {
            $inv = Get-LedgerHolding -JournalPath $jp -FiscalYear $fy -Name 'Investor B'
            $inv.MarketValue | Should -Be 132700
            $inv.Difference | Should -Be 32700
            $inv.BelowBookValue | Should -BeFalse
            $atlas = Get-LedgerHolding -JournalPath $jp -FiscalYear $fy -Name 'Atlas*'
            $atlas.MarketValue | Should -Be 90000
            $atlas.Difference | Should -Be -10000
            $atlas.BelowBookValue | Should -BeTrue
        }

        It 'Should leave Difference empty when there is no book value' {
            $fund = Get-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1810
            $fund.Difference | Should -BeNullOrEmpty
            $fund.BelowBookValue | Should -BeNullOrEmpty
        }

        It 'Should report the valuation rule for the account' {
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350)[0].Rule | Should -Be 'FixedAsset'
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1810).Rule | Should -Be 'Current'
        }

        It 'Should skip malformed rows with a warning' {
            $file = Join-Path $jp $fy 'holdings.txt'
            $original = Get-Content $file -Encoding UTF8
            try {
                Add-Content -Path $file -Value "1350`tTrasig`t`tabc`t1`tSEK`t1`t`t`t" -Encoding UTF8
                $h = @(Get-LedgerHolding -JournalPath $jp -FiscalYear $fy -WarningVariable w -WarningAction SilentlyContinue)
                $h.Count | Should -Be 3
                ($w -join ' ') | Should -Match 'malformed'
            }
            finally {
                Set-Content -Path $file -Value $original -Encoding UTF8
            }
        }
    }
}
