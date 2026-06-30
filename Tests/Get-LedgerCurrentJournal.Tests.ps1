BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerCurrentJournal' {
    BeforeAll {
        $CommandName = 'Get-LedgerCurrentJournal'
        $Command = Get-Command -Name $CommandName
        $env:PSLEDGER_EXTENSIONS = $null
        Import-Module $ModulePath -Force
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
        }

        AfterEach {
            Clear-LedgerCurrentJournal
        }

        It 'Should throw when no current journal is set' {
            { Get-LedgerCurrentJournal } | Should -Throw '*No current journal*'
        }

        It 'Should return journal info when current is set' {
            Set-LedgerCurrentJournal -Path $journalDir
            $result = Get-LedgerCurrentJournal
            $result.Name | Should -Be 'Firma AB'
            $result.OrgNumber | Should -Be '559988-7766'
        }
    }
}
