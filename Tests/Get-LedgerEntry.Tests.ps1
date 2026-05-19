BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerEntry' {
    BeforeAll {
        $CommandName = 'Get-LedgerEntry'
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

        It 'Should have an optional VerificationNumber parameter of type Int32' {
            $Param = $Command.Parameters['VerificationNumber']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'Int32'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'

            $Rows1 = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )
            $Rows2 = @(
                @{ Account = '1910'; Amount = 500 }
                @{ Account = '2440'; Amount = -500 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Försäljning kontant' -Rows $Rows1
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-02-01' -Description 'Betalning leverantör' -Rows $Rows2
        }

        It 'Should return all entries when no filter is specified' {
            $Result = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result.Count | Should -Be 2
        }

        It 'Should return objects with VerificationNumber, Date, Description, and Rows' {
            $Result = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result[0].VerificationNumber | Should -Be 1
            $Result[0].Date | Should -Be '2024-01-15'
            $Result[0].Description | Should -Be 'Försäljning kontant'
            $Result[0].Rows.Count | Should -Be 2
        }

        It 'Should return rows with Account and Amount properties' {
            $Result = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result[0].Rows[0].Account | Should -Be '1910'
            $Result[0].Rows[0].Amount | Should -Be 1000
        }

        It 'Should filter by VerificationNumber' {
            $Result = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 2

            $Result.VerificationNumber | Should -Be 2
            $Result.Description | Should -Be 'Betalning leverantör'
        }

        It 'Should return nothing if VerificationNumber does not exist' {
            $Result = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 99

            $Result | Should -BeNullOrEmpty
        }

        It 'Should return empty if no entries exist' {
            $EmptyJournal = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $EmptyJournal -Name 'Tom AB'
            New-LedgerFiscalYear -JournalPath $EmptyJournal -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Result = Get-LedgerEntry -JournalPath $EmptyJournal -FiscalYear '2024-01_2024-12'

            $Result | Should -BeNullOrEmpty
        }

        It 'Should throw if fiscal year directory does not exist' {
            { Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2099-01_2099-12' } | Should -Throw
        }
    }
}
