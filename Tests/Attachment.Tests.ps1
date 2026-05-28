BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerAttachment' {
    BeforeAll {
        $CommandName = 'Add-LedgerAttachment'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory VerificationNumber parameter of type Int32' {
            $Param = $Command.Parameters['VerificationNumber']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'Int32'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory Path parameter of type String' {
            $Param = $Command.Parameters['Path']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have an optional Move switch' {
            $Param = $Command.Parameters['Move']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'AttachTest.ledger'
            New-LedgerJournal -Path $journalDir -Name 'AttachTest AB' -OrgNumber '556000-0003'
            Import-LedgerChart -JournalPath $journalDir -Template 'BAS-Mini'
            New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2024-01-01' -EndDate '2024-12-31'
            $rows = @(
                @{ Account = '1910'; Amount = 5000 }
                @{ Account = '3010'; Amount = -5000 }
            )
            Add-LedgerEntry -JournalPath $journalDir -FiscalYear '2024-01_2024-12' `
                -Date '2024-03-15' -Description 'Test entry' -Rows $rows
            Set-LedgerJournal -Path $journalDir
        }

        AfterAll {
            Clear-LedgerJournal
        }

        It 'Should copy a file to the verification attachment directory' {
            $testFile = Join-Path $TestDrive 'faktura.pdf'
            'PDF content' | Set-Content $testFile -Encoding UTF8

            $result = Add-LedgerAttachment -VerificationNumber 1 -Path $testFile
            $result.FileName | Should -Be 'faktura.pdf'
            $result.VerificationNumber | Should -Be 1

            $destDir = Join-Path $journalDir '2024-01_2024-12' 'ver0001'
            Test-Path (Join-Path $destDir 'faktura.pdf') | Should -BeTrue
            # Original should still exist (copy, not move)
            Test-Path $testFile | Should -BeTrue
        }

        It 'Should move a file when -Move is specified' {
            $testFile = Join-Path $TestDrive 'kvitto.jpg'
            'JPG content' | Set-Content $testFile -Encoding UTF8

            Add-LedgerAttachment -VerificationNumber 1 -Path $testFile -Move
            # Original should be gone
            Test-Path $testFile | Should -BeFalse
        }

        It 'Should throw when verification does not exist' {
            $testFile = Join-Path $TestDrive 'dummy.txt'
            'x' | Set-Content $testFile -Encoding UTF8

            { Add-LedgerAttachment -VerificationNumber 99 -Path $testFile } |
                Should -Throw '*not found*'
        }

        It 'Should throw when source file does not exist' {
            { Add-LedgerAttachment -VerificationNumber 1 -Path 'C:\nonexistent.pdf' } |
                Should -Throw '*not found*'
        }

        It 'Should return object with correct properties' {
            $testFile = Join-Path $TestDrive 'rapport.xlsx'
            'XLS content' | Set-Content $testFile -Encoding UTF8

            $result = Add-LedgerAttachment -VerificationNumber 1 -Path $testFile
            $result.VerificationNumber | Should -Be 1
            $result.FiscalYear | Should -Be '2024-01_2024-12'
            $result.FileName | Should -Be 'rapport.xlsx'
            $result.DestinationPath | Should -Not -BeNullOrEmpty
            $result.Size | Should -BeGreaterThan 0
        }
    }
}

Describe 'Get-LedgerAttachment' {
    BeforeAll {
        $CommandName = 'Get-LedgerAttachment'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have VerificationNumber accept pipeline by property name' {
            $Param = $Command.Parameters['VerificationNumber']
            $attrs = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attrs.ValueFromPipelineByPropertyName | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'GetAttach.ledger'
            New-LedgerJournal -Path $journalDir -Name 'GetAttach AB' -OrgNumber '556000-0004'
            Import-LedgerChart -JournalPath $journalDir -Template 'BAS-Mini'
            New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2024-01-01' -EndDate '2024-12-31'
            $rows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )
            Add-LedgerEntry -JournalPath $journalDir -FiscalYear '2024-01_2024-12' `
                -Date '2024-01-15' -Description 'Entry 1' -Rows $rows
            Add-LedgerEntry -JournalPath $journalDir -FiscalYear '2024-01_2024-12' `
                -Date '2024-02-15' -Description 'Entry 2' -Rows $rows
            Set-LedgerJournal -Path $journalDir

            # Attach files
            $file1 = Join-Path $TestDrive 'doc1.pdf'
            $file2 = Join-Path $TestDrive 'doc2.pdf'
            $file3 = Join-Path $TestDrive 'doc3.pdf'
            'content1' | Set-Content $file1 -Encoding UTF8
            'content2' | Set-Content $file2 -Encoding UTF8
            'content3' | Set-Content $file3 -Encoding UTF8
            Add-LedgerAttachment -VerificationNumber 1 -Path $file1
            Add-LedgerAttachment -VerificationNumber 1 -Path $file2
            Add-LedgerAttachment -VerificationNumber 2 -Path $file3
        }

        AfterAll {
            Clear-LedgerJournal
        }

        It 'Should list attachments for a specific verification' {
            $result = Get-LedgerAttachment -VerificationNumber 1
            $result.Count | Should -Be 2
            $result[0].VerificationNumber | Should -Be 1
        }

        It 'Should return correct properties' {
            $result = Get-LedgerAttachment -VerificationNumber 1 | Select-Object -First 1
            $result.FileName | Should -Not -BeNullOrEmpty
            $result.FiscalYear | Should -Be '2024-01_2024-12'
            $result.Path | Should -Not -BeNullOrEmpty
            $result.Size | Should -BeGreaterThan 0
        }

        It 'Should list all attachments when no verification specified' {
            $result = Get-LedgerAttachment
            $result.Count | Should -Be 3
        }

        It 'Should return nothing for verification without attachments' {
            # Create a third entry without attachments
            $rows = @(
                @{ Account = '1910'; Amount = 500 }
                @{ Account = '3010'; Amount = -500 }
            )
            Add-LedgerEntry -FiscalYear '2024-01_2024-12' `
                -Date '2024-03-15' -Description 'Entry 3' -Rows $rows
            $result = Get-LedgerAttachment -VerificationNumber 3
            $result | Should -BeNullOrEmpty
        }

        It 'Should accept pipeline input from Get-LedgerEntry' {
            $result = Get-LedgerEntry -FiscalYear '2024-01_2024-12' -VerificationNumber 2 |
                Get-LedgerAttachment
            $result | Should -Not -BeNullOrEmpty
            $result.FileName | Should -Be 'doc3.pdf'
        }
    }
}

