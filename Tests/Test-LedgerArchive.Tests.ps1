BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')
}

Describe 'Test-LedgerArchive' {
    BeforeAll {
        $CommandName = 'Test-LedgerArchive'
        $Command = Get-Command -Name $CommandName
        $Fixture = Join-Path $PSScriptRoot 'Fixtures' 'FileFormat' 'Exempel.ledger'
        $Year = '2023-01_2023-12'

        function New-TestArchive {
            param ([switch]$AsDirectory)
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            Copy-Item -Path $Fixture -Destination $dir -Recurse
            Export-LedgerArchive -JournalPath (Join-Path $dir 'Exempel.ledger') -FiscalYear $Year -AsDirectory:$AsDirectory
        }
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory Path parameter that binds from the pipeline' {
            $Param = $Command.Parameters['Path']
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
            $Param.Attributes.ValueFromPipeline | Should -Contain $true
            $Param.Aliases | Should -Contain 'FullName'
        }
    }

    Context 'Behavior' {
        It 'Reports a fresh zip archive as valid' {
            $zip = New-TestArchive

            $result = Test-LedgerArchive -Path $zip.FullName
            $result.Status | Should -Be 'Valid'
            $result.IsValid | Should -BeTrue
            $result.Journal | Should -Be 'Exempel AB'
            $result.FiscalYear | Should -Be $Year
            $result.Preliminary | Should -BeFalse
            $result.IntegrityStatus | Should -Be 'Valid'
            $result.ChainHash | Should -Be '5364aa894e1d60cf65d1942ee1b8b2ab9b64f8ddc33f13db03f6530a78ce96e1'
            $result.Files | Should -BeGreaterThan 10
            $result.Issues | Should -BeNullOrEmpty
        }

        It 'Accepts packages from the pipeline' {
            $result = New-TestArchive -AsDirectory | Test-LedgerArchive
            $result.Status | Should -Be 'Valid'
        }

        It 'Removes the temporary extraction directory' {
            $zip = New-TestArchive
            $before = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Directory -Filter 'psledger_archive_*').Count
            Test-LedgerArchive -Path $zip.FullName | Out-Null
            @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Directory -Filter 'psledger_archive_*').Count | Should -Be $before
        }

        It 'Reports modified, missing and unlisted files' {
            $dir = New-TestArchive -AsDirectory
            Add-Content (Join-Path $dir.FullName 'reports' 'grundbok.txt') 'x'
            Remove-Item (Join-Path $dir.FullName 'reports' 'huvudbok.pdf')
            Set-Content (Join-Path $dir.FullName 'reports' 'extra.txt') 'x'

            $result = Test-LedgerArchive -Path $dir.FullName
            $result.Status | Should -Be 'Invalid'
            @($result.Issues | ForEach-Object { "$($_.Problem) $($_.Path)" } | Sort-Object) |
                Should -Be @('Missing reports/huvudbok.pdf', 'Modified reports/grundbok.txt', 'Unlisted reports/extra.txt')
        }

        It 'Detects a change inside a zip archive' {
            $zip = New-TestArchive
            $archive = [System.IO.Compression.ZipFile]::Open($zip.FullName, 'Update')
            try {
                $entry = $archive.GetEntry("Exempel_${Year}_archive/journal/$Year/ver0001.txt")
                $writer = [System.IO.StreamWriter]::new($entry.Open())
                $writer.BaseStream.Seek(0, 'End') | Out-Null
                $writer.Write('x')
                $writer.Dispose()
            }
            finally {
                $archive.Dispose()
            }

            $issues = (Test-LedgerArchive -Path $zip.FullName).Issues
            $issues | Where-Object { $_.Problem -eq 'Modified' -and $_.Path -eq "journal/$Year/ver0001.txt" } | Should -Not -BeNullOrEmpty
        }

        It 'Detects a changed verification even when checksums.txt is updated' {
            $dir = New-TestArchive -AsDirectory
            $ver = Join-Path $dir.FullName 'journal' $Year 'ver0001.txt'
            Add-Content $ver 'x'
            $checksums = Join-Path $dir.FullName 'checksums.txt'
            $hash = (Get-FileHash $ver).Hash.ToLowerInvariant()
            $lines = Get-Content $checksums | ForEach-Object { if ($_ -like "*  journal/$Year/ver0001.txt") { "$hash  journal/$Year/ver0001.txt" } else { $_ } }
            Set-Content $checksums $lines

            $result = Test-LedgerArchive -Path $dir.FullName
            $result.Status | Should -Be 'Invalid'
            $result.Issues.Problem | Should -Be @('Integrity')
            $result.Issues.Detail | Should -Match 'Verification 1: Modified'
        }

        It 'Reports a directory that is not an archive package' {
            $dir = Join-Path $TestDrive 'not-an-archive'
            New-Item -ItemType Directory -Path $dir | Out-Null

            $result = Test-LedgerArchive -Path $dir
            $result.Status | Should -Be 'Invalid'
            $result.Issues.Problem | Should -Contain 'Malformed'
        }

        It 'Throws for a path that does not exist' {
            { Test-LedgerArchive -Path (Join-Path $TestDrive 'missing.zip') } | Should -Throw '*not found*'
        }
    }
}
