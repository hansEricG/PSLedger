BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
}

Describe 'SIE Dimensions round-trip' {
    BeforeAll {
        $jp = Join-Path $TestDrive 'dimtest.ledger'
        New-LedgerJournal -Path $jp -Name 'DimTest AB' -OrgNumber '556677-8899'
        New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
        Add-LedgerAccount -JournalPath $jp -AccountNumber '1910' -AccountName 'Kassa'
        Add-LedgerAccount -JournalPath $jp -AccountNumber '3010' -AccountName 'Försäljning'
        Add-LedgerAccount -JournalPath $jp -AccountNumber '5010' -AccountName 'Lokalkostnader'

        Add-LedgerDimension -JournalPath $jp -DimensionNumber 1 -Name 'Kostnadsställe'
        Add-LedgerDimension -JournalPath $jp -DimensionNumber 2 -Name 'Projekt'
        Add-LedgerObject -JournalPath $jp -DimensionNumber 1 -ObjectNumber 'sthlm' -Name 'Stockholm'
        Add-LedgerObject -JournalPath $jp -DimensionNumber 1 -ObjectNumber 'gbg' -Name 'Göteborg'
        Add-LedgerObject -JournalPath $jp -DimensionNumber 2 -ObjectNumber 'proj-a' -Name 'Projekt Alpha'

        $fy = '2024-01_2024-12'
        Add-LedgerEntry -JournalPath $jp -FiscalYear $fy -Date '2024-03-15' `
            -Description 'Försäljning Stockholm' -Rows @(
            @{ Account = '1910'; Amount = 1000; Objects = @{ 1 = 'sthlm' } }
            @{ Account = '3010'; Amount = -1000; Objects = @{ 1 = 'sthlm'; 2 = 'proj-a' } }
        )
        Add-LedgerEntry -JournalPath $jp -FiscalYear $fy -Date '2024-04-01' `
            -Description 'Hyra Göteborg' -Rows @(
            @{ Account = '5010'; Amount = 8000; Objects = @{ 1 = 'gbg' } }
            @{ Account = '1910'; Amount = -8000 }
        )

        $script:siePath = Join-Path $TestDrive 'dim_export.se'
        Export-LedgerSie -JournalPath $jp -FiscalYear '2024-01_2024-12' -Path $script:siePath
    }

    Context 'Export includes dimensions and objects' {
        BeforeAll {
            $content = [System.IO.File]::ReadAllText($script:siePath, [System.Text.Encoding]::GetEncoding(437))
        }

        It 'Should contain #DIM records' {
            # Single-word values are unquoted in SIE; Kostnadsställe is one word
            $content | Should -Match '#DIM 1 Kostnadsst'
            $content | Should -Match '#DIM 2 Projekt'
        }

        It 'Should contain #OBJEKT records' {
            $content | Should -Match '#OBJEKT 1 sthlm Stockholm'
            $content | Should -Match '#OBJEKT 1 gbg'
            $content | Should -Match '#OBJEKT 2 proj-a "Projekt Alpha"'
        }

        It 'Should contain object tags on #TRANS rows' {
            $content | Should -Match '#TRANS 1910 \{1 "sthlm"\} 1000'
            $content | Should -Match '#TRANS 3010 \{1 "sthlm" 2 "proj-a"\} -1000'
        }

        It 'Should have empty object list for rows without objects' {
            $content | Should -Match '#TRANS 1910 \{\} -8000'
        }
    }

    Context 'Validate exported file' {
        BeforeAll {
            $result = Test-LedgerSie -Path $script:siePath
        }

        It 'Should be valid' {
            $result.IsValid | Should -BeTrue
        }

        It 'Should have no errors' {
            $result.Errors | Should -HaveCount 0
        }
    }

    Context 'Import round-trip preserves dimensions' {
        BeforeAll {
            # Create a fresh journal to import into
            $importJp = Join-Path $TestDrive 'dimimport.ledger'
            New-LedgerJournal -Path $importJp -Name 'Import Test'
            New-LedgerFiscalYear -JournalPath $importJp -StartDate '2024-01-01' -EndDate '2024-12-31'

            Import-LedgerSie -Path $script:siePath -JournalPath $importJp -FiscalYear '2024-01_2024-12' -CreateMissingAccounts
        }

        It 'Should import dimensions' {
            $dims = @(Get-LedgerDimension -JournalPath $importJp)
            $dims.Count | Should -Be 2
            ($dims | Where-Object { $_.DimensionNumber -eq 1 }).Name | Should -Be 'Kostnadsställe'
            ($dims | Where-Object { $_.DimensionNumber -eq 2 }).Name | Should -Be 'Projekt'
        }

        It 'Should import objects' {
            $objs = @(Get-LedgerObject -JournalPath $importJp)
            $objs.Count | Should -Be 3
            ($objs | Where-Object { $_.ObjectNumber -eq 'sthlm' }).Name | Should -Be 'Stockholm'
        }

        It 'Should preserve object tags on entries' {
            $entries = @(Get-LedgerEntry -JournalPath $importJp -FiscalYear '2024-01_2024-12')
            $entry1 = $entries | Where-Object { $_.Description -eq 'Försäljning Stockholm' }
            $entry1 | Should -Not -BeNullOrEmpty
            $entry1.Rows[0].Objects[1] | Should -Be 'sthlm'
            $entry1.Rows[1].Objects[2] | Should -Be 'proj-a'
        }

        It 'Should leave rows without objects as null' {
            $entries = @(Get-LedgerEntry -JournalPath $importJp -FiscalYear '2024-01_2024-12')
            $entry2 = $entries | Where-Object { $_.Description -eq 'Hyra Göteborg' }
            $entry2.Rows[1].Objects | Should -BeNullOrEmpty
        }

        It 'Should produce identical re-export' {
            $reExportPath = Join-Path $TestDrive 'dim_reexport.se'
            Export-LedgerSie -JournalPath $importJp -FiscalYear '2024-01_2024-12' -Path $reExportPath
            $original = [System.IO.File]::ReadAllText($script:siePath, [System.Text.Encoding]::GetEncoding(437))
            $reExport = [System.IO.File]::ReadAllText($reExportPath, [System.Text.Encoding]::GetEncoding(437))

            # Compare VER blocks (skip header which may differ in FNAMN/ORGNR)
            $origVers = ($original -split "`r?`n" | Select-String -Pattern '^\s*#(VER|TRANS)|^\{|^\}' | ForEach-Object { $_.Line.Trim() })
            $reVers = ($reExport -split "`r?`n" | Select-String -Pattern '^\s*#(VER|TRANS)|^\{|^\}' | ForEach-Object { $_.Line.Trim() })
            ($origVers -join "`n") | Should -Be ($reVers -join "`n")
        }
    }
}
