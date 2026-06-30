BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerDocument' {
    BeforeAll {
        $CommandName = 'Add-LedgerDocument'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory Path parameter of type String array' {
            $Param = $Command.Parameters['Path']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String[]'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have Path accept pipeline input' {
            $Param = $Command.Parameters['Path']
            $attrs = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attrs.ValueFromPipeline | Should -Contain $true
            $attrs.ValueFromPipelineByPropertyName | Should -Contain $true
        }

        It 'Should have an optional Move switch' {
            $Param = $Command.Parameters['Move']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have an optional Force switch' {
            $Param = $Command.Parameters['Force']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have FiscalYear accept pipeline by property name' {
            $Param = $Command.Parameters['FiscalYear']
            $attrs = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attrs.ValueFromPipelineByPropertyName | Should -Contain $true
        }

        It 'Should not have a VerificationNumber parameter' {
            $Command.Parameters.ContainsKey('VerificationNumber') | Should -BeFalse
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'AddDoc.ledger'
            New-LedgerJournal -Path $journalDir -Name 'Bokforing Nord AB' -OrgNumber '556000-0010'
            Import-LedgerChart -JournalPath $journalDir -Template 'BAS-Mini'
            New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2024-01-01' -EndDate '2024-12-31'
            Set-LedgerCurrentJournal -Path $journalDir
        }

        AfterAll {
            Clear-LedgerCurrentJournal
        }

        It 'Should copy a file to the fiscal year document directory' {
            $testFile = Join-Path $TestDrive 'kontoutdrag-jan.pdf'
            'PDF content' | Set-Content $testFile -Encoding UTF8

            $result = Add-LedgerDocument -Path $testFile
            $result.FileName | Should -Be 'kontoutdrag-jan.pdf'
            $result.FiscalYear | Should -Be '2024-01_2024-12'

            $destDir = Join-Path $journalDir '2024-01_2024-12' 'documents'
            Test-Path (Join-Path $destDir 'kontoutdrag-jan.pdf') | Should -BeTrue
            # Original should still exist (copy, not move)
            Test-Path $testFile | Should -BeTrue
        }

        It 'Should move a file when -Move is specified' {
            $testFile = Join-Path $TestDrive 'kontoutdrag-feb.pdf'
            'PDF content' | Set-Content $testFile -Encoding UTF8

            Add-LedgerDocument -Path $testFile -Move
            # Original should be gone
            Test-Path $testFile | Should -BeFalse
        }

        It 'Should throw when fiscal year does not exist' {
            $testFile = Join-Path $TestDrive 'dummy.txt'
            'x' | Set-Content $testFile -Encoding UTF8

            { Add-LedgerDocument -FiscalYear '2099-01_2099-12' -Path $testFile } |
                Should -Throw '*not found*'
        }

        It 'Should throw when source file does not exist' {
            { Add-LedgerDocument -Path 'C:\nonexistent.pdf' } |
                Should -Throw '*not found*'
        }

        It 'Should return object with correct properties' {
            $testFile = Join-Path $TestDrive 'rapport.xlsx'
            'XLS content' | Set-Content $testFile -Encoding UTF8

            $result = Add-LedgerDocument -Path $testFile
            $result.FiscalYear | Should -Be '2024-01_2024-12'
            $result.FileName | Should -Be 'rapport.xlsx'
            $result.DestinationPath | Should -Not -BeNullOrEmpty
            $result.Size | Should -BeGreaterThan 0
        }

        It 'Should add multiple files passed as an array' {
            $a = Join-Path $TestDrive 'multi-a.pdf'
            $b = Join-Path $TestDrive 'multi-b.pdf'
            'a' | Set-Content $a -Encoding UTF8
            'b' | Set-Content $b -Encoding UTF8

            $result = Add-LedgerDocument -Path $a, $b
            $result.Count | Should -Be 2

            $destDir = Join-Path $journalDir '2024-01_2024-12' 'documents'
            Test-Path (Join-Path $destDir 'multi-a.pdf') | Should -BeTrue
            Test-Path (Join-Path $destDir 'multi-b.pdf') | Should -BeTrue
        }

        It 'Should expand wildcard patterns' {
            $dir = Join-Path $TestDrive 'wild'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            'x' | Set-Content (Join-Path $dir 'wild-1.pdf') -Encoding UTF8
            'y' | Set-Content (Join-Path $dir 'wild-2.pdf') -Encoding UTF8
            'z' | Set-Content (Join-Path $dir 'other.txt') -Encoding UTF8

            $result = Add-LedgerDocument -Path (Join-Path $dir '*.pdf')
            $result.Count | Should -Be 2
            ($result.FileName | Sort-Object) | Should -Be @('wild-1.pdf', 'wild-2.pdf')
        }

        It 'Should add all files piped from Get-ChildItem' {
            $dir = Join-Path $TestDrive 'piped-folder'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            '1' | Set-Content (Join-Path $dir 'p1.pdf') -Encoding UTF8
            '2' | Set-Content (Join-Path $dir 'p2.pdf') -Encoding UTF8

            $result = Get-ChildItem -Path $dir -File | Add-LedgerDocument
            $result.Count | Should -Be 2

            $destDir = Join-Path $journalDir '2024-01_2024-12' 'documents'
            Test-Path (Join-Path $destDir 'p1.pdf') | Should -BeTrue
            Test-Path (Join-Path $destDir 'p2.pdf') | Should -BeTrue
        }

        It 'Should throw a helpful error when given a directory' {
            $dir = Join-Path $TestDrive 'a-folder'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null

            { Add-LedgerDocument -Path $dir } | Should -Throw '*directory*'
        }

        It 'Should not overwrite an existing document by default' {
            $first = Join-Path $TestDrive 'clobber.pdf'
            'original' | Set-Content $first -Encoding UTF8
            Add-LedgerDocument -Path $first

            $secondDir = Join-Path $TestDrive 'other'
            New-Item -ItemType Directory -Path $secondDir -Force | Out-Null
            $second = Join-Path $secondDir 'clobber.pdf'
            'replacement' | Set-Content $second -Encoding UTF8

            $err = $null
            $result = Add-LedgerDocument -Path $second -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty

            $destPath = Join-Path $journalDir '2024-01_2024-12' 'documents' 'clobber.pdf'
            (Get-Content $destPath -Raw).Trim() | Should -Be 'original'
        }

        It 'Should overwrite an existing document when -Force is specified' {
            $first = Join-Path $TestDrive 'forced.pdf'
            'original' | Set-Content $first -Encoding UTF8
            Add-LedgerDocument -Path $first

            $secondDir = Join-Path $TestDrive 'force-other'
            New-Item -ItemType Directory -Path $secondDir -Force | Out-Null
            $second = Join-Path $secondDir 'forced.pdf'
            'replacement' | Set-Content $second -Encoding UTF8

            $result = Add-LedgerDocument -Path $second -Force
            $result.FileName | Should -Be 'forced.pdf'

            $destPath = Join-Path $journalDir '2024-01_2024-12' 'documents' 'forced.pdf'
            (Get-Content $destPath -Raw).Trim() | Should -Be 'replacement'
        }

        It 'Should skip a colliding file but still add the rest of the batch' {
            $existingSrc = Join-Path $TestDrive 'batch-existing.pdf'
            'orig' | Set-Content $existingSrc -Encoding UTF8
            Add-LedgerDocument -Path $existingSrc

            $dir = Join-Path $TestDrive 'batch'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $collide = Join-Path $dir 'batch-existing.pdf'
            $fresh = Join-Path $dir 'batch-new.pdf'
            'dup' | Set-Content $collide -Encoding UTF8
            'fresh' | Set-Content $fresh -Encoding UTF8

            $result = Add-LedgerDocument -Path $collide, $fresh -ErrorAction SilentlyContinue
            $result.FileName | Should -Be 'batch-new.pdf'

            $destDir = Join-Path $journalDir '2024-01_2024-12' 'documents'
            Test-Path (Join-Path $destDir 'batch-new.pdf') | Should -BeTrue
            (Get-Content (Join-Path $destDir 'batch-existing.pdf') -Raw).Trim() | Should -Be 'orig'
        }
    }
}

