BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
}

Describe 'Journal schema versioning' {
    BeforeEach {
        $JournalName = [System.IO.Path]::GetRandomFileName()
        $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
    }

    Context 'New journals' {
        It 'Should write a SchemaVersion field to journal.txt' {
            New-LedgerJournal -Path $JournalPath -Name 'Nytt AB'

            $content = Get-Content (Join-Path $JournalPath 'journal.txt')
            $content | Should -Contain 'SchemaVersion: 2'
        }

        It 'Should allow writing commands on a current-version journal' {
            New-LedgerJournal -Path $JournalPath -Name 'Nytt AB'

            { Add-LedgerAccount -JournalPath $JournalPath -AccountNumber 1910 -AccountName 'Kassa' } |
                Should -Not -Throw
        }
    }

    Context 'Legacy journals (no SchemaVersion field)' {
        BeforeEach {
            New-Item -ItemType Directory -Path $JournalPath | Out-Null
            Set-Content -Path (Join-Path $JournalPath 'journal.txt') -Value @('Name: Gammal AB') -Encoding UTF8
        }

        It 'Should throw from a writing command and name the migration command' {
            $err = $null
            try {
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber 1910 -AccountName 'Kassa' -ErrorAction Stop
            }
            catch {
                $err = $_.Exception.Message
            }

            $err | Should -Not -BeNullOrEmpty
            $err | Should -Match 'schema version 1'
            $err | Should -Match 'Convert-LedgerOpeningBalance'
        }

        It 'Should only warn (not throw) from a reading command' {
            New-Item -ItemType Directory -Path (Join-Path $JournalPath '2024-01_2024-12') | Out-Null
            Set-Content -Path (Join-Path $JournalPath '2024-01_2024-12\year.txt') `
                -Value @('StartDate: 2024-01-01', 'EndDate: 2024-12-31', 'Status: Open') -Encoding UTF8

            $warnings = $null
            Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' `
                -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

            ($warnings -join "`n") | Should -Match 'Convert-LedgerOpeningBalance'
        }
    }

    Context 'Migration bumps the schema version' {
        It 'Should mark a legacy journal as current and unblock writing' {
            New-Item -ItemType Directory -Path $JournalPath | Out-Null
            Set-Content -Path (Join-Path $JournalPath 'journal.txt') -Value @('Name: Gammal AB') -Encoding UTF8

            Convert-LedgerOpeningBalance -JournalPath $JournalPath | Out-Null

            (Get-LedgerJournal -Path $JournalPath).SchemaVersion | Should -Be 2
            { Add-LedgerAccount -JournalPath $JournalPath -AccountNumber 1910 -AccountName 'Kassa' } |
                Should -Not -Throw
        }

        It 'Should not change journal.txt under -WhatIf' {
            New-Item -ItemType Directory -Path $JournalPath | Out-Null
            Set-Content -Path (Join-Path $JournalPath 'journal.txt') -Value @('Name: Gammal AB') -Encoding UTF8

            Convert-LedgerOpeningBalance -JournalPath $JournalPath -WhatIf | Out-Null

            (Get-LedgerJournal -Path $JournalPath).SchemaVersion | Should -Be 1
        }
    }
}
