BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'SIE round-trip' {
    Context 'Export then import yields identical data' {
        BeforeEach {
            $Suffix = [System.IO.Path]::GetRandomFileName()
            $JournalA = Join-Path $TestDrive "a-$Suffix.ledger"
            New-LedgerJournal -Path $JournalA -Name 'Round AB' -OrgNumber '556677-8899'
            Add-LedgerAccount -JournalPath $JournalA -AccountNumber '1910' -AccountName 'Kassa och bank'
            Add-LedgerAccount -JournalPath $JournalA -AccountNumber '2440' -AccountName 'Leverantörsskulder'
            Add-LedgerAccount -JournalPath $JournalA -AccountNumber '2640' -AccountName 'Ingående moms'
            Add-LedgerAccount -JournalPath $JournalA -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $JournalA -AccountNumber '5010' -AccountName 'Lokalhyra'
            New-LedgerFiscalYear -JournalPath $JournalA -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'

            Add-LedgerEntry -JournalPath $JournalA -FiscalYear $FiscalYear `
                -Date '2024-03-15' -Description 'Försäljning kontant' -Rows @(
                    @{ Account = '1910'; Amount = 1250.50 }
                    @{ Account = '3010'; Amount = -1250.50 }
                )
            Add-LedgerEntry -JournalPath $JournalA -FiscalYear $FiscalYear `
                -Date '2024-04-01' -Description 'Hyra kontor å andra våningen' -Rows @(
                    @{ Account = '5010'; Amount = 8000 }
                    @{ Account = '2640'; Amount = 2000 }
                    @{ Account = '2440'; Amount = -10000 }
                )
        }

        It 'Should produce identical entries after export -> import -> export' {
            $SieFile1 = Join-Path $TestDrive 'first.se'
            Export-LedgerSie -JournalPath $JournalA -FiscalYear $FiscalYear -Path $SieFile1

            $JournalB = Join-Path $TestDrive 'b.ledger'
            New-LedgerJournal -Path $JournalB -Name 'Round AB' -OrgNumber '556677-8899'
            New-LedgerFiscalYear -JournalPath $JournalB -StartDate '2024-01-01' -EndDate '2024-12-31'
            Import-LedgerSie -JournalPath $JournalB -FiscalYear $FiscalYear -Path $SieFile1 -CreateMissingAccounts

            $SieFile2 = Join-Path $TestDrive 'second.se'
            Export-LedgerSie -JournalPath $JournalB -FiscalYear $FiscalYear -Path $SieFile2

            $entriesA = @(Get-LedgerEntry -JournalPath $JournalA -FiscalYear $FiscalYear | Sort-Object VerificationNumber)
            $entriesB = @(Get-LedgerEntry -JournalPath $JournalB -FiscalYear $FiscalYear | Sort-Object VerificationNumber)

            $entriesB.Count | Should -Be $entriesA.Count
            for ($i = 0; $i -lt $entriesA.Count; $i++) {
                $entriesB[$i].Date | Should -Be $entriesA[$i].Date
                $entriesB[$i].Description | Should -Be $entriesA[$i].Description
                $entriesB[$i].Rows.Count | Should -Be $entriesA[$i].Rows.Count
                for ($j = 0; $j -lt $entriesA[$i].Rows.Count; $j++) {
                    $entriesB[$i].Rows[$j].Account | Should -Be $entriesA[$i].Rows[$j].Account
                    $entriesB[$i].Rows[$j].Amount  | Should -Be $entriesA[$i].Rows[$j].Amount
                }
            }
        }

        It 'Should produce SIE bodies that differ only in the #GEN date' {
            $SieFile1 = Join-Path $TestDrive 'rt1.se'
            Export-LedgerSie -JournalPath $JournalA -FiscalYear $FiscalYear -Path $SieFile1

            $JournalB = Join-Path $TestDrive 'rtb.ledger'
            New-LedgerJournal -Path $JournalB -Name 'Round AB' -OrgNumber '556677-8899'
            New-LedgerFiscalYear -JournalPath $JournalB -StartDate '2024-01-01' -EndDate '2024-12-31'
            Import-LedgerSie -JournalPath $JournalB -FiscalYear $FiscalYear -Path $SieFile1 -CreateMissingAccounts

            $SieFile2 = Join-Path $TestDrive 'rt2.se'
            Export-LedgerSie -JournalPath $JournalB -FiscalYear $FiscalYear -Path $SieFile2

            $enc = [System.Text.Encoding]::GetEncoding(437)
            $textA = [System.IO.File]::ReadAllText($SieFile1, $enc) -replace '#GEN \d+', '#GEN <date>'
            $textB = [System.IO.File]::ReadAllText($SieFile2, $enc) -replace '#GEN \d+', '#GEN <date>'
            $textB | Should -Be $textA
        }
    }
}
