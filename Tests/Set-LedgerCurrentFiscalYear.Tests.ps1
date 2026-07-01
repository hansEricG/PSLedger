BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Set-LedgerCurrentFiscalYear' {
    BeforeAll {
        $CommandName = 'Set-LedgerCurrentFiscalYear'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory FiscalYear parameter of type String' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have an optional JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $false
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'MinFirma.ledger'
            New-Item -Path $journalDir -ItemType Directory -Force | Out-Null
            "Name: MinFirma AB`nOrgNumber: 556123-4567" |
                Set-Content (Join-Path $journalDir 'journal.txt') -Encoding UTF8
            New-Item -Path (Join-Path $journalDir '2024-01_2024-12') -ItemType Directory -Force | Out-Null
            $env:PSLEDGER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        AfterEach {
            Clear-LedgerCurrentJournal
        }

        It 'Should set the current fiscal year using the current journal' {
            Set-LedgerCurrentJournal -Path $journalDir
            Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12'
            Get-LedgerCurrentFiscalYear | Should -Be '2024-01_2024-12'
        }

        It 'Should set the current fiscal year using an explicit JournalPath' {
            Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12' -JournalPath $journalDir
            Get-LedgerCurrentFiscalYear | Should -Be '2024-01_2024-12'
        }

        It 'Should throw when the fiscal year does not exist' {
            Set-LedgerCurrentJournal -Path $journalDir
            { Set-LedgerCurrentFiscalYear -FiscalYear '2099-01_2099-12' } |
                Should -Throw '*not found*'
        }

        It 'Should throw when no journal is available' {
            { Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12' } |
                Should -Throw '*No journal specified*'
        }

        It 'Should be cleared when switching journals' {
            $otherDir = Join-Path $TestDrive 'AnnatBolag.ledger'
            New-Item -Path $otherDir -ItemType Directory -Force | Out-Null
            "Name: Annat AB`nOrgNumber: 559000-0000" |
                Set-Content (Join-Path $otherDir 'journal.txt') -Encoding UTF8

            Set-LedgerCurrentJournal -Path $journalDir
            Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12'
            Set-LedgerCurrentJournal -Path $otherDir
            { Get-LedgerCurrentFiscalYear } | Should -Throw '*No current fiscal year*'
        }
    }
}

Describe 'Get-LedgerCurrentFiscalYear' {
    BeforeAll {
        $CommandName = 'Get-LedgerCurrentFiscalYear'
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
            $journalDir = Join-Path $TestDrive 'Firma.ledger'
            New-Item -Path $journalDir -ItemType Directory -Force | Out-Null
            "Name: Firma AB`nOrgNumber: 559988-7766" |
                Set-Content (Join-Path $journalDir 'journal.txt') -Encoding UTF8
            New-Item -Path (Join-Path $journalDir '2024-01_2024-12') -ItemType Directory -Force | Out-Null
            $env:PSLEDGER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        AfterEach {
            Clear-LedgerCurrentJournal
        }

        It 'Should throw when no current fiscal year is set' {
            { Get-LedgerCurrentFiscalYear } | Should -Throw '*No current fiscal year*'
        }

        It 'Should return the fiscal year when set' {
            Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12' -JournalPath $journalDir
            Get-LedgerCurrentFiscalYear | Should -Be '2024-01_2024-12'
        }
    }
}

Describe 'Clear-LedgerCurrentFiscalYear' {
    BeforeAll {
        $CommandName = 'Clear-LedgerCurrentFiscalYear'
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
            $journalDir = Join-Path $TestDrive 'Firma.ledger'
            New-Item -Path $journalDir -ItemType Directory -Force | Out-Null
            "Name: Firma AB`nOrgNumber: 559988-7766" |
                Set-Content (Join-Path $journalDir 'journal.txt') -Encoding UTF8
            New-Item -Path (Join-Path $journalDir '2024-01_2024-12') -ItemType Directory -Force | Out-Null
            $env:PSLEDGER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        AfterEach {
            Clear-LedgerCurrentJournal
        }

        It 'Should clear the current fiscal year' {
            Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12' -JournalPath $journalDir
            Clear-LedgerCurrentFiscalYear
            { Get-LedgerCurrentFiscalYear } | Should -Throw '*No current fiscal year*'
        }

        It 'Should not throw when no fiscal year is set' {
            { Clear-LedgerCurrentFiscalYear } | Should -Not -Throw
        }
    }
}
