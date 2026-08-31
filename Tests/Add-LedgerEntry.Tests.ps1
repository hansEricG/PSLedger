BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerEntry' {
    BeforeAll {
        $CommandName = 'Add-LedgerEntry'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have an optional FiscalYear parameter of type String that binds from Name' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
            $Param.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $Param.Aliases | Should -Contain 'Name'
        }

        It 'Should have a mandatory Date parameter of type DateTime' {
            $Param = $Command.Parameters['Date']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'DateTime'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory Description parameter of type String' {
            $Param = $Command.Parameters['Description']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory Rows parameter' {
            $Param = $Command.Parameters['Rows']
            $Param | Should -Not -BeNullOrEmpty
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should accept Rows from the pipeline' {
            $Param = $Command.Parameters['Rows']
            $Param.Attributes.ValueFromPipeline | Should -Contain $true
        }

        It 'Should have an optional Attachment parameter that accepts multiple files' {
            $Param = $Command.Parameters['Attachment']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String[]'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have an optional PassThru switch' {
            $Param = $Command.Parameters['PassThru']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'
            $Rows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )
        }

        It 'Should create a verification file ver0001.txt' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Försäljning kontant' -Rows $Rows

            $VerFile = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            Test-Path $VerFile | Should -BeTrue
        }

        It 'Should auto-increment verification number' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Ver 1' -Rows $Rows
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-16' -Description 'Ver 2' -Rows $Rows

            $VerFile = Join-Path $JournalPath $FiscalYear 'ver0002.txt'
            Test-Path $VerFile | Should -BeTrue
        }

        It 'Should write date to the verification file' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Test' -Rows $Rows

            $Content = Get-Content (Join-Path $JournalPath $FiscalYear 'ver0001.txt') -Raw
            $Content | Should -Match '2024-01-15'
        }

        It 'Should write description to the verification file' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Försäljning kontant' -Rows $Rows

            $Content = Get-Content (Join-Path $JournalPath $FiscalYear 'ver0001.txt') -Raw
            $Content | Should -Match 'Försäljning kontant'
        }

        It 'Should write account rows to the verification file' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Test' -Rows $Rows

            $Content = Get-Content (Join-Path $JournalPath $FiscalYear 'ver0001.txt') -Raw
            $Content | Should -Match '1910'
            $Content | Should -Match '1000'
            $Content | Should -Match '3010'
            $Content | Should -Match '-1000'
        }

        It 'Should throw if rows do not balance (sum != 0)' {
            $BadRows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -500 }
            )

            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Obalanserad' -Rows $BadRows } | Should -Throw
        }

        It 'Should throw if fiscal year directory does not exist' {
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2099-01_2099-12' -Date '2024-01-15' -Description 'Test' -Rows $Rows } | Should -Throw
        }

        It 'Should throw if an account in Rows does not exist in chart of accounts' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'

            $BadRows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '9999'; Amount = -1000 }
            )

            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Okänt konto' -Rows $BadRows } |
                Should -Throw '*9999*'
        }

        It 'Should succeed when all accounts exist in chart of accounts' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'

            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Alla konton finns' -Rows $Rows } |
                Should -Not -Throw
        }

        It 'Should skip account validation when no accounts.txt exists' {
            # No accounts added — accounts.txt does not exist
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Utan kontoplan' -Rows $Rows } |
                Should -Not -Throw
        }

        It 'Should throw if date is before fiscal year start' {
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2023-12-31' -Description 'Före start' -Rows $Rows } |
                Should -Throw '*outside fiscal year*'
        }

        It 'Should throw if date is after fiscal year end' {
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-01-01' -Description 'Efter slut' -Rows $Rows } |
                Should -Throw '*outside fiscal year*'
        }

        It 'Should fail closed when year.txt is missing' {
            Remove-Item -Path (Join-Path $JournalPath $FiscalYear 'year.txt') -Force
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-06-15' -Description 'Utan year.txt' -Rows $Rows } |
                Should -Throw '*year.txt not found*'
        }

        It 'Should fail closed when year.txt has no parseable date range' {
            Set-Content -Path (Join-Path $JournalPath $FiscalYear 'year.txt') -Value @('Status: Open') -Encoding UTF8
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-06-15' -Description 'Trasig year.txt' -Rows $Rows } |
                Should -Throw '*StartDate/EndDate*'
        }

        It 'Should accept date on fiscal year boundary dates' {
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-01' -Description 'Första dagen' -Rows $Rows } |
                Should -Not -Throw
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-12-31' -Description 'Sista dagen' -Rows $Rows } |
                Should -Not -Throw
        }

        It 'Should produce no output by default' {
            $result = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Tyst' -Rows $Rows
            $result | Should -BeNullOrEmpty
        }

        It 'Should return a verification object with -PassThru' {
            $result = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Med passthru' -Rows $Rows -PassThru
            $result.VerificationNumber | Should -Be 1
            $result.FiscalYear | Should -Be $FiscalYear
            $result.Description | Should -Be 'Med passthru'
            $result.Path | Should -Match 'ver0001\.txt'
        }

        It 'Should attach files supplied via -Attachment' {
            $fileA = Join-Path $TestDrive 'kvitto-a.pdf'
            $fileB = Join-Path $TestDrive 'kvitto-b.pdf'
            'A' | Set-Content $fileA -Encoding UTF8
            'B' | Set-Content $fileB -Encoding UTF8

            $result = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-01-15' -Description 'Med bilagor' -Rows $Rows `
                -Attachment $fileA, $fileB -PassThru

            $result.Attachments.Count | Should -Be 2
            $attachDir = Join-Path $JournalPath $FiscalYear 'ver0001'
            Test-Path (Join-Path $attachDir 'kvitto-a.pdf') | Should -BeTrue
            Test-Path (Join-Path $attachDir 'kvitto-b.pdf') | Should -BeTrue
        }

        It 'Should not create a verification when an attachment file is missing' {
            $missing = Join-Path $TestDrive 'saknas.pdf'
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-01-15' -Description 'Trasig bilaga' -Rows $Rows `
                -Attachment $missing } | Should -Throw '*not found*'

            $VerFile = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            Test-Path $VerFile | Should -BeFalse
        }

        It 'Should collect rows piped in as a single verification' {
            $piped = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )
            $piped | Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-01-15' -Description 'Via pipeline'

            $VerFile = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            Test-Path $VerFile | Should -BeTrue
            $Content = Get-Content $VerFile -Raw
            $Content | Should -Match '1910'
            $Content | Should -Match '3010'
            # A single verification means ver0002.txt must not exist
            Test-Path (Join-Path $JournalPath $FiscalYear 'ver0002.txt') | Should -BeFalse
        }

        It 'Should accept rows built with New-LedgerEntryRow via the pipeline' {
            # A single debit row cannot balance, so it must throw and write nothing
            {
                New-LedgerEntryRow -Debit '1910' 2500 |
                    Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                        -Date '2024-01-15' -Description 'Obalanserad pipeline'
            } | Should -Throw '*does not balance*'
            Test-Path (Join-Path $JournalPath $FiscalYear 'ver0001.txt') | Should -BeFalse

            $rows = @(
                New-LedgerEntryRow -Debit '1910' 2500
                New-LedgerEntryRow -Credit '3010' 2500
            )
            $rows | Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-01-15' -Description 'Balanserad pipeline'

            $Content = Get-Content (Join-Path $JournalPath $FiscalYear 'ver0001.txt') -Raw
            $Content | Should -Match '1910'
            $Content | Should -Match '2500'
            $Content | Should -Match '-2500'
        }

        It 'Should still bind FiscalYear from the pipeline by property name' {
            $fyObject = [PSCustomObject]@{ Name = $FiscalYear }
            $fyObject | Add-LedgerEntry -JournalPath $JournalPath `
                -Date '2024-01-15' -Description 'Fiscal year via pipeline' -Rows $Rows

            Test-Path (Join-Path $JournalPath $FiscalYear 'ver0001.txt') | Should -BeTrue
        }
    }
}
