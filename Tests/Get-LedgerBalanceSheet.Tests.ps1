BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerBalanceSheet' {
    BeforeAll {
        $CommandName = 'Get-LedgerBalanceSheet'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have an optional FiscalYear parameter of type String that binds from Name' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
            $Param.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $Param.Aliases | Should -Contain 'Name'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'

            Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Mini'

            # Cash sale: asset increases, equity (via revenue)
            $Rows1 = @(
                @{ Account = '1910'; Amount = 30000 }
                @{ Account = '3010'; Amount = -30000 }
            )
            # Liability: buy on credit
            $Rows2 = @(
                @{ Account = '4010'; Amount = 10000 }
                @{ Account = '2440'; Amount = -10000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Kontantförsäljning' -Rows $Rows1
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-02-01' -Description 'Inköp på kredit' -Rows $Rows2
        }

        It 'Should return detailed line items with section totals' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result.Count | Should -Be 12
            ($Result | Where-Object { $_.Group -eq 'TotalAssets' }) | Should -Not -BeNullOrEmpty
            ($Result | Where-Object { $_.Group -eq 'TotalEquityAndLiabilities' }) | Should -Not -BeNullOrEmpty
        }

        It 'Should report cash and bank under likvida medel' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Cash = $Result | Where-Object { $_.Group -eq 'CashAndBank' }

            $Cash.Label | Should -Be 'Likvida medel'
            $Cash.Amount | Should -Be 30000
        }

        It 'Should show total assets' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Assets = $Result | Where-Object { $_.Group -eq 'TotalAssets' }

            $Assets.Amount | Should -Be 30000
        }

        It 'Should report short-term liabilities with their natural credit sign' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear
            $ShortTerm = $Result | Where-Object { $_.Group -eq 'ShortTermLiabilities' }

            $ShortTerm.Label | Should -Be 'Kortfristiga skulder'
            $ShortTerm.Amount | Should -Be -10000
        }

        It 'Should report the unclosed year result on a separate line' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Res = $Result | Where-Object { $_.Group -eq 'Result' }

            # Revenue 3010 (-30000) and expense 4010 (10000) net to -20000 (credit/profit)
            $Res.Amount | Should -Be -20000
        }

        It 'Should balance so total assets equal negated total equity and liabilities' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Assets = ($Result | Where-Object { $_.Group -eq 'TotalAssets' }).Amount
            $EqLiab = ($Result | Where-Object { $_.Group -eq 'TotalEquityAndLiabilities' }).Amount

            ($Assets + $EqLiab) | Should -Be 0
        }

        It 'Should return empty if no entries exist' {
            $EmptyJournal = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $EmptyJournal -Name 'Tom AB'
            New-LedgerFiscalYear -JournalPath $EmptyJournal -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Result = Get-LedgerBalanceSheet -JournalPath $EmptyJournal -FiscalYear '2024-01_2024-12'

            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'Detailed breakdown' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Detalj AB' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'

            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2081' -AccountName 'Aktiekapital'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2091' -AccountName 'Balanserat resultat'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2510' -AccountName 'Skatteskulder'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2440' -AccountName 'Leverantörsskulder'

            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-02' -Description 'Aktiekapital' -Rows @(
                @{ Account = '1910'; Amount = 100000 }, @{ Account = '2081'; Amount = -100000 })
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-01' -Description 'Skatteskuld' -Rows @(
                @{ Account = '1910'; Amount = 5000 }, @{ Account = '2510'; Amount = -5000 })
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-04-01' -Description 'Leverantörsskuld' -Rows @(
                @{ Account = '1910'; Amount = 3000 }, @{ Account = '2440'; Amount = -3000 })
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-05-01' -Description 'Balanserat' -Rows @(
                @{ Account = '1910'; Amount = 7000 }, @{ Account = '2091'; Amount = -7000 })
        }

        It 'Should not add breakdown rows without -Detailed' {
            $Result = @(Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear)
            $Result.Count | Should -Be 12
            ($Result | Where-Object { $_.Group -eq 'ShareCapital' }) | Should -BeNullOrEmpty
        }

        It 'Should split equity into share capital and retained earnings' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear -Detailed
            ($Result | Where-Object { $_.Group -eq 'ShareCapital' }).Amount | Should -Be -100000
            ($Result | Where-Object { $_.Group -eq 'RetainedEarnings' }).Amount | Should -Be -7000
        }

        It 'Should report current tax liabilities on their own line' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear -Detailed
            ($Result | Where-Object { $_.Group -eq 'CurrentTaxLiabilities' }).Amount | Should -Be -5000
            ($Result | Where-Object { $_.Group -eq 'OtherShortTermLiabilities' }).Amount | Should -Be -3000
        }

        It 'Should keep breakdown lines consistent with their aggregate' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear -Detailed
            $tax = ($Result | Where-Object { $_.Group -eq 'CurrentTaxLiabilities' }).Amount
            $other = ($Result | Where-Object { $_.Group -eq 'OtherShortTermLiabilities' }).Amount
            $aggregate = ($Result | Where-Object { $_.Group -eq 'ShortTermLiabilities' }).Amount
            ($tax + $other) | Should -Be $aggregate
        }
    }
}
