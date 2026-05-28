BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Set-LedgerJournal' {
    BeforeAll {
        $CommandName = 'Set-LedgerJournal'
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
            Clear-LedgerJournal
        }

        It 'Should set the current journal' {
            Set-LedgerJournal -Path $journalDir
            $journal = Get-LedgerJournal -Current
            $journal.Name | Should -Be 'MinFirma AB'
        }

        It 'Should throw when path does not exist' {
            { Set-LedgerJournal -Path (Join-Path $TestDrive 'NoSuch.ledger') } |
                Should -Throw '*not found*'
        }

        It 'Should throw when path is not a valid journal' {
            $badDir = Join-Path $TestDrive 'NotAJournal'
            New-Item -Path $badDir -ItemType Directory -Force | Out-Null
            { Set-LedgerJournal -Path $badDir } |
                Should -Throw '*journal.txt*'
        }

        It 'Should allow Get-LedgerJournal -Current after set' {
            Set-LedgerJournal -Path $journalDir
            { Get-LedgerJournal -Current } | Should -Not -Throw
        }
    }
}

Describe 'Clear-LedgerJournal' {
    BeforeAll {
        $CommandName = 'Clear-LedgerJournal'
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
            Set-LedgerJournal -Path $journalDir
            Clear-LedgerJournal
            { Get-LedgerJournal -Current } | Should -Throw '*No current journal*'
        }

        It 'Should not throw when no journal is set' {
            { Clear-LedgerJournal } | Should -Not -Throw
        }
    }
}

Describe 'Get-LedgerJournal -Current' {
    BeforeAll {
        $env:PSLEDGER_EXTENSIONS = $null
        Import-Module $ModulePath -Force
    }

    Context 'Behavior' {
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'Firma.ledger'
            New-Item -Path $journalDir -ItemType Directory -Force | Out-Null
            "Name: Firma AB`nOrgNumber: 559988-7766" |
                Set-Content (Join-Path $journalDir 'journal.txt') -Encoding UTF8
        }

        AfterEach {
            Clear-LedgerJournal
        }

        It 'Should throw when no current journal is set' {
            { Get-LedgerJournal -Current } | Should -Throw '*No current journal*'
        }

        It 'Should return journal info when current is set' {
            Set-LedgerJournal -Path $journalDir
            $result = Get-LedgerJournal -Current
            $result.Name | Should -Be 'Firma AB'
            $result.OrgNumber | Should -Be '559988-7766'
        }

        It 'Path parameter set still works as before' {
            $result = Get-LedgerJournal -Path $journalDir
            $result.Name | Should -Be 'Firma AB'
        }
    }
}
