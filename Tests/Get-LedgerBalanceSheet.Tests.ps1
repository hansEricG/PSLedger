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

        It 'Should return 2 result rows (Assets and EquityAndLiabilities)' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result.Count | Should -Be 2
        }

        It 'Should show total assets' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Assets = $Result | Where-Object { $_.Group -eq 'Assets' }

            $Assets.Amount | Should -Be 30000
        }

        It 'Should show equity and liabilities' {
            $Result = Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear
            $EqLiab = $Result | Where-Object { $_.Group -eq 'EquityAndLiabilities' }

            $EqLiab.Amount | Should -Be 10000
        }

        It 'Should return empty if no entries exist' {
            $EmptyJournal = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $EmptyJournal -Name 'Tom AB'
            New-LedgerFiscalYear -JournalPath $EmptyJournal -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Result = Get-LedgerBalanceSheet -JournalPath $EmptyJournal -FiscalYear '2024-01_2024-12'

            $Result | Should -BeNullOrEmpty
        }
    }
}
