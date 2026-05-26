BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerAccount' {
    BeforeAll {
        $CommandName = 'Add-LedgerAccount'
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

        It 'Should have a mandatory AccountNumber parameter of type String' {
            $Param = $Command.Parameters['AccountNumber']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory AccountName parameter of type String' {
            $Param = $Command.Parameters['AccountName']
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
        }

        It 'Should create accounts.txt if it does not exist' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'

            $KontoplanFile = Join-Path $JournalPath 'accounts.txt'
            Test-Path $KontoplanFile | Should -BeTrue
        }

        It 'Should add the account to accounts.txt' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'

            $Content = Get-Content (Join-Path $JournalPath 'accounts.txt') -Raw
            $Content | Should -Match '1910'
            $Content | Should -Match 'Kassa'
        }

        It 'Should store account number and name on the same line' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'

            $Lines = Get-Content (Join-Path $JournalPath 'accounts.txt')
            $Lines | Where-Object { $_ -match '^1910\s+Kassa$' } | Should -Not -BeNullOrEmpty
        }

        It 'Should allow adding multiple accounts' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2440' -AccountName 'Leverantörsskulder'

            $Lines = Get-Content (Join-Path $JournalPath 'accounts.txt')
            ($Lines | Where-Object { $_ -match '^\d{4}\s+' }).Count | Should -Be 2
        }

        It 'Should throw if account number already exists' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'

            { Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa igen' } | Should -Throw
        }

        It 'Should throw if journal path does not exist' {
            { Add-LedgerAccount -JournalPath 'C:\nonexistent' -AccountNumber '1910' -AccountName 'Kassa' } | Should -Throw
        }
    }
}
