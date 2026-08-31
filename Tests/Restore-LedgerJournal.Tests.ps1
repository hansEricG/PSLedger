BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Restore-LedgerJournal' {
    BeforeAll {
        $CommandName = 'Restore-LedgerJournal'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should support ShouldProcess (WhatIf/Confirm)' {
            $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
            $Command.Parameters.ContainsKey('Confirm') | Should -BeTrue
        }

        It 'Should have a mandatory ArchivePath parameter of type String' {
            $Param = $Command.Parameters['ArchivePath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have an optional DestinationPath parameter of type String' {
            $Param = $Command.Parameters['DestinationPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have a Force switch parameter' {
            $Param = $Command.Parameters['Force']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB' -OrgNumber '556677-8899'
            Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Mini'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -Date '2024-06-01' -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 50000 }
                @{ Account = '3010'; Amount = -50000 }
            )

            $BackupDir = Join-Path $TestDrive 'backups'
            $Archive = Backup-LedgerJournal -JournalPath $JournalPath -DestinationPath $BackupDir
            $ArchivePath = $Archive.FullName
        }

        It 'Should restore the journal folder into the destination' {
            $Dest = Join-Path $TestDrive 'restore1'
            Restore-LedgerJournal -ArchivePath $ArchivePath -DestinationPath $Dest | Out-Null

            $Restored = Join-Path $Dest "$JournalName.ledger"
            Test-Path (Join-Path $Restored 'journal.txt') | Should -BeTrue
        }

        It 'Should restore all fiscal year data' {
            $Dest = Join-Path $TestDrive 'restore2'
            Restore-LedgerJournal -ArchivePath $ArchivePath -DestinationPath $Dest | Out-Null

            $Restored = Join-Path $Dest "$JournalName.ledger"
            $Entries = @(Get-LedgerEntry -JournalPath $Restored -FiscalYear '2024-01_2024-12')
            $Entries.Count | Should -Be 1
        }

        It 'Should return the restored journal metadata' {
            $Dest = Join-Path $TestDrive 'restore3'
            $Result = Restore-LedgerJournal -ArchivePath $ArchivePath -DestinationPath $Dest

            $Result | Should -Not -BeNullOrEmpty
            $Result.Name | Should -Be 'Testföretaget AB'
            $Result.OrgNumber | Should -Be '556677-8899'
        }

        It 'Should throw if the target journal already exists without -Force' {
            $Dest = Join-Path $TestDrive 'restore4'
            Restore-LedgerJournal -ArchivePath $ArchivePath -DestinationPath $Dest | Out-Null

            { Restore-LedgerJournal -ArchivePath $ArchivePath -DestinationPath $Dest } |
                Should -Throw '*already exists*'
        }

        It 'Should overwrite an existing journal when -Force is used' {
            $Dest = Join-Path $TestDrive 'restore5'
            Restore-LedgerJournal -ArchivePath $ArchivePath -DestinationPath $Dest | Out-Null

            # Add a stray file that should be gone after a forced restore
            $Restored = Join-Path $Dest "$JournalName.ledger"
            Set-Content -Path (Join-Path $Restored 'stray.txt') -Value 'x'

            Restore-LedgerJournal -ArchivePath $ArchivePath -DestinationPath $Dest -Force | Out-Null

            Test-Path (Join-Path $Restored 'stray.txt') | Should -BeFalse
            Test-Path (Join-Path $Restored 'journal.txt') | Should -BeTrue
        }

        It 'Should restore into the current directory by default' {
            $Dest = Join-Path $TestDrive 'restore6'
            New-Item -ItemType Directory -Path $Dest -Force | Out-Null
            Push-Location $Dest
            try {
                Restore-LedgerJournal -ArchivePath $ArchivePath | Out-Null
                Test-Path (Join-Path $Dest "$JournalName.ledger" 'journal.txt') | Should -BeTrue
            }
            finally {
                Pop-Location
            }
        }

        It 'Should not extract anything when -WhatIf is used' {
            $Dest = Join-Path $TestDrive 'restore7'
            Restore-LedgerJournal -ArchivePath $ArchivePath -DestinationPath $Dest -WhatIf | Out-Null

            Test-Path (Join-Path $Dest "$JournalName.ledger") | Should -BeFalse
        }

        It 'Should throw if the archive does not exist' {
            { Restore-LedgerJournal -ArchivePath (Join-Path $TestDrive 'nope.zip') } |
                Should -Throw '*not found*'
        }

        It 'Should throw if the archive is not a valid journal backup' {
            $Bad = Join-Path $TestDrive 'bad.zip'
            $Loose = Join-Path $TestDrive 'loose'
            New-Item -ItemType Directory -Path $Loose -Force | Out-Null
            Set-Content -Path (Join-Path $Loose 'readme.txt') -Value 'not a journal'
            Compress-Archive -Path (Join-Path $Loose '*') -DestinationPath $Bad -Force

            { Restore-LedgerJournal -ArchivePath $Bad -DestinationPath (Join-Path $TestDrive 'restore8') } |
                Should -Throw '*Invalid backup archive*'
        }

        It 'Should reject an archive whose entries escape the destination (zip-slip)' {
            $Bad = Join-Path $TestDrive 'zipslip.zip'
            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $fs = [System.IO.File]::Open($Bad, [System.IO.FileMode]::Create)
            try {
                $zip = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
                try {
                    $e1 = $zip.CreateEntry('EvilJournal.ledger/journal.txt')
                    $w1 = [System.IO.StreamWriter]::new($e1.Open())
                    $w1.Write('Name: Evil'); $w1.Dispose()
                    $e2 = $zip.CreateEntry('EvilJournal.ledger/../../evil.txt')
                    $w2 = [System.IO.StreamWriter]::new($e2.Open())
                    $w2.Write('pwned'); $w2.Dispose()
                }
                finally { $zip.Dispose() }
            }
            finally { $fs.Dispose() }

            { Restore-LedgerJournal -ArchivePath $Bad -DestinationPath (Join-Path $TestDrive 'restore-slip') } |
                Should -Throw '*Invalid backup archive*'
        }
    }
}
