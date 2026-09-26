BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerEquityReconciliation' {
    BeforeAll {
        $CommandName = 'Get-LedgerEquityReconciliation'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have an optional FiscalYear parameter that binds from Name' {
            $Param = $Command.Parameters['FiscalYear']
            $Param.Aliases | Should -Contain 'Name'
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'equity.ledger'
            New-LedgerJournal -Path $jp -Name 'Eget Kapital AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2081' -AccountName 'Aktiekapital'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2091' -AccountName 'Balanserat resultat'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2099' -AccountName 'Årets resultat'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '8999' -AccountName 'Årets resultat'

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2023-01-01' -EndDate '2023-12-31'
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-01-02' -Description 'Aktiekapital' -Rows @(
                @{ Account = '1910'; Amount = 100000 }, @{ Account = '2081'; Amount = -100000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-06-01' -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 50000 }, @{ Account = '3010'; Amount = -50000 })
            Close-LedgerFiscalYear -JournalPath $jp -FiscalYear '2023-01_2023-12'

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Copy-LedgerOpeningBalance -JournalPath $jp -FromFiscalYear '2023-01_2023-12' -ToFiscalYear '2024-01_2024-12'
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-06-01' -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 30000 }, @{ Account = '3010'; Amount = -30000 })
        }

        It 'Should report share capital opening and closing' {
            $rows = Get-LedgerEquityReconciliation -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $share = $rows | Where-Object { $_.Component -eq 'ShareCapital' }
            $share.OpeningBalance | Should -Be 100000
            $share.ClosingBalance | Should -Be 100000
        }

        It 'Should carry the previous year result into retained earnings opening' {
            $rows = Get-LedgerEquityReconciliation -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $retained = $rows | Where-Object { $_.Component -eq 'RetainedEarnings' }
            $retained.OpeningBalance | Should -Be 50000
        }

        It 'Should report the current year result on its own line' {
            $rows = Get-LedgerEquityReconciliation -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $result = $rows | Where-Object { $_.Component -eq 'YearResult' }
            $result.OpeningBalance | Should -Be 0
            $result.ClosingBalance | Should -Be 30000
        }

        It 'Should produce a total that reconciles to the balance sheet equity and result' {
            $rows = Get-LedgerEquityReconciliation -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $total = $rows | Where-Object { $_.Component -eq 'Total' }
            $total.ClosingBalance | Should -Be 180000

            $bs = Get-LedgerBalanceSheet -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $equity = ($bs | Where-Object { $_.Group -eq 'Equity' }).Amount
            $result = ($bs | Where-Object { $_.Group -eq 'Result' }).Amount
            $total.ClosingBalance | Should -Be (-($equity + $result))
        }

        It 'Should return nothing for an empty fiscal year' {
            $empty = Join-Path $TestDrive 'emptyeq.ledger'
            New-LedgerJournal -Path $empty -Name 'Tom AB' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $empty -StartDate '2024-01-01' -EndDate '2024-12-31'
            Get-LedgerEquityReconciliation -JournalPath $empty -FiscalYear '2024-01_2024-12' | Should -BeNullOrEmpty
        }
    }

    Context 'Behavior with dividend' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'equitydiv.ledger'
            New-LedgerJournal -Path $jp -Name 'Utdelning AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2081' -AccountName 'Aktiekapital'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2091' -AccountName 'Balanserat resultat'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2099' -AccountName 'Årets resultat'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '8999' -AccountName 'Årets resultat'

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2023-01-01' -EndDate '2023-12-31'
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-01-02' -Description 'Aktiekapital' -Rows @(
                @{ Account = '1910'; Amount = 100000 }, @{ Account = '2081'; Amount = -100000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-06-01' -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 50000 }, @{ Account = '3010'; Amount = -50000 })
            Close-LedgerFiscalYear -JournalPath $jp -FiscalYear '2023-01_2023-12'

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Copy-LedgerOpeningBalance -JournalPath $jp -FromFiscalYear '2023-01_2023-12' -ToFiscalYear '2024-01_2024-12'
            # Dividend of 20000 paid out of retained earnings.
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-03-01' -Description 'Utdelning' -Rows @(
                @{ Account = '2091'; Amount = 20000 }, @{ Account = '1910'; Amount = -20000 })
        }

        It 'Should show the dividend as a negative change in retained earnings' {
            $rows = Get-LedgerEquityReconciliation -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $retained = $rows | Where-Object { $_.Component -eq 'RetainedEarnings' }
            $retained.OpeningBalance | Should -Be 50000
            $retained.Change | Should -Be -20000
            $retained.ClosingBalance | Should -Be 30000
        }
    }

    Context 'Behavior with resultatdisposition booked during the year' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'equitydisp.ledger'
            New-LedgerJournal -Path $jp -Name 'Disposition AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            foreach ($a in @(@('1910', 'Kassa'), @('2081', 'Aktiekapital'), @('2091', 'Balanserat resultat'),
                    @('2099', 'Årets resultat'), @('3010', 'Försäljning'), @('5010', 'Lokalhyra'), @('8999', 'Årets resultat'))) {
                Add-LedgerAccount -JournalPath $jp -AccountNumber $a[0] -AccountName $a[1]
            }

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2023-01-01' -EndDate '2023-12-31'
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-01-02' -Description 'Aktiekapital' -Rows @(
                @{ Account = '1910'; Amount = 100000 }, @{ Account = '2081'; Amount = -100000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-06-01' -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 50000 }, @{ Account = '3010'; Amount = -50000 })
            Close-LedgerFiscalYear -JournalPath $jp -FiscalYear '2023-01_2023-12'

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Copy-LedgerOpeningBalance -JournalPath $jp -FromFiscalYear '2023-01_2023-12' -ToFiscalYear '2024-01_2024-12'
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-05-01' -Description 'Resultatdisposition' -Rows @(
                @{ Account = '2099'; Amount = 50000 }, @{ Account = '2091'; Amount = -50000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-06-01' -Description 'Hyra' -Rows @(
                @{ Account = '5010'; Amount = 10000 }, @{ Account = '1910'; Amount = -10000 })
        }

        It 'Should not count a disposed prior-year result twice' {
            $rows = Get-LedgerEquityReconciliation -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $retained = $rows | Where-Object { $_.Component -eq 'RetainedEarnings' }
            $result = $rows | Where-Object { $_.Component -eq 'YearResult' }
            $retained.OpeningBalance | Should -Be 50000
            $retained.ClosingBalance | Should -Be 50000
            $result.ClosingBalance | Should -Be -10000
            ($rows | Where-Object { $_.Component -eq 'Total' }).ClosingBalance | Should -Be 140000
        }

        It 'Should report the result of a closed year on the Årets resultat line' {
            Close-LedgerFiscalYear -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $rows = Get-LedgerEquityReconciliation -JournalPath $jp -FiscalYear '2024-01_2024-12'
            ($rows | Where-Object { $_.Component -eq 'RetainedEarnings' }).ClosingBalance | Should -Be 50000
            ($rows | Where-Object { $_.Component -eq 'YearResult' }).ClosingBalance | Should -Be -10000
        }
    }
}
