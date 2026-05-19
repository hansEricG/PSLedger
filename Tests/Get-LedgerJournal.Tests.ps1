BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerJournal' {
    BeforeAll {
        $CommandName = 'Get-LedgerJournal'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory Path parameter of type String' {
            $Param = $Command.Parameters['Path']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB' -OrgNumber '556677-8899'
        }

        It 'Should return an object with the company Name' {
            $Result = Get-LedgerJournal -Path $JournalPath

            $Result.Name | Should -Be 'Testföretaget AB'
        }

        It 'Should return an object with the OrgNumber' {
            $Result = Get-LedgerJournal -Path $JournalPath

            $Result.OrgNumber | Should -Be '556677-8899'
        }

        It 'Should return an object with the Path' {
            $Result = Get-LedgerJournal -Path $JournalPath

            $Result.Path | Should -Be $JournalPath
        }

        It 'Should throw if the path does not exist' {
            { Get-LedgerJournal -Path 'C:\nonexistent\path.ledger' } | Should -Throw
        }

        It 'Should throw if journal.txt is missing' {
            $BadPath = Join-Path $TestDrive 'empty.ledger'
            New-Item -ItemType Directory -Path $BadPath | Out-Null

            { Get-LedgerJournal -Path $BadPath } | Should -Throw
        }
    }
}
