BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerReversal' {
    BeforeAll {
        $CommandName = 'Add-LedgerReversal'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory FiscalYear parameter of type String' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory VerificationNumber parameter of type Int32' {
            $Param = $Command.Parameters['VerificationNumber']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'Int32'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have an optional Date parameter of type DateTime' {
            $Param = $Command.Parameters['Date']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'DateTime'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Mini'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'

            $Rows = @(
                @{ Account = '1910'; Amount = 5000 }
                @{ Account = '3010'; Amount = -5000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-15' -Description 'Felaktig post' -Rows $Rows
        }

        It 'Should create a new verification' {
            Add-LedgerReversal -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1 -Date '2024-03-16'

            $All = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear
            $All.Count | Should -Be 2
        }

        It 'Should negate the amounts from the original' {
            Add-LedgerReversal -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1 -Date '2024-03-16'

            $Reversal = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 2
            $Kassa = $Reversal.Rows | Where-Object { $_.Account -eq '1910' }
            $Kassa.Amount | Should -Be -5000

            $Sales = $Reversal.Rows | Where-Object { $_.Account -eq '3010' }
            $Sales.Amount | Should -Be 5000
        }

        It 'Should include a reference to the original in the description' {
            Add-LedgerReversal -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1 -Date '2024-03-16'

            $Reversal = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 2
            $Reversal.Description | Should -Match 'Rättelse ver 1'
            $Reversal.Description | Should -Match 'Felaktig post'
        }

        It 'Should use the specified date' {
            Add-LedgerReversal -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1 -Date '2024-03-20'

            $Reversal = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 2
            $Reversal.Date | Should -Be '2024-03-20'
        }

        It 'Should result in zero net balance after reversal' {
            Add-LedgerReversal -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1 -Date '2024-03-16'

            $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Balance | ForEach-Object { $_.Balance | Should -Be 0 }
        }

        It 'Should throw if verification does not exist' {
            { Add-LedgerReversal -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 99 -Date '2024-03-16' } |
                Should -Throw '*not found*'
        }
    }
}
