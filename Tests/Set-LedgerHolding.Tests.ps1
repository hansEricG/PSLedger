BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Set-LedgerHolding' {
    BeforeAll {
        $Command = Get-Command -Name 'Set-LedgerHolding'
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

        It 'Should have mandatory String parameters Account and Name' {
            foreach ($p in 'Account', 'Name') {
                $Command.Parameters[$p].ParameterType.Name | Should -Be 'String'
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'Should have Decimal parameters Quantity, Price and FxRate' {
            foreach ($p in 'Quantity', 'Price', 'FxRate') {
                $Command.Parameters[$p].ParameterType.Name | Should -Be 'Decimal'
            }
        }

        It 'Should have a nullable decimal BookValue parameter' {
            $Command.Parameters['BookValue'].ParameterType | Should -Be ([Nullable[decimal]])
        }

        It 'Should have optional String parameters Isin, Currency, PriceDate and Source' {
            foreach ($p in 'Isin', 'Currency', 'PriceDate', 'Source') {
                $Command.Parameters[$p].ParameterType.Name | Should -Be 'String'
                $Command.Parameters[$p].Attributes.Mandatory | Should -Not -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $jp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            $fy = '2024-01_2024-12'
            New-LedgerJournal -Path $jp -Name 'Aktier AB' -OrgNumber '556000-0004' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1350' -AccountName 'Andelar och värdepapper'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1810' -AccountName 'Andelar i börsnoterade företag'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1930' -AccountName 'Företagskonto'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            $file = Join-Path $jp $fy 'holdings.txt'
        }

        It 'Should create holdings.txt with a header row and the holding' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 265.40
            $lines = Get-Content $file -Encoding UTF8
            $lines[0] | Should -Be "Account`tName`tIsin`tQuantity`tPrice`tCurrency`tFxRate`tPriceDate`tSource`tBookValue`tCost"
            $lines[1] | Should -Be "1350`tInvestor B`t`t500`t265.4`tSEK`t1`t`t`t`t"
        }

        It 'Should read a holdings file written before the Cost column existed' {
            New-Item -ItemType File -Path $file -Force | Out-Null
            Set-Content -Path $file -Encoding UTF8 -Value @(
                "Account`tName`tIsin`tQuantity`tPrice`tCurrency`tFxRate`tPriceDate`tSource`tBookValue"
                "1350`tInvestor B`t`t500`t265.4`tSEK`t1`t`t`t100000"
            )
            $h = Get-LedgerHolding -JournalPath $jp -FiscalYear $fy
            $h.BookValue | Should -Be 100000
            $h.Cost | Should -BeNullOrEmpty
        }

        It 'Should store, keep and clear Cost' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Knowit' -Quantity 200 -Price 94.5 -BookValue 18900 -Cost 43248
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy).Cost | Should -Be 43248
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Knowit' -Price 100
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy).Cost | Should -Be 43248
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Knowit' -Cost $null
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy).Cost | Should -BeNullOrEmpty
        }

        It 'Should warn when BookValue exceeds Cost' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Knowit' -Quantity 200 -Price 94.5 `
                -BookValue 50000 -Cost 43248 -WarningVariable w -WarningAction SilentlyContinue
            "$w" | Should -BeLike '*exceeds the acquisition cost*'
        }

        It 'Should store all optional fields including Swedish characters' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1810 -Name 'Spiltan Räntefond Sverige' `
                -Isin 'se0015811963' -Quantity 1000.5 -Price 11.83 -PriceDate '2024-12-31' -Source 'Fondbolagets årsbesked' -BookValue 12000
            $h = Get-LedgerHolding -JournalPath $jp -FiscalYear $fy
            $h.Name | Should -Be 'Spiltan Räntefond Sverige'
            $h.Isin | Should -Be 'SE0015811963'
            $h.Quantity | Should -Be 1000.5
            $h.PriceDate | Should -Be '2024-12-31'
            $h.Source | Should -Be 'Fondbolagets årsbesked'
            $h.BookValue | Should -Be 12000
        }

        It 'Should update an existing holding and keep fields that are not supplied' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 265.40 -BookValue 100000 -Source 'Nasdaq'
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Price 300
            $h = @(Get-LedgerHolding -JournalPath $jp -FiscalYear $fy)
            $h.Count | Should -Be 1
            $h[0].Quantity | Should -Be 500
            $h[0].Price | Should -Be 300
            $h[0].BookValue | Should -Be 100000
            $h[0].Source | Should -Be 'Nasdaq'
        }

        It 'Should clear BookValue with $null and Source with an empty string' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 265.40 -BookValue 100000 -Source 'Nasdaq'
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -BookValue $null -Source ''
            $h = Get-LedgerHolding -JournalPath $jp -FiscalYear $fy
            $h.BookValue | Should -BeNullOrEmpty
            $h.Source | Should -BeNullOrEmpty
        }

        It 'Should treat holdings with the same name on different accounts as separate' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 265
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1810 -Name 'Investor B' -Quantity 10 -Price 265
            @(Get-LedgerHolding -JournalPath $jp -FiscalYear $fy).Count | Should -Be 2
        }

        It 'Should require Quantity and Price for a new holding' {
            { Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Price 265 } |
                Should -Throw '*Quantity is required*'
            { Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 5 } |
                Should -Throw '*Price is required*'
        }

        It 'Should require FxRate for a foreign currency' {
            { Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Apple' -Quantity 10 -Price 200 -Currency USD } |
                Should -Throw '*FxRate*'
        }

        It 'Should reject an FxRate other than 1 for SEK' {
            { Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 10 -Price 200 -FxRate 2 } |
                Should -Throw '*FxRate must be 1*'
        }

        It 'Should compute the market value in SEK for a foreign currency holding' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Apple' -Isin 'US0378331005' `
                -Quantity 10 -Price 250.50 -Currency usd -FxRate 11.0521
            $h = Get-LedgerHolding -JournalPath $jp -FiscalYear $fy
            $h.Currency | Should -Be 'USD'
            $h.MarketValue | Should -Be ([Math]::Round(10 * 250.50 * 11.0521, 2))
        }

        It 'Should reset the exchange rate when switching to SEK' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Fond' -Quantity 10 -Price 100 -Currency EUR -FxRate 11.5
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Fond' -Currency SEK -Price 1150
            $h = Get-LedgerHolding -JournalPath $jp -FiscalYear $fy
            $h.FxRate | Should -Be 1
            $h.MarketValue | Should -Be 11500
        }

        It 'Should reject an ISIN with an invalid check digit' {
            { Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 1 -Price 1 -Isin 'SE0015811964' } |
                Should -Throw '*Invalid ISIN*'
        }

        It 'Should reject a malformed PriceDate' {
            { Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 1 -Price 1 -PriceDate '31/12/2024' } |
                Should -Throw '*PriceDate*'
        }

        It 'Should reject a name containing a tab' {
            { Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name "Investor`tB" -Quantity 1 -Price 1 } |
                Should -Throw '*tabs*'
        }

        It 'Should warn when the ISIN is already used by another holding' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 1 -Price 1 -Isin 'SE0015811963'
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1810 -Name 'Investor ser. B' -Quantity 1 -Price 1 -Isin 'SE0015811963' -WarningVariable w -WarningAction SilentlyContinue
            ($w -join ' ') | Should -Match 'already used'
        }

        It 'Should warn when the account is not a securities account' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1930 -Name 'Bank' -Quantity 1 -Price 1 -WarningVariable w -WarningAction SilentlyContinue
            ($w -join ' ') | Should -Match '13xx or 18xx'
        }

        It 'Should refuse to change holdings in a closed fiscal year' {
            Close-LedgerFiscalYear -JournalPath $jp -FiscalYear $fy
            { Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 1 -Price 1 } |
                Should -Throw '*Closed*'
        }

        It 'Should not write anything with -WhatIf' {
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 1 -Price 1 -WhatIf
            Test-Path $file | Should -BeFalse
        }
    }
}