Describe 'Remove-LedgerAttachment' {
    BeforeAll {
        $CommandName = 'Remove-LedgerAttachment'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory VerificationNumber parameter' {
            $Param = $Command.Parameters['VerificationNumber']
            $Param | Should -Not -BeNullOrEmpty
            $Param.Attributes.Mandatory | Should -Contain $true
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
            $journalDir = Join-Path $TestDrive 'RemAttach.ledger'
            New-LedgerJournal -Path $journalDir -Name 'RemAttach AB' -OrgNumber '556000-0005'
            Import-LedgerChart -JournalPath $journalDir -Template 'BAS-Mini'
            New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2024-01-01' -EndDate '2024-12-31'
            $rows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )
            Add-LedgerEntry -JournalPath $journalDir -FiscalYear '2024-01_2024-12' `
                -Date '2024-01-15' -Description 'Entry' -Rows $rows
            Set-LedgerJournal -Path $journalDir
        }

        AfterAll {
            Clear-LedgerJournal
        }

        It 'Should remove an attachment file' {
            $file = Join-Path $TestDrive 'toremove.pdf'
            'content' | Set-Content $file -Encoding UTF8
            Add-LedgerAttachment -VerificationNumber 1 -Path $file

            Remove-LedgerAttachment -VerificationNumber 1 -FileName 'toremove.pdf' -Confirm:$false
            $remaining = Get-LedgerAttachment -VerificationNumber 1 |
                Where-Object { $_.FileName -eq 'toremove.pdf' }
            $remaining | Should -BeNullOrEmpty
        }

        It 'Should remove the directory when last file is removed' {
            $file = Join-Path $TestDrive 'last.pdf'
            'content' | Set-Content $file -Encoding UTF8
            Add-LedgerAttachment -VerificationNumber 1 -Path $file

            Remove-LedgerAttachment -VerificationNumber 1 -FileName 'last.pdf' -Confirm:$false

            $attachDir = Join-Path $journalDir '2024-01_2024-12' 'ver0001'
            Test-Path $attachDir | Should -BeFalse
        }

        It 'Should throw when attachment does not exist' {
            $file = Join-Path $TestDrive 'exists.pdf'
            'content' | Set-Content $file -Encoding UTF8
            Add-LedgerAttachment -VerificationNumber 1 -Path $file

            { Remove-LedgerAttachment -VerificationNumber 1 -FileName 'nonexistent.pdf' -Confirm:$false } |
                Should -Throw '*not found*'
        }

        It 'Should throw when no attachments directory exists' {
            # Use a verification without any prior attachments
            $rows = @(
                @{ Account = '1910'; Amount = 2000 }
                @{ Account = '3010'; Amount = -2000 }
            )
            Add-LedgerEntry -FiscalYear '2024-01_2024-12' `
                -Date '2024-02-15' -Description 'Entry 2' -Rows $rows

            { Remove-LedgerAttachment -VerificationNumber 2 -FileName 'any.pdf' -Confirm:$false } |
                Should -Throw '*No attachments*'
        }
    }
}
