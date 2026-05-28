BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerEntry with Objects' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Obj AB'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '5010' -AccountName 'Lokalhyra'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Kostnadsställe'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 2 -Name 'Projekt'
            Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber 'sthlm' -Name 'Stockholm'
            Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 2 -ObjectNumber 'proj-a' -Name 'Projekt Alpha'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'
        }

        It 'Should write object tags to verification file' {
            $rows = @(
                @{ Account = '5010'; Amount = 8000; Objects = @{1='sthlm'; 2='proj-a'} }
                @{ Account = '1910'; Amount = -8000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Hyra med objekt' -Rows $rows

            $content = Get-Content (Join-Path $JournalPath $FiscalYear 'ver0001.txt') -Raw
            $content | Should -Match '\{1:sthlm,2:proj-a\}'
        }

        It 'Should read back Objects from verification' {
            $rows = @(
                @{ Account = '5010'; Amount = 8000; Objects = @{1='sthlm'} }
                @{ Account = '1910'; Amount = -8000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Hyra' -Rows $rows

            $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber 1
            $row5010 = $entry.Rows | Where-Object Account -eq '5010'
            $row5010.Objects | Should -Not -BeNullOrEmpty
            $row5010.Objects[1] | Should -Be 'sthlm'
            $row1910 = $entry.Rows | Where-Object Account -eq '1910'
            $row1910.Objects | Should -BeNullOrEmpty
        }

        It 'Should throw if dimension does not exist' {
            $rows = @(
                @{ Account = '5010'; Amount = 8000; Objects = @{99='x'} }
                @{ Account = '1910'; Amount = -8000 }
            )
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Bad dim' -Rows $rows } |
                Should -Throw '*Dimension 99*'
        }

        It 'Should throw if object does not exist in dimension' {
            $rows = @(
                @{ Account = '5010'; Amount = 8000; Objects = @{1='nonexist'} }
                @{ Account = '1910'; Amount = -8000 }
            )
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Bad obj' -Rows $rows } |
                Should -Throw '*nonexist*'
        }

        It 'Should work without objects (backward compatibility)' {
            $rows = @(
                @{ Account = '5010'; Amount = 8000 }
                @{ Account = '1910'; Amount = -8000 }
            )
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Utan objekt' -Rows $rows } |
                Should -Not -Throw
        }
    }
}
