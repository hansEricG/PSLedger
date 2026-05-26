BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Close-LedgerFiscalYear' {
    BeforeAll {
        $CommandName = 'Close-LedgerFiscalYear'
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
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'
        }

        It 'Should set fiscal year status to Closed' {
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $YearFile = Join-Path $JournalPath $FiscalYear 'year.txt'
            $Content = Get-Content $YearFile -Raw
            $Content | Should -Match 'Status: Closed'
        }

        It 'Should preserve StartDate and EndDate in year.txt' {
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $YearFile = Join-Path $JournalPath $FiscalYear 'year.txt'
            $Content = Get-Content $YearFile -Raw
            $Content | Should -Match 'StartDate: 2024-01-01'
            $Content | Should -Match 'EndDate: 2024-12-31'
        }

        It 'Should prevent Add-LedgerEntry on a closed fiscal year' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Rows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )

            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-06-01' -Description 'Ska inte gå' -Rows $Rows } |
                Should -Throw '*Closed*'
        }

        It 'Should throw if fiscal year does not exist' {
            { Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear '2099-01_2099-12' } | Should -Throw
        }

        It 'Should throw if fiscal year is already closed' {
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            { Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear } | Should -Throw '*already closed*'
        }

        It 'Should be reflected in Get-LedgerFiscalYear output' {
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result = Get-LedgerFiscalYear -JournalPath $JournalPath
            $Result.Status | Should -Be 'Closed'
        }
    }
}
