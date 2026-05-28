BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerAccount' {
    BeforeAll {
        $CommandName = 'Get-LedgerAccount'
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

        It 'Should have an optional AccountNumber parameter of type String' {
            $Param = $Command.Parameters['AccountNumber']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2440' -AccountName 'Leverantörsskulder'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
        }

        It 'Should return all accounts when no filter is specified' {
            $Result = Get-LedgerAccount -JournalPath $JournalPath

            $Result.Count | Should -Be 3
        }

        It 'Should return objects with AccountNumber and AccountName properties' {
            $Result = Get-LedgerAccount -JournalPath $JournalPath

            $Result[0].AccountNumber | Should -Be '1910'
            $Result[0].AccountName | Should -Be 'Kassa'
        }

        It 'Should return a single account when AccountNumber is specified' {
            $Result = Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '2440'

            $Result.AccountNumber | Should -Be '2440'
            $Result.AccountName | Should -Be 'Leverantörsskulder'
        }

        It 'Should return nothing if AccountNumber does not exist' {
            $Result = Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '9999'

            $Result | Should -BeNullOrEmpty
        }

        It 'Should return empty collection if accounts.txt does not exist' {
            $EmptyJournal = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $EmptyJournal -Name 'Tom AB'

            $Result = Get-LedgerAccount -JournalPath $EmptyJournal

            $Result | Should -BeNullOrEmpty
        }

        It 'Should throw if journal path does not exist' {
            { Get-LedgerAccount -JournalPath 'C:\nonexistent' } | Should -Throw
        }
    }
}
