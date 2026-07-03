BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Backup-LedgerJournal' {
    BeforeAll {
        $CommandName = 'Backup-LedgerJournal'
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

        It 'Should have an optional JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have an optional DestinationPath parameter of type String' {
            $Param = $Command.Parameters['DestinationPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have an optional KeepCount parameter of type Int32' {
            $Param = $Command.Parameters['KeepCount']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'Int32'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Mini'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
        }

        It 'Should create a backups directory next to the journal by default' {
            Backup-LedgerJournal -JournalPath $JournalPath | Out-Null

            $BackupDir = Join-Path $TestDrive 'backups'
            Test-Path $BackupDir -PathType Container | Should -BeTrue
        }

        It 'Should create a timestamped zip archive' {
            Backup-LedgerJournal -JournalPath $JournalPath | Out-Null

            $BackupDir = Join-Path $TestDrive 'backups'
            $Archives = @(Get-ChildItem -Path $BackupDir -Filter "$JournalName*.zip")
            $Archives.Count | Should -Be 1
            $Archives[0].Name | Should -Match '_\d{4}-\d{2}-\d{2}_\d{6}\.zip$'
        }

        It 'Should return the created backup file' {
            $Result = Backup-LedgerJournal -JournalPath $JournalPath
            $Result | Should -Not -BeNullOrEmpty
            $Result.Extension | Should -Be '.zip'
            Test-Path $Result.FullName | Should -BeTrue
        }

        It 'Should include the journal contents in the archive' {
            $Result = Backup-LedgerJournal -JournalPath $JournalPath

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $Zip = [System.IO.Compression.ZipFile]::OpenRead($Result.FullName)
            try {
                $Entries = $Zip.Entries.FullName
                $Entries | Where-Object { $_ -like '*journal.txt' } | Should -Not -BeNullOrEmpty
                $Entries | Where-Object { $_ -like '*accounts.txt' } | Should -Not -BeNullOrEmpty
            }
            finally {
                $Zip.Dispose()
            }
        }

        It 'Should write to a custom DestinationPath' {
            $Dest = Join-Path $TestDrive 'MyBackups'
            Backup-LedgerJournal -JournalPath $JournalPath -DestinationPath $Dest | Out-Null

            @(Get-ChildItem -Path $Dest -Filter '*.zip').Count | Should -Be 1
        }

        It 'Should keep only the most recent KeepCount backups' {
            $Dest = Join-Path $TestDrive 'Retention'
            New-Item -ItemType Directory -Path $Dest -Force | Out-Null

            $BaseName = $JournalName
            # Seed six older backups with sortable timestamps
            1..6 | ForEach-Object {
                $Name = "${BaseName}_2020-01-0${_}_120000.zip"
                Set-Content -Path (Join-Path $Dest $Name) -Value 'old'
            }

            Backup-LedgerJournal -JournalPath $JournalPath -DestinationPath $Dest -KeepCount 5 | Out-Null

            $Archives = @(Get-ChildItem -Path $Dest -Filter '*.zip')
            $Archives.Count | Should -Be 5
        }

        It 'Should keep all backups when KeepCount is 0' {
            $Dest = Join-Path $TestDrive 'KeepAll'
            New-Item -ItemType Directory -Path $Dest -Force | Out-Null

            $BaseName = $JournalName
            1..3 | ForEach-Object {
                $Name = "${BaseName}_2020-01-0${_}_120000.zip"
                Set-Content -Path (Join-Path $Dest $Name) -Value 'old'
            }

            Backup-LedgerJournal -JournalPath $JournalPath -DestinationPath $Dest -KeepCount 0 | Out-Null

            @(Get-ChildItem -Path $Dest -Filter '*.zip').Count | Should -Be 4
        }

        It 'Should not remove backups belonging to a different journal' {
            $Dest = Join-Path $TestDrive 'Shared'
            New-Item -ItemType Directory -Path $Dest -Force | Out-Null

            1..6 | ForEach-Object {
                $Name = "OtherJournal_2020-01-0${_}_120000.zip"
                Set-Content -Path (Join-Path $Dest $Name) -Value 'other'
            }

            Backup-LedgerJournal -JournalPath $JournalPath -DestinationPath $Dest -KeepCount 5 | Out-Null

            @(Get-ChildItem -Path $Dest -Filter 'OtherJournal_*.zip').Count | Should -Be 6
        }

        It 'Should not create an archive when -WhatIf is used' {
            $Dest = Join-Path $TestDrive 'WhatIf'
            Backup-LedgerJournal -JournalPath $JournalPath -DestinationPath $Dest -WhatIf | Out-Null

            Test-Path (Join-Path $Dest '*.zip') | Should -BeFalse
        }

        It 'Should throw if the journal does not exist' {
            { Backup-LedgerJournal -JournalPath (Join-Path $TestDrive 'nope.ledger') } |
                Should -Throw '*not found*'
        }

        It 'Should back up the current session journal when JournalPath is omitted' {
            try {
                Set-LedgerCurrentJournal -Path $JournalPath
                $Result = Backup-LedgerJournal
                $Result | Should -Not -BeNullOrEmpty
                Test-Path $Result.FullName | Should -BeTrue
            }
            finally {
                Clear-LedgerCurrentJournal
            }
        }
    }
}
