BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerEntry with row comments' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Kommentar AB'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '5010' -AccountName 'Lokalhyra'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Kostnadsställe'
            Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber 'sthlm' -Name 'Stockholm'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'
        }

        It 'Should write and read back a per-row comment' {
            $rows = @(
                @{ Account = '5010'; Amount = 8000; Comment = 'Hyra mars' }
                @{ Account = '1910'; Amount = -8000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Hyra' -Rows $rows

            $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1
            $row5010 = $entry.Rows | Where-Object Account -eq '5010'
            $row5010.Comment | Should -Be 'Hyra mars'
            $row1910 = $entry.Rows | Where-Object Account -eq '1910'
            $row1910.Comment | Should -BeNullOrEmpty
        }

        It 'Should read back both Objects and Comment on the same row' {
            $rows = @(
                @{ Account = '5010'; Amount = 8000; Objects = @{1='sthlm'}; Comment = 'Hyra Stockholm' }
                @{ Account = '1910'; Amount = -8000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Hyra med objekt och kommentar' -Rows $rows

            $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1
            $row5010 = $entry.Rows | Where-Object Account -eq '5010'
            $row5010.Objects[1] | Should -Be 'sthlm'
            $row5010.Comment | Should -Be 'Hyra Stockholm'
        }

        It 'Should support comments via New-LedgerEntryRow' {
            $rows = @(
                New-LedgerEntryRow -Debit '5010' 8000 -Comment 'Hyra mars'
                New-LedgerEntryRow -Credit '1910' 8000
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Hyra' -Rows $rows

            $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1
            ($entry.Rows | Where-Object Account -eq '5010').Comment | Should -Be 'Hyra mars'
        }

        It 'Should sanitize tabs and newlines in a comment' {
            $rows = @(
                @{ Account = '5010'; Amount = 8000; Comment = "Rad1`tkol`r`nRad2" }
                @{ Account = '1910'; Amount = -8000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Hyra' -Rows $rows

            $verFile = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            # The 5010 row must remain a single line with the account/amount intact
            $rowLine = (Get-Content $verFile) | Where-Object { $_ -like '5010*' }
            @($rowLine).Count | Should -Be 1

            $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1
            ($entry.Rows | Where-Object Account -eq '5010').Comment | Should -Be 'Rad1 kol Rad2'
        }

        It 'Should read rows without a comment as null (backward compatibility)' {
            $rows = @(
                @{ Account = '5010'; Amount = 8000 }
                @{ Account = '1910'; Amount = -8000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Utan kommentar' -Rows $rows

            $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1
            foreach ($row in $entry.Rows) {
                $row.Comment | Should -BeNullOrEmpty
            }
        }
    }
}
