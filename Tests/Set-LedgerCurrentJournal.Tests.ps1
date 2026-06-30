BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Set-LedgerCurrentJournal' {
    BeforeAll {
        $CommandName = 'Set-LedgerCurrentJournal'
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
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'MinFirma.ledger'
            New-Item -Path $journalDir -ItemType Directory -Force | Out-Null
            "Name: MinFirma AB`nOrgNumber: 556123-4567" |
                Set-Content (Join-Path $journalDir 'journal.txt') -Encoding UTF8
            $env:PSLEDGER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        AfterEach {
            Clear-LedgerCurrentJournal
        }

        It 'Should set the current journal' {
            Set-LedgerCurrentJournal -Path $journalDir
            $journal = Get-LedgerCurrentJournal
            $journal.Name | Should -Be 'MinFirma AB'
        }

        It 'Should throw when path does not exist' {
            { Set-LedgerCurrentJournal -Path (Join-Path $TestDrive 'NoSuch.ledger') } |
                Should -Throw '*not found*'
        }

        It 'Should throw when path is not a valid journal' {
            $badDir = Join-Path $TestDrive 'NotAJournal'
            New-Item -Path $badDir -ItemType Directory -Force | Out-Null
            { Set-LedgerCurrentJournal -Path $badDir } |
                Should -Throw '*journal.txt*'
        }

        It 'Should allow Get-LedgerCurrentJournal after set' {
            Set-LedgerCurrentJournal -Path $journalDir
            { Get-LedgerCurrentJournal } | Should -Not -Throw
        }
    }
}

Describe 'Clear-LedgerCurrentJournal' {
    BeforeAll {
        $CommandName = 'Clear-LedgerCurrentJournal'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'MinFirma.ledger'
            New-Item -Path $journalDir -ItemType Directory -Force | Out-Null
            "Name: MinFirma AB`nOrgNumber: 556123-4567" |
                Set-Content (Join-Path $journalDir 'journal.txt') -Encoding UTF8
            $env:PSLEDGER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        It 'Should clear current journal' {
            Set-LedgerCurrentJournal -Path $journalDir
            Clear-LedgerCurrentJournal
            { Get-LedgerCurrentJournal } | Should -Throw '*No current journal*'
        }

        It 'Should not throw when no journal is set' {
            { Clear-LedgerCurrentJournal } | Should -Not -Throw
        }
    }
}
