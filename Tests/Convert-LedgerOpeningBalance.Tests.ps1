BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Convert-LedgerOpeningBalance' {
    BeforeAll {
        $CommandName = 'Convert-LedgerOpeningBalance'
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
            $Command.Parameters['WhatIf'] | Should -Not -BeNullOrEmpty
            $Command.Parameters['Confirm'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have an optional JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Legacy AB'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa och bank'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2081' -AccountName 'Aktiekapital'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '4010' -AccountName 'Inköp'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'
            $YearDir = Join-Path $JournalPath $FiscalYear

            # Legacy layout: opening balance stored as the first verification.
            @(
                'Date: 2024-01-01'
                'Description: Ingående balans'
                ''
                "1910`t4000"
                "2081`t-4000"
            ) | Set-Content -Path (Join-Path $YearDir 'ver0001.txt') -Encoding UTF8
            @(
                'Date: 2024-03-15'
                'Description: Försäljning'
                ''
                "1910`t500"
                "3010`t-500"
            ) | Set-Content -Path (Join-Path $YearDir 'ver0002.txt') -Encoding UTF8
            @(
                'Date: 2024-04-01'
                'Description: Inköp'
                ''
                "4010`t200"
                "1910`t-200"
            ) | Set-Content -Path (Join-Path $YearDir 'ver0003.txt') -Encoding UTF8
        }

        It 'Should create ib.txt from the opening balance verification' {
            Convert-LedgerOpeningBalance -JournalPath $JournalPath | Out-Null

            $IbFile = Join-Path $YearDir 'ib.txt'
            Test-Path $IbFile | Should -BeTrue

            $balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            ($balance | Where-Object AccountNumber -eq '1910').OpeningBalance | Should -Be 4000
            ($balance | Where-Object AccountNumber -eq '2081').OpeningBalance | Should -Be -4000
        }

        It 'Should remove the opening balance verification and renumber the rest' {
            Convert-LedgerOpeningBalance -JournalPath $JournalPath | Out-Null

            $entries = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear | Sort-Object VerificationNumber)
            $entries.Count | Should -Be 2
            $entries[0].VerificationNumber | Should -Be 1
            $entries[0].Description | Should -Be 'Försäljning'
            $entries[1].VerificationNumber | Should -Be 2
            $entries[1].Description | Should -Be 'Inköp'

            (Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear | Where-Object Description -eq 'Ingående balans') |
                Should -BeNullOrEmpty
        }

        It 'Should report the number of migrated rows and renumbered verifications' {
            $result = Convert-LedgerOpeningBalance -JournalPath $JournalPath
            $result.FiscalYear | Should -Be $FiscalYear
            $result.OpeningBalanceRows | Should -Be 2
            $result.RenumberedVerifications | Should -Be 2
        }

        It 'Should be idempotent when run twice' {
            Convert-LedgerOpeningBalance -JournalPath $JournalPath | Out-Null
            $second = Convert-LedgerOpeningBalance -JournalPath $JournalPath

            $second | Should -BeNullOrEmpty
            $entries = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear)
            $entries.Count | Should -Be 2
        }

        It 'Should not change anything when -WhatIf is used' {
            Convert-LedgerOpeningBalance -JournalPath $JournalPath -WhatIf | Out-Null

            Test-Path (Join-Path $YearDir 'ib.txt') | Should -BeFalse
            $entries = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear | Sort-Object VerificationNumber)
            ($entries | Where-Object Description -eq 'Ingående balans') | Should -Not -BeNullOrEmpty
        }

        It 'Should skip a fiscal year that already has ib.txt' {
            "1910`t100" | Set-Content -Path (Join-Path $YearDir 'ib.txt') -Encoding UTF8
            $result = Convert-LedgerOpeningBalance -JournalPath $JournalPath

            $result | Should -BeNullOrEmpty
            # ver0001 (legacy opening balance) is left untouched.
            Test-Path (Join-Path $YearDir 'ver0003.txt') | Should -BeTrue
        }

        It 'Should skip a fiscal year whose first verification is not an opening balance' {
            $OtherName = [System.IO.Path]::GetRandomFileName()
            $OtherJournal = Join-Path $TestDrive "$OtherName.ledger"
            New-LedgerJournal -Path $OtherJournal -Name 'Normal AB'
            Add-LedgerAccount -JournalPath $OtherJournal -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $OtherJournal -AccountNumber '3010' -AccountName 'Försäljning'
            New-LedgerFiscalYear -JournalPath $OtherJournal -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerEntry -JournalPath $OtherJournal -FiscalYear '2024-01_2024-12' -Date '2024-05-01' -Description 'Vanlig' -Rows @(
                @{ Account = '1910'; Amount = 100 }
                @{ Account = '3010'; Amount = -100 }
            )

            $result = Convert-LedgerOpeningBalance -JournalPath $OtherJournal
            $result | Should -BeNullOrEmpty
            Test-Path (Join-Path $OtherJournal '2024-01_2024-12' 'ib.txt') | Should -BeFalse
        }

        It 'Should rename attachment directories along with their verifications' {
            $attachDir = Join-Path $YearDir 'ver0002'
            New-Item -ItemType Directory -Path $attachDir | Out-Null
            'kvitto' | Set-Content -Path (Join-Path $attachDir 'faktura.txt') -Encoding UTF8

            Convert-LedgerOpeningBalance -JournalPath $JournalPath | Out-Null

            # ver0002 (Försäljning) became ver0001, so its attachment dir moved too.
            Test-Path (Join-Path $YearDir 'ver0001' 'faktura.txt') | Should -BeTrue
            Test-Path $attachDir | Should -BeFalse
        }
    }
}
