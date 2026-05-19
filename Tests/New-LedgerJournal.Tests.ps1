BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    Import-Module TDDSeams -Force
}

Describe 'New-LedgerJournal' {
    BeforeAll {
        $CommandName = 'New-LedgerJournal'
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

        It 'Should have a mandatory Name parameter of type String' {
            $Param = $Command.Parameters['Name']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have an optional OrgNumber parameter of type String' {
            $Param = $Command.Parameters['OrgNumber']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
        }

        It 'Should create a journal directory at the specified path' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'

            Test-Path $JournalPath -PathType Container | Should -BeTrue
        }

        It 'Should create a journal.txt file inside the directory' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'

            $JournalFile = Join-Path $JournalPath 'journal.txt'
            Test-Path $JournalFile | Should -BeTrue
        }

        It 'Should write company name to journal.txt' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'

            $Content = Get-Content (Join-Path $JournalPath 'journal.txt') -Raw
            $Content | Should -Match 'Testföretaget AB'
        }

        It 'Should write org number to journal.txt when provided' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB' -OrgNumber '556677-8899'

            $Content = Get-Content (Join-Path $JournalPath 'journal.txt') -Raw
            $Content | Should -Match '556677-8899'
        }

        It 'Should throw if the journal directory already exists' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'

            { New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB' } | Should -Throw
        }
    }
}
