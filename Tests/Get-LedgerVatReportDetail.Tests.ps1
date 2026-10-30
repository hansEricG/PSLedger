BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1') -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')
}

Describe 'Get-LedgerVatReportDetail' {
    Context 'Function metadata' {
        It 'Should expose an advanced function with the same period parameters as the summary' {
            $command = Get-Command Get-LedgerVatReportDetail
            Test-TDDCmdletBinding $command | Should -BeTrue
            foreach ($name in 'FromDate', 'ToDate') {
                $command.Parameters[$name].ParameterType | Should -Be ([datetime])
                $command.Parameters[$name].Attributes.Mandatory | Should -Contain $true
            }
            foreach ($name in 'JournalPath', 'FiscalYear') {
                $command.Parameters[$name].ParameterType | Should -Be ([string])
                $command.Parameters[$name].Attributes.Mandatory | Should -Not -Contain $true
            }
            $command.Parameters['FiscalYear'].Aliases | Should -Contain 'Name'
            $command.Parameters['FiscalYear'].Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $journal = New-TestLedger -Root $TestDrive -NoChart -Name 'Konsultbyrån AB'
            $year = '2024-01_2024-12'
            foreach ($account in '1930', '2610', '2640', '3010', '3060', '3212', '3300', '3308', '5010') {
                Add-LedgerAccount -JournalPath $journal -AccountNumber $account -AccountName "Konto $account"
            }
            Add-LedgerEntry -JournalPath $journal -FiscalYear $year -Date '2024-01-15' -Description 'Försäljning' -Rows @(
                @{ Account = '1930'; Amount = 8250 }
                @{ Account = '3010'; Amount = -1000 }
                @{ Account = '2610'; Amount = -250 }
                @{ Account = '3308'; Amount = -6000 }
                @{ Account = '3212'; Amount = -1000 }
            )
            Add-LedgerEntry -JournalPath $journal -FiscalYear $year -Date '2024-01-16' -Description 'Inköp' -Rows @(
                @{ Account = '5010'; Amount = 400 }
                @{ Account = '2640'; Amount = 100 }
                @{ Account = '1930'; Amount = -500 }
            )
            $period = @{ JournalPath = $journal; FiscalYear = $year; FromDate = '2024-01-01'; ToDate = '2024-01-31' }
        }

        It 'Should explain amounts, signs, rules and explicit exclusions without modifying the journal' {
            $before = Get-ChildItem -LiteralPath $journal -Recurse -File | Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
            $rows = @(Get-LedgerVatReportDetail @period)
            $rows.AccountNumber | Should -Be @('1930', '2610', '2640', '3010', '3212', '3308', '5010')
            $eu = $rows | Where-Object AccountNumber -eq '3308'
            $eu.AccountName | Should -Be 'Konto 3308'
            $eu.Balance | Should -Be -6000
            $eu.Amount | Should -Be 6000
            $eu.Box | Should -Be 39
            $eu.Source | Should -Be 'BAS'
            $eu.Rule | Should -Be '3308'
            $eu.Status | Should -Be 'Mapped'
            ($rows | Where-Object AccountNumber -eq '2610').Amount | Should -Be 250
            ($rows | Where-Object AccountNumber -eq '2640').Amount | Should -Be 100
            ($rows | Where-Object AccountNumber -eq '3010').Status | Should -Be 'Implicit'

            $excluded = $rows | Where-Object AccountNumber -eq '3212'
            $excluded.Balance | Should -Be -1000
            $excluded.Source | Should -Be 'BAS'
            $excluded.Status | Should -Be 'Excluded'
            $excluded.Box | Should -BeNullOrEmpty
            $excluded.Amount | Should -BeNullOrEmpty
            $bank = $rows | Where-Object AccountNumber -eq '1930'
            $bank.Balance | Should -Be 7750
            $bank.Source | Should -Be 'None'
            $bank.Status | Should -Be 'Unmapped'
            $bank.Rule | Should -BeNullOrEmpty
            $bank.Amount | Should -BeNullOrEmpty
            $after = Get-ChildItem -LiteralPath $journal -Recurse -File | Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
            $after | Should -Be $before
        }

        It 'Should expose first-match override rules and reconcile every box with the summary' {
            Set-Content -LiteralPath (Join-Path $journal 'vat.txt') -Value @("3060-3069`t39", "3060`t40", "2640-2649`t-")
            Add-LedgerEntry -JournalPath $journal -FiscalYear $year -Date '2024-01-20' -Description 'EU-uppdrag' -Rows @(
                @{ Account = '1930'; Amount = 500 }
                @{ Account = '3060'; Amount = -500 }
            )
            $details = @(Get-LedgerVatReportDetail @period)
            $custom = $details | Where-Object AccountNumber -eq '3060'
            $custom.Source | Should -Be 'vat.txt'
            $custom.Rule | Should -Be '3060-3069'
            $custom.Box | Should -Be 39
            $custom.Amount | Should -Be 500
            $excluded = $details | Where-Object AccountNumber -eq '2640'
            $excluded.Source | Should -Be 'vat.txt'
            $excluded.Status | Should -Be 'Excluded'
            $excluded.Amount | Should -BeNullOrEmpty
            $summary = @(Get-LedgerVatReport @period)
            foreach ($box in $summary | Where-Object Box -ne 49) {
                $sum = [decimal]0
                foreach ($detail in $details | Where-Object Box -eq $box.Box) { $sum += $detail.Amount }
                $box.Amount | Should -Be $sum
            }
            ($summary | Where-Object Box -eq 39).Amount | Should -Be 6500
            ($summary | Where-Object Box -eq 49).Amount | Should -Be 250
        }

        It 'Should include both date boundaries and exclude opening balances' {
            Set-Content -LiteralPath (Join-Path $journal $year 'ib.txt') -Value @("1930`t100", "2610`t-100")
            foreach ($date in '2024-01-14', '2024-01-17') {
                Add-LedgerEntry -JournalPath $journal -FiscalYear $year -Date $date -Description 'Utanför perioden' -Rows @(
                    @{ Account = '1930'; Amount = 500 }
                    @{ Account = '3308'; Amount = -500 }
                )
            }
            $period.FromDate = '2024-01-15'
            $period.ToDate = '2024-01-16'
            $details = @(Get-LedgerVatReportDetail @period)
            ($details | Where-Object AccountNumber -eq '3308').Amount | Should -Be 6000
            ($details | Where-Object AccountNumber -eq '2610').Amount | Should -Be 250
            ($details | Where-Object AccountNumber -eq '2640').Amount | Should -Be 100
        }

        It 'Should retain zero-net accounts and negative credit-note contributions' {
            Add-LedgerReversal -JournalPath $journal -FiscalYear $year -VerificationNumber 1 -Date '2024-01-20'
            $details = @(Get-LedgerVatReportDetail @period)
            ($details | Where-Object AccountNumber -eq '3308').Amount | Should -Be 0
            $period.FromDate = '2024-01-20'
            $credits = @(Get-LedgerVatReportDetail @period)
            ($credits | Where-Object AccountNumber -eq '3308').Amount | Should -Be -6000
            ($credits | Where-Object AccountNumber -eq '2610').Amount | Should -Be -250
        }

        It 'Should identify and warn about implicit mappings for foreign sales' {
            Add-LedgerEntry -JournalPath $journal -FiscalYear $year -Date '2024-01-20' -Description 'Omappad försäljning' -Rows @(
                @{ Account = '1930'; Amount = 500 }
                @{ Account = '3300'; Amount = -500 }
            )
            $details = @(Get-LedgerVatReportDetail @period -WarningVariable warnings -WarningAction SilentlyContinue)
            $implicit = $details | Where-Object AccountNumber -eq '3300'
            $implicit.Status | Should -Be 'Implicit'
            $implicit.Box | Should -Be 5
            $implicit.Rule | Should -Be '3000-3799'
            $warnings | Should -HaveCount 1
            "$warnings" | Should -BeLike '*3300*vat.txt*'
        }

        It 'Should reject an invalid date interval in both detail and summary reports' {
            $period.ToDate = '2023-12-31'
            { Get-LedgerVatReportDetail @period } | Should -Throw '*must not be earlier*'
            { Get-LedgerVatReport @period } | Should -Throw '*must not be earlier*'
        }

        It 'Should return no detail rows for an empty period and reject malformed mappings' {
            $period.FromDate = '2024-02-01'
            $period.ToDate = '2024-02-29'
            Get-LedgerVatReportDetail @period | Should -BeNullOrEmpty
            Set-Content -LiteralPath (Join-Path $journal 'vat.txt') -Value "3308`t99"
            { Get-LedgerVatReportDetail @period } | Should -Throw '*not a VAT declaration box*'
        }
    }
}
