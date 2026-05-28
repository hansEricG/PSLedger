BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerIncomeStatement' {
    BeforeAll {
        $CommandName = 'Get-LedgerIncomeStatement'
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

        It 'Should have a mandatory FiscalYear parameter of type String' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
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

            # Revenue: 50000 sales
            $Rows1 = @(
                @{ Account = '1910'; Amount = 50000 }
                @{ Account = '3010'; Amount = -50000 }
            )
            # Cost of goods: 20000
            $Rows2 = @(
                @{ Account = '4010'; Amount = 20000 }
                @{ Account = '2440'; Amount = -20000 }
            )
            # Operating expense: rent 10000
            $Rows3 = @(
                @{ Account = '5010'; Amount = 10000 }
                @{ Account = '1910'; Amount = -10000 }
            )
            # Financial: interest income 500
            $Rows4 = @(
                @{ Account = '1910'; Amount = 500 }
                @{ Account = '8310'; Amount = -500 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-02-01' -Description 'Försäljning' -Rows $Rows1
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-02-15' -Description 'Inköp varor' -Rows $Rows2
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-01' -Description 'Hyra' -Rows $Rows3
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-15' -Description 'Ränteintäkt' -Rows $Rows4
        }

        It 'Should return 7 result rows' {
            $Result = Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result.Count | Should -Be 7
        }

        It 'Should show revenue as positive amount' {
            $Result = Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Revenue = $Result | Where-Object { $_.Group -eq 'Revenue' }

            $Revenue.Amount | Should -Be 50000
        }

        It 'Should show cost of goods as negative amount' {
            $Result = Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $FiscalYear
            $CoG = $Result | Where-Object { $_.Group -eq 'CostOfGoods' }

            $CoG.Amount | Should -Be -20000
        }

        It 'Should calculate gross profit correctly' {
            $Result = Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $FiscalYear
            $GP = $Result | Where-Object { $_.Group -eq 'GrossProfit' }

            $GP.Amount | Should -Be 30000
        }

        It 'Should show operating expenses as negative' {
            $Result = Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $FiscalYear
            $OpEx = $Result | Where-Object { $_.Group -eq 'OperatingExpenses' }

            $OpEx.Amount | Should -Be -10000
        }

        It 'Should calculate operating result correctly' {
            $Result = Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $FiscalYear
            $OpRes = $Result | Where-Object { $_.Group -eq 'OperatingResult' }

            $OpRes.Amount | Should -Be 20000
        }

        It 'Should show financial items' {
            $Result = Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Fin = $Result | Where-Object { $_.Group -eq 'Financial' }

            $Fin.Amount | Should -Be 500
        }

        It 'Should calculate net result correctly' {
            $Result = Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Net = $Result | Where-Object { $_.Group -eq 'NetResult' }

            $Net.Amount | Should -Be 20500
        }

        It 'Should return empty if no entries exist' {
            $EmptyJournal = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $EmptyJournal -Name 'Tom AB'
            New-LedgerFiscalYear -JournalPath $EmptyJournal -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Result = Get-LedgerIncomeStatement -JournalPath $EmptyJournal -FiscalYear '2024-01_2024-12'

            $Result | Should -BeNullOrEmpty
        }
    }
}