Describe 'Get-LedgerDocument' {
    BeforeAll {
        $CommandName = 'Get-LedgerDocument'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have FiscalYear accept pipeline by property name' {
            $Param = $Command.Parameters['FiscalYear']
            $attrs = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attrs.ValueFromPipelineByPropertyName | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'GetDoc.ledger'
            New-LedgerJournal -Path $journalDir -Name 'Bokforing Nord AB' -OrgNumber '556000-0011'
            Import-LedgerChart -JournalPath $journalDir -Template 'BAS-Mini'
            New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2024-01-01' -EndDate '2024-12-31'
            Set-LedgerCurrentJournal -Path $journalDir

            $file1 = Join-Path $TestDrive 'kontoutdrag-jan.pdf'
            $file2 = Join-Path $TestDrive 'kontoutdrag-feb.pdf'
            $file3 = Join-Path $TestDrive 'arsredovisning.pdf'
            'content1' | Set-Content $file1 -Encoding UTF8
            'content2' | Set-Content $file2 -Encoding UTF8
            'content3' | Set-Content $file3 -Encoding UTF8
            Add-LedgerDocument -Path $file1
            Add-LedgerDocument -Path $file2
            Add-LedgerDocument -Path $file3
        }

        AfterAll {
            Clear-LedgerCurrentJournal
        }

        It 'Should list all documents in the fiscal year' {
            $result = Get-LedgerDocument
            $result.Count | Should -Be 3
        }

        It 'Should return correct properties' {
            $result = Get-LedgerDocument | Select-Object -First 1
            $result.FileName | Should -Not -BeNullOrEmpty
            $result.FiscalYear | Should -Be '2024-01_2024-12'
            $result.Path | Should -Not -BeNullOrEmpty
            $result.Size | Should -BeGreaterThan 0
        }

        It 'Should filter documents by FileName pattern' {
            $result = Get-LedgerDocument -FileName 'kontoutdrag-*'
            $result.Count | Should -Be 2
        }

        It 'Should return nothing when fiscal year has no documents' {
            New-LedgerFiscalYear -StartDate '2025-01-01' -EndDate '2025-12-31'
            $result = Get-LedgerDocument -FiscalYear '2025-01_2025-12'
            $result | Should -BeNullOrEmpty
        }

        It 'Should accept pipeline input by FiscalYear property name' {
            $result = [PSCustomObject]@{ FiscalYear = '2024-01_2024-12' } | Get-LedgerDocument
            $result.Count | Should -Be 3
        }
    }
}

