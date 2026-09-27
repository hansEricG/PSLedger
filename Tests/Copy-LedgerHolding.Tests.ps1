BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Copy-LedgerHolding' {
    BeforeAll {
        $Command = Get-Command -Name 'Copy-LedgerHolding'
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

        It 'Should have a mandatory String ToFiscalYear parameter and a Force switch' {
            $Command.Parameters['ToFiscalYear'].ParameterType.Name | Should -Be 'String'
            $Command.Parameters['ToFiscalYear'].Attributes.Mandatory | Should -Contain $true
            $Command.Parameters['Force'].ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $jp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            $fy1 = '2023-01_2023-12'
            $fy2 = '2024-01_2024-12'
            New-LedgerJournal -Path $jp -Name 'Aktier AB' -OrgNumber '556000-0004' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1350' -AccountName 'Andelar och värdepapper'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1810' -AccountName 'Andelar i börsnoterade företag'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1930' -AccountName 'Företagskonto'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2023-01-01' -EndDate '2023-12-31'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy1 -Date '2023-02-01' -Description 'Köp aktier' -Rows @(
                @{ Account = '1350'; Amount = 130000 }, @{ Account = '1930'; Amount = -130000 })
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy1 -Account 1350 -Name 'Investor B' -Isin 'SE0015811963' `
                -Quantity 500 -Price 265.4 -PriceDate '2023-12-29' -Source 'Nasdaq Stockholm' -BookValue 130000
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy1 -Account 1810 -Name 'Spiltan Räntefond' -Quantity 1000 -Price 11.83 `
                -WarningAction SilentlyContinue
            Copy-LedgerOpeningBalance -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear $fy2
        }

        It 'Should copy all holdings with all fields' {
            Copy-LedgerHolding -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear $fy2 -WarningAction SilentlyContinue | Out-Null
            $h = @(Get-LedgerHolding -JournalPath $jp -FiscalYear $fy2)
            $h.Count | Should -Be 2
            $inv = $h | Where-Object Name -eq 'Investor B'
            $inv.Isin | Should -Be 'SE0015811963'
            $inv.Quantity | Should -Be 500
            $inv.Price | Should -Be 265.4
            $inv.PriceDate | Should -Be '2023-12-29'
            $inv.Source | Should -Be 'Nasdaq Stockholm'
            $inv.BookValue | Should -Be 130000
        }

        It 'Should return the copied holdings with the target fiscal year' {
            $r = @(Copy-LedgerHolding -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear $fy2 -WarningAction SilentlyContinue)
            $r.Count | Should -Be 2
            $r.FiscalYear | Select-Object -Unique | Should -Be $fy2
        }

        It 'Should warn about holdings whose account has no opening balance in the target year' {
            Copy-LedgerHolding -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear $fy2 -WarningVariable w -WarningAction SilentlyContinue | Out-Null
            @($w).Count | Should -Be 1
            "$w" | Should -BeLike '*1810*opening balance*'
        }

        It 'Should throw when the target already has holdings unless -Force is given' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy2 -Account 1350 -Name 'Volvo B' -Quantity 10 -Price 250
            { Copy-LedgerHolding -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear $fy2 } | Should -Throw '*already has holdings*'

            Copy-LedgerHolding -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear $fy2 -Force -WarningAction SilentlyContinue | Out-Null
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy2).Name | Should -Not -Contain 'Volvo B'
        }

        It 'Should throw when the source has no holdings' {
            { Copy-LedgerHolding -JournalPath $jp -FromFiscalYear $fy2 -ToFiscalYear $fy1 } | Should -Throw '*No holdings*'
        }

        It 'Should refuse to copy into a closed fiscal year' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy2 -Account 1350 -Name 'Volvo B' -Quantity 10 -Price 250
            Close-LedgerFiscalYear -JournalPath $jp -FiscalYear $fy1
            { Copy-LedgerHolding -JournalPath $jp -FromFiscalYear $fy2 -ToFiscalYear $fy1 -Force } | Should -Throw '*Closed*'
        }

        It 'Should throw when the target fiscal year does not exist' {
            { Copy-LedgerHolding -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear '2025-01_2025-12' } | Should -Throw '*not found*'
        }

        It 'Should not write anything with -WhatIf' {
            Copy-LedgerHolding -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear $fy2 -WhatIf -WarningAction SilentlyContinue
            Test-Path (Join-Path $jp $fy2 'holdings.txt') | Should -BeFalse
        }
    }
}
