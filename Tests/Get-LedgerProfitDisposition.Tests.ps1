BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerProfitDisposition' {
    BeforeAll {
        $CommandName = 'Get-LedgerProfitDisposition'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a Dividend parameter of type Decimal' {
            $Command.Parameters['Dividend'].ParameterType.Name | Should -Be 'Decimal'
        }

        It 'Should have a NumberOfShares parameter of type Int32' {
            $Command.Parameters['NumberOfShares'].ParameterType.Name | Should -Be 'Int32'
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'disp.ledger'
            New-LedgerJournal -Path $jp -Name 'Disposition AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            Set-LedgerJournal -JournalPath $jp -Metadata @{ NumberOfShares = '1000' }
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

        It 'Should sum retained earnings and year result into disposable earnings' {
            $d = Get-LedgerProfitDisposition -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $d.RetainedEarnings | Should -Be 50000
            $d.YearResult | Should -Be 30000
            $d.TotalDisposable | Should -Be 80000
        }

        It 'Should carry everything forward when there is no dividend' {
            $d = Get-LedgerProfitDisposition -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $d.ProposedDividend | Should -Be 0
            $d.CarriedForward | Should -Be 80000
        }

        It 'Should split disposable earnings between dividend and carried forward' {
            $d = Get-LedgerProfitDisposition -JournalPath $jp -FiscalYear '2024-01_2024-12' -Dividend 20000
            $d.ProposedDividend | Should -Be 20000
            $d.CarriedForward | Should -Be 60000
        }

        It 'Should compute dividend per share from journal metadata' {
            $d = Get-LedgerProfitDisposition -JournalPath $jp -FiscalYear '2024-01_2024-12' -Dividend 20000
            $d.NumberOfShares | Should -Be 1000
            $d.DividendPerShare | Should -Be 20
        }

        It 'Should use the recorded ProposedDividend when -Dividend is omitted' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear '2024-01_2024-12' -ProposedDividend '10000'
            $d = Get-LedgerProfitDisposition -JournalPath $jp -FiscalYear '2024-01_2024-12'
            $d.ProposedDividend | Should -Be 10000
            $d.CarriedForward | Should -Be 70000
        }

        It 'Should override the number of shares when provided' {
            $d = Get-LedgerProfitDisposition -JournalPath $jp -FiscalYear '2024-01_2024-12' -Dividend 20000 -NumberOfShares 2000
            $d.DividendPerShare | Should -Be 10
        }
    }
}
