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
