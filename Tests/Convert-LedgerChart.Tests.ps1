BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Convert-LedgerChart' {
    BeforeAll {
        $CommandName = 'Convert-LedgerChart'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding that supports ShouldProcess' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
            $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }

        It 'Should have optional JournalPath, FiscalYear (binding from Name) and Date parameters' {
            foreach ($p in 'JournalPath', 'FiscalYear', 'Date') {
                $Command.Parameters[$p] | Should -Not -BeNullOrEmpty
                $Command.Parameters[$p].Attributes.Mandatory | Should -Not -Contain $true
            }
            $Command.Parameters['FiscalYear'].Aliases | Should -Contain 'Name'
            $Command.Parameters['Date'].ParameterType | Should -Be ([datetime])
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Konsultbyrån AB' -OrgNumber '556677-8899'
            foreach ($a in @(
                    @('1930', 'Företagskonto'), @('2440', 'Leverantörsskulder')
                    @('3300', 'Försäljning tjänster inom EU'), @('4531', 'Tull')
                    @('3200', 'Försäljning utrikes'), @('3050', 'Försäljning tjänster momsfri')
                )) {
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $a[0] -AccountName $a[1]
            }
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-01-01' -EndDate '2025-12-31'
            $FiscalYear = '2025-01_2025-12'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-02-10' `
                -Description 'Konsultuppdrag Tyskland' -Rows @(
                    @{ Account = '1930'; Amount = 8000 }
                    @{ Account = '3300'; Amount = -8000 }
                )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-02-12' `
                -Description 'Tull på leverans' -Rows @(
                    @{ Account = '4531'; Amount = 500 }
                    @{ Account = '2440'; Amount = -500 }
                )
        }

        It 'Should add the BAS accounts and report the converted and ambiguous legacy accounts' {
            $result = Convert-LedgerChart -JournalPath $JournalPath -WarningVariable warnings -WarningAction SilentlyContinue

            (Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '3308').AccountName |
                Should -Be 'Försäljning tjänster till annat EU-land'
            Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '3004' | Should -Not -BeNullOrEmpty
            Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '5720' | Should -Not -BeNullOrEmpty
            Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '3300' | Should -Not -BeNullOrEmpty

            ($result | Where-Object Account -eq '3300').NewAccount | Should -Be '3308'
            ($result | Where-Object Account -eq '3200').Status | Should -Be 'Ambiguous'
            $warnings | Should -HaveCount 1
            "$warnings" | Should -BeLike '*3200*'
        }

        It 'Should write vat.txt rules so booked amounts land in the right VAT box' {
            Convert-LedgerChart -JournalPath $JournalPath -WarningAction SilentlyContinue | Out-Null

            $report = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2025-01-01' -ToDate '2025-03-31' -WarningAction SilentlyContinue
            ($report | Where-Object Box -eq 39).Amount | Should -Be 8000
            ($report | Where-Object Box -eq 5).Amount | Should -Be 0
            $report | Where-Object Box -eq 22 | Should -BeNullOrEmpty
        }

        It 'Should keep existing vat.txt rules and give them precedence' {
            Set-Content -LiteralPath (Join-Path $JournalPath 'vat.txt') -Encoding UTF8 -Value "3300`t40"

            $result = Convert-LedgerChart -JournalPath $JournalPath -WarningAction SilentlyContinue

            ($result | Where-Object Account -eq '3300').VatRule | Should -BeFalse
            ($result | Where-Object Account -eq '3300').Box | Should -Be 40
            $report = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2025-01-01' -ToDate '2025-03-31' -WarningAction SilentlyContinue
            ($report | Where-Object Box -eq 40).Amount | Should -Be 8000
        }

        It 'Should book a VAT-neutral transfer verification with -Date' {
            $result = Convert-LedgerChart -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-03-01' -WarningAction SilentlyContinue

            ($result | Where-Object Account -eq '3300').Transferred | Should -Be -8000
            $transfer = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 3
            $transfer.Description | Should -Be 'Omföring till BAS-konton'
            ($transfer.Rows | Where-Object Account -eq '3308').Amount | Should -Be -8000
            ($transfer.Rows | Where-Object Account -eq '3300').Amount | Should -Be 8000
            ($transfer.Rows | Where-Object Account -eq '5720').Amount | Should -Be 500

            $balances = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            ($balances | Where-Object AccountNumber -eq '3300').Balance | Should -Be 0
            $report = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2025-01-01' -ToDate '2025-03-31' -WarningAction SilentlyContinue
            ($report | Where-Object Box -eq 39).Amount | Should -Be 8000
            $transferPeriod = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2025-03-01' -ToDate '2025-03-31' -WarningAction SilentlyContinue
            $transferPeriod | Where-Object Amount -ne 0 | Should -BeNullOrEmpty
        }

        It 'Should convert opening balances and be safe to run again' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2660' -AccountName 'Moms omvänd skattskyldighet'
            Set-Content -LiteralPath (Join-Path $JournalPath $FiscalYear 'ib.txt') -Value @("1930`t1000", "2660`t-1000")

            $result = Convert-LedgerChart -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-03-01' -WarningAction SilentlyContinue
            ($result | Where-Object Account -eq '2660').Transferred | Should -Be -1000
            $balances = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            ($balances | Where-Object AccountNumber -eq '2660').Balance | Should -Be 0
            ($balances | Where-Object AccountNumber -eq '2614').Balance | Should -Be -1000

            Convert-LedgerChart -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-03-01' -WarningAction SilentlyContinue | Out-Null
            @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear) | Should -HaveCount 3
            (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear).IsValid | Should -BeTrue
        }

        It 'Should reject conflicting <Rule> rules before changing any files' -ForEach @(
            @{ Rule = "3300`t40" }
            @{ Rule = "3300`t-" }
            @{ Rule = "3308`t40" }
            @{ Rule = "3308`t-" }
        ) {
            Set-Content -LiteralPath (Join-Path $JournalPath 'vat.txt') -Value $Rule
            $before = Get-ChildItem -LiteralPath $JournalPath -Recurse -File | Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }

            { Convert-LedgerChart -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-03-01' -WarningAction SilentlyContinue } |
                Should -Throw '*conflicting VAT rules*'

            $after = Get-ChildItem -LiteralPath $JournalPath -Recurse -File | Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
            $after | Should -Be $before
        }

        It 'Should preserve VAT neutrality when both accounts use the same override' {
            Set-Content -LiteralPath (Join-Path $JournalPath 'vat.txt') -Value "3300-3399`t40"
            Convert-LedgerChart -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-03-01' -WarningAction SilentlyContinue | Out-Null

            $period = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2025-03-01' -ToDate '2025-03-31' -WarningAction SilentlyContinue
            $period | Where-Object Amount -ne 0 | Should -BeNullOrEmpty
            $quarter = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2025-01-01' -ToDate '2025-03-31' -WarningAction SilentlyContinue
            ($quarter | Where-Object Box -eq 40).Amount | Should -Be 8000
        }

        It 'Should reject <Case> before changing any files' -ForEach @(
            @{ Case = 'a closed year'; Setup = { Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear -SkipResultEntry | Out-Null }; TransferDate = '2025-03-01'; ExpectedError = '*Closed*' }
            @{ Case = 'a date outside the year'; Setup = {}; TransferDate = '2026-03-01'; ExpectedError = '*outside fiscal year*' }
            @{ Case = 'missing year metadata'; Setup = { Remove-Item -LiteralPath (Join-Path $JournalPath $FiscalYear 'year.txt') }; TransferDate = '2025-03-01'; ExpectedError = '*year.txt not found*' }
            @{ Case = 'fractional opening balance amounts'; Setup = { Set-Content -LiteralPath (Join-Path $JournalPath $FiscalYear 'ib.txt') -Value @("1930`t10.005", "3300`t-10.005") }; TransferDate = '2025-03-01'; ExpectedError = '*more than two decimals*' }
        ) {
            & $Setup
            $before = Get-ChildItem -LiteralPath $JournalPath -Recurse -File | Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }

            { Convert-LedgerChart -JournalPath $JournalPath -FiscalYear $FiscalYear -Date $TransferDate -WarningAction SilentlyContinue } |
                Should -Throw $ExpectedError

            $after = Get-ChildItem -LiteralPath $JournalPath -Recurse -File | Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
            $after | Should -Be $before
        }

        It 'Should change nothing with -WhatIf' {
            Convert-LedgerChart -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-03-01' -WhatIf -WarningAction SilentlyContinue | Out-Null

            Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '3308' | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $JournalPath 'vat.txt') | Should -BeFalse
            @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear) | Should -HaveCount 2
        }

        It 'Should leave accounts alone whose name does not match the legacy template' {
            $other = Join-Path $TestDrive 'Annan.ledger'
            New-LedgerJournal -Path $other -Name 'Annan AB'
            Add-LedgerAccount -JournalPath $other -AccountNumber '3300' -AccountName 'Försäljning av tjänster utanför Sverige'

            Convert-LedgerChart -JournalPath $other | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $other 'vat.txt') | Should -BeFalse
        }
    }
}