Describe 'Remove-LedgerDocument' {
    BeforeAll {
        $CommandName = 'Remove-LedgerDocument'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory FileName parameter' {
            $Param = $Command.Parameters['FileName']
            $Param | Should -Not -BeNullOrEmpty
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should support ShouldProcess' {
            $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'RemDoc.ledger'
            New-LedgerJournal -Path $journalDir -Name 'Bokforing Nord AB' -OrgNumber '556000-0012'
            Import-LedgerChart -JournalPath $journalDir -Template 'BAS-Mini'
            New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2024-01-01' -EndDate '2024-12-31'
            Set-LedgerCurrentJournal -Path $journalDir
        }

        AfterAll {
            Clear-LedgerCurrentJournal
        }

        It 'Should remove a document file' {
            $file = Join-Path $TestDrive 'toremove.pdf'
            'content' | Set-Content $file -Encoding UTF8
            Add-LedgerDocument -Path $file

            Remove-LedgerDocument -FileName 'toremove.pdf' -Confirm:$false
            $remaining = Get-LedgerDocument | Where-Object { $_.FileName -eq 'toremove.pdf' }
            $remaining | Should -BeNullOrEmpty
        }

        It 'Should remove the directory when last file is removed' {
            $file = Join-Path $TestDrive 'last.pdf'
            'content' | Set-Content $file -Encoding UTF8
            Add-LedgerDocument -Path $file

            Remove-LedgerDocument -FileName 'last.pdf' -Confirm:$false

            $docDir = Join-Path $journalDir '2024-01_2024-12' 'documents'
            Test-Path $docDir | Should -BeFalse
        }

        It 'Should throw when document does not exist' {
            $file = Join-Path $TestDrive 'exists.pdf'
            'content' | Set-Content $file -Encoding UTF8
            Add-LedgerDocument -Path $file

            { Remove-LedgerDocument -FileName 'nonexistent.pdf' -Confirm:$false } |
                Should -Throw '*not found*'
        }

        It 'Should throw when no documents directory exists' {
            New-LedgerFiscalYear -StartDate '2026-01-01' -EndDate '2026-12-31'

            { Remove-LedgerDocument -FiscalYear '2026-01_2026-12' -FileName 'any.pdf' -Confirm:$false } |
                Should -Throw '*No documents*'
        }

        It 'Should accept pipeline input from Get-LedgerDocument' {
            $file = Join-Path $TestDrive 'piped.pdf'
            'content' | Set-Content $file -Encoding UTF8
            Add-LedgerDocument -Path $file

            Get-LedgerDocument -FileName 'piped.pdf' |
                Remove-LedgerDocument -Confirm:$false

            $remaining = Get-LedgerDocument | Where-Object { $_.FileName -eq 'piped.pdf' }
            $remaining | Should -BeNullOrEmpty
        }
    }
}
