BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')
}

Describe 'Test-LedgerIntegrity' {
    BeforeAll {
        $CommandName = 'Test-LedgerIntegrity'
        $Command = Get-Command -Name $CommandName
        $FiscalYear = '2024-01_2024-12'

        function Add-TestEntry {
            param ([string]$JournalPath, [string]$Description = 'Kontorsmaterial', [decimal]$Amount = 100, [string[]]$Attachment)
            $rows = @(
                New-LedgerEntryRow -Debit 6110 -Amount $Amount
                New-LedgerEntryRow -Credit 1930 -Amount $Amount
            )
            $params = @{ JournalPath = $JournalPath; FiscalYear = $FiscalYear; Date = '2024-02-01'; Description = $Description; Rows = $rows }
            if ($Attachment) { $params.Attachment = $Attachment }
            Add-LedgerEntry @params
        }

        function Get-Problem {
            param ($Result)
            @($Result.Issues | ForEach-Object { "$($_.Kind) $($_.Key) $($_.Problem)" })
        }
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter of type String' {
            $Command.Parameters['JournalPath'].ParameterType.Name | Should -Be 'String'
            $Command.Parameters['JournalPath'].Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have an optional FiscalYear parameter that binds from Name' {
            $Param = $Command.Parameters['FiscalYear']
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
            $Param.Aliases | Should -Contain 'Name'
        }

        It 'Should have an optional ExpectedHash parameter of type String' {
            $Command.Parameters['ExpectedHash'].ParameterType.Name | Should -Be 'String'
            $Command.Parameters['ExpectedHash'].Attributes.Mandatory | Should -Not -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-TestLedger -Root $TestDrive
            $Receipt = Join-Path $TestDrive "kvitto-$([guid]::NewGuid().ToString('N')).txt"
            Set-Content -Path $Receipt -Value "Kvitto`r`nPennor 100 kr" -NoNewline
        }

        It 'Seals each verification and attachment when it is written' {
            Add-TestEntry -JournalPath $JournalPath -Attachment $Receipt
            Add-TestEntry -JournalPath $JournalPath -Description 'Papper'

            $lines = @(Get-Content (Join-Path $JournalPath $FiscalYear 'integrity.txt') | Where-Object { $_ -notmatch '^;' })
            $lines.Count | Should -Be 3
            ($lines | ForEach-Object { ($_ -split "`t")[0..1] -join ' ' }) |
                Should -Be @('Verification 1', "Attachment 1/$(Split-Path $Receipt -Leaf)", 'Verification 2')

            $result = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
            $result.Status | Should -Be 'Valid'
            $result.IsValid | Should -BeTrue
            $result.Verifications | Should -Be 2
            $result.Attachments | Should -Be 1
            $result.ChainHash | Should -Match '^[0-9a-f]{64}$'
            $result.Issues | Should -BeNullOrEmpty
        }

        It 'Checks every fiscal year when FiscalYear is omitted' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-01-01' -EndDate '2025-12-31'
            Add-TestEntry -JournalPath $JournalPath

            $results = @(Test-LedgerIntegrity -JournalPath $JournalPath)
            $results.FiscalYear | Should -Be @('2024-01_2024-12', '2025-01_2025-12')
            $results.Status | Should -Be @('Valid', 'Valid')
        }

        It 'Reports a changed verification' {
            Add-TestEntry -JournalPath $JournalPath
            Add-TestEntry -JournalPath $JournalPath
            $file = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            (Get-Content $file) -replace '100', '1000' | Set-Content $file

            $result = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
            $result.Status | Should -Be 'Invalid'
            $result.IsValid | Should -BeFalse
            Get-Problem $result | Should -Be @('Verification 1 Modified')
        }

        It 'Reports a deleted verification' {
            Add-TestEntry -JournalPath $JournalPath
            Add-TestEntry -JournalPath $JournalPath
            Remove-Item (Join-Path $JournalPath $FiscalYear 'ver0002.txt')

            Get-Problem (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear) |
                Should -Be @('Verification 2 Missing')
        }

        It 'Reports a verification added outside PSLedger' {
            Add-TestEntry -JournalPath $JournalPath
            Copy-Item (Join-Path $JournalPath $FiscalYear 'ver0001.txt') (Join-Path $JournalPath $FiscalYear 'ver0002.txt')

            Get-Problem (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear) |
                Should -Be @('Verification 2 Unsealed')
        }

        It 'Reports changed, deleted and unsealed attachments' {
            Add-TestEntry -JournalPath $JournalPath -Attachment $Receipt
            Add-TestEntry -JournalPath $JournalPath -Attachment $Receipt
            $name = Split-Path $Receipt -Leaf
            Set-Content (Join-Path $JournalPath $FiscalYear 'ver0001' $name) 'Ändrat kvitto'
            Remove-Item (Join-Path $JournalPath $FiscalYear 'ver0002' $name)
            Set-Content (Join-Path $JournalPath $FiscalYear 'ver0002' 'extra.txt') 'Nytt underlag'

            Get-Problem (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear) |
                Should -Be @("Attachment 1/$name Modified", "Attachment 2/$name Missing", 'Attachment 2/extra.txt Unsealed')
        }

        It 'Logs an attachment removed with Remove-LedgerAttachment instead of reporting it' {
            Add-TestEntry -JournalPath $JournalPath -Attachment $Receipt
            Remove-LedgerAttachment -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1 -FileName (Split-Path $Receipt -Leaf)

            $result = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
            $result.Status | Should -Be 'Valid'
            $result.Attachments | Should -Be 0
            Get-Content (Join-Path $JournalPath $FiscalYear 'integrity.txt') | Select-Object -Last 1 | Should -Match '^AttachmentRemoved\t1/'
        }

        It 'Refuses to replace a sealed attachment' {
            Add-TestEntry -JournalPath $JournalPath -Attachment $Receipt
            { Add-LedgerAttachment -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1 -Path $Receipt } |
                Should -Throw '*is sealed*'
        }

        It 'Allows an attachment to be added again after it was removed' {
            Add-TestEntry -JournalPath $JournalPath -Attachment $Receipt
            $name = Split-Path $Receipt -Leaf
            Remove-LedgerAttachment -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1 -FileName $name
            Add-LedgerAttachment -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1 -Path $Receipt

            $result = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
            $result.Status | Should -Be 'Valid'
            $result.Attachments | Should -Be 1
        }

        It 'Reports an edited chain record' {
            Add-TestEntry -JournalPath $JournalPath
            Add-TestEntry -JournalPath $JournalPath
            $chainFile = Join-Path $JournalPath $FiscalYear 'integrity.txt'
            $lines = Get-Content $chainFile
            $lines[2] = $lines[2] -replace '\t\d{4}-\d{2}-\d{2}T', "`t2020-01-01T"
            Set-Content $chainFile $lines

            Get-Problem (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear) |
                Should -Be @('Chain line 3 ChainBroken')
        }

        It 'Reports a removed chain record and a sealed verification that was re-sealed by hand' {
            Add-TestEntry -JournalPath $JournalPath
            Add-TestEntry -JournalPath $JournalPath
            $chainFile = Join-Path $JournalPath $FiscalYear 'integrity.txt'
            $lines = @(Get-Content $chainFile)
            Set-Content $chainFile ($lines[0], $lines[1], $lines[3])

            $problems = Get-Problem (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear)
            $problems | Should -Contain 'Chain line 3 ChainBroken'
            $problems | Should -Contain 'Verification 1 Unsealed'
        }

        It 'Reports a malformed chain line' {
            Add-TestEntry -JournalPath $JournalPath
            Add-Content (Join-Path $JournalPath $FiscalYear 'integrity.txt') 'Verification	2	trasig'

            Get-Problem (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear) |
                Should -Be @('Chain line 4 Malformed')
        }

        It 'Detects a rebuilt chain with ExpectedHash' {
            Add-TestEntry -JournalPath $JournalPath
            $saved = (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear).ChainHash
            (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear -ExpectedHash $saved.ToUpperInvariant()).Status |
                Should -Be 'Valid'

            # Change the verification and rebuild the whole chain from scratch.
            $file = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            (Get-Content $file) -replace '100', '1000' | Set-Content $file
            Remove-Item (Join-Path $JournalPath $FiscalYear 'integrity.txt')
            Protect-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear | Out-Null

            (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear).Status | Should -Be 'Valid'
            Get-Problem (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear -ExpectedHash $saved) |
                Should -Be @('Chain  HashMismatch')
        }

        It 'Requires FiscalYear with ExpectedHash' {
            { Test-LedgerIntegrity -JournalPath $JournalPath -ExpectedHash ('0' * 64) } | Should -Throw '*requires -FiscalYear*'
        }

        It 'Ignores line-ending conversion of verifications and text attachments' {
            Add-TestEntry -JournalPath $JournalPath -Attachment $Receipt
            $files = @(
                Join-Path $JournalPath $FiscalYear 'ver0001.txt'
                Join-Path $JournalPath $FiscalYear 'ver0001' (Split-Path $Receipt -Leaf)
            )
            foreach ($file in $files) {
                $text = [System.IO.File]::ReadAllText($file)
                $converted = if ($text.Contains("`r`n")) { $text.Replace("`r`n", "`n") } else { $text.Replace("`n", "`r`n") }
                [System.IO.File]::WriteAllText($file, $converted)
            }

            (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear).Status | Should -Be 'Valid'
        }

        It 'Hashes binary attachments byte for byte' {
            $pdf = Join-Path $TestDrive "faktura-$([guid]::NewGuid().ToString('N')).pdf"
            [System.IO.File]::WriteAllBytes($pdf, [byte[]](37, 80, 68, 70, 0, 13, 10, 1))
            Add-TestEntry -JournalPath $JournalPath -Attachment $pdf
            $stored = Join-Path $JournalPath $FiscalYear 'ver0001' (Split-Path $pdf -Leaf)
            [System.IO.File]::WriteAllBytes($stored, [byte[]](37, 80, 68, 70, 0, 10, 1))

            Get-Problem (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear) |
                Should -Be @("Attachment 1/$(Split-Path $pdf -Leaf) Modified")
        }

        It 'Reports a year without a chain as Unsealed' {
            Add-TestEntry -JournalPath $JournalPath
            Remove-Item (Join-Path $JournalPath $FiscalYear 'integrity.txt')

            $result = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
            $result.Status | Should -Be 'Unsealed'
            $result.IsValid | Should -BeFalse
            $result.ChainHash | Should -BeNullOrEmpty
        }

        It 'Reports an empty year without a chain as Valid' {
            (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear).Status | Should -Be 'Valid'
        }

        It 'Seals all existing verifications when the first entry is added to a journal without a chain' {
            Add-TestEntry -JournalPath $JournalPath -Attachment $Receipt
            Add-TestEntry -JournalPath $JournalPath
            Remove-Item (Join-Path $JournalPath $FiscalYear 'integrity.txt')

            Add-TestEntry -JournalPath $JournalPath
            $result = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
            $result.Status | Should -Be 'Valid'
            $result.Verifications | Should -Be 3
            $result.Attachments | Should -Be 1
        }

        It 'Does not modify the journal' {
            Add-TestEntry -JournalPath $JournalPath
            $before = Get-ChildItem $JournalPath -Recurse -File | ForEach-Object { "$($_.FullName) $($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
            Test-LedgerIntegrity -JournalPath $JournalPath | Out-Null
            Get-ChildItem $JournalPath -Recurse -File | ForEach-Object { "$($_.FullName) $($_.Length) $($_.LastWriteTimeUtc.Ticks)" } |
                Should -Be $before
        }
    }
}
