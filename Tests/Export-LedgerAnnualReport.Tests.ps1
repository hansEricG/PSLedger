BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
    Import-Module TDDUtils -Force
    Import-Module TDDSeams -Force
}

Describe 'Export-LedgerAnnualReport' {
    Context 'Function metadata' {
        BeforeAll {
            $Command = Get-Command Export-LedgerAnnualReport
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory Path parameter' {
            $param = $Command.Parameters['Path']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should have a Format parameter validating Text, Markdown and Word' {
            $param = $Command.Parameters['Format']
            $validate = $param.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] })
            $validate.ValidValues | Should -Contain 'Text'
            $validate.ValidValues | Should -Contain 'Markdown'
            $validate.ValidValues | Should -Contain 'Word'
        }

        It 'Should have a Force switch parameter' {
            $param = $Command.Parameters['Force']
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'export.ledger'
            New-LedgerJournal -Path $jp -Name 'Export AB' -OrgNumber '556677-8899' -CompanyType 'AB'
            Set-LedgerJournal -JournalPath $jp -Metadata @{
                RegisteredOffice = 'Gävle'
                BusinessObject   = 'Konsultverksamhet inom IT.'
                NumberOfShares   = '1000'
                ShareCapital     = '100000'
                BoardMembers     = 'Anna Andersson;Bertil Bengtsson'
            }

            foreach ($a in @(
                    @('1930', 'Företagskonto'),
                    @('1350', 'Andra långfristiga värdepappersinnehav'),
                    @('2081', 'Aktiekapital'),
                    @('2091', 'Balanserad vinst'),
                    @('2099', 'Årets resultat'),
                    @('3011', 'Försäljning'),
                    @('6110', 'Kontorsmateriel'),
                    @('8999', 'Årets resultat'))) {
                Add-LedgerAccount -JournalPath $jp -AccountNumber $a[0] -AccountName $a[1]
            }

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2023-09-01' -EndDate '2024-08-31'
            $fy1 = '2023-09_2024-08'
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy1 -Date '2023-09-01' -Description 'Aktiekapital' -Rows @(
                @{ Account = '1930'; Amount = 100000 }, @{ Account = '2081'; Amount = -100000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy1 -Date '2023-10-01' -Description 'Köp värdepapper' -Rows @(
                @{ Account = '1350'; Amount = 80000 }, @{ Account = '1930'; Amount = -80000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy1 -Date '2024-01-15' -Description 'Försäljning' -Rows @(
                @{ Account = '1930'; Amount = 200000 }, @{ Account = '3011'; Amount = -200000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy1 -Date '2024-03-01' -Description 'Kontorsmateriel' -Rows @(
                @{ Account = '6110'; Amount = 30000 }, @{ Account = '1930'; Amount = -30000 })
            Close-LedgerFiscalYear -JournalPath $jp -FiscalYear $fy1

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-09-01' -EndDate '2025-08-31'
            $fy2 = '2024-09_2025-08'
            Copy-LedgerOpeningBalance -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear $fy2
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy2 -Date '2025-01-15' -Description 'Försäljning' -Rows @(
                @{ Account = '1930'; Amount = 250000 }, @{ Account = '3011'; Amount = -250000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy2 -Date '2025-03-01' -Description 'Kontorsmateriel' -Rows @(
                @{ Account = '6110'; Amount = 40000 }, @{ Account = '1930'; Amount = -40000 })

            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy2 `
                -SignificantEvents 'Inga väsentliga händelser har inträffat under året.' `
                -ProposedDividend 50000 -AverageEmployees 1 -SecuritiesMarketValue 95000 `
                -SigningPlace 'Gävle' -SigningDate '2025-11-15'
        }

        It 'Should create a text report file' {
            $out = Join-Path $TestDrive 'report.txt'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out
            Test-Path $out | Should -BeTrue
        }

        It 'Should include the heading with company name and org number' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $content | Should -Match 'Export AB'
            $content | Should -Match '556677-8899'
            $content | Should -Match '2024-09-01 - 2025-08-31'
        }

        It 'Should include the förvaltningsberättelse sections' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $content | Should -Match 'Förvaltningsberättelse'
            $content | Should -Match 'Väsentliga händelser'
            $content | Should -Match 'Flerårsöversikt'
            $content | Should -Match 'Förslag till vinstdisposition'
        }

        It 'Should include both statement sections with a comparison column' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $content | Should -Match 'Resultaträkning'
            $content | Should -Match 'Balansräkning'
            $content | Should -Match 'Nettoomsättning'
            $content | Should -Match '2024/2025'
            $content | Should -Match '2023/2024'
        }

        It 'Should include the notes section with numbered notes' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $content | Should -Match 'Redovisnings- och värderingsprinciper'
            $content | Should -Match 'Not 1'
            $content | Should -Match 'Marknadsvärde'
            $content | Should -Match 'Förändring av eget kapital'
        }

        It 'Should include the signatures and fastställelseintyg' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $content | Should -Match 'Underskrifter'
            $content | Should -Match 'Anna Andersson'
            $content | Should -Match 'Bertil Bengtsson'
            $content | Should -Match 'Fastställelseintyg'
        }

        It 'Should write a Markdown report with headings and tables' {
            $out = Join-Path $TestDrive 'report.md'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out -Format Markdown
            $content = Get-Content $out -Raw
            $content | Should -Match '# Årsredovisning'
            $content | Should -Match '## Resultaträkning'
            $content | Should -Match '\| Nettoomsättning \|'
        }

        It 'Should write a Word (.docx) document that is a valid package' {
            $out = Join-Path $TestDrive 'report.docx'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out -Format Word
            Test-Path $out | Should -BeTrue

            Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
            $zip = [System.IO.Compression.ZipFile]::OpenRead($out)
            try {
                $entries = $zip.Entries.FullName
                $entries | Should -Contain 'word/document.xml'
                $entries | Should -Contain '[Content_Types].xml'
                $entries | Should -Contain '_rels/.rels'

                $docEntry = $zip.GetEntry('word/document.xml')
                $reader = New-Object System.IO.StreamReader($docEntry.Open())
                try { $xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
                $xml | Should -Match 'Resultaträkning'
                $xml | Should -Match 'Balansräkning'
                $xml | Should -Match '<w:tbl>'
            }
            finally { $zip.Dispose() }
        }

        It 'Should omit the comparison column from the statements with -NoComparison' {
            $out = Join-Path $TestDrive 'nocomp.txt'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out -NoComparison
            $content = Get-Content $out -Raw
            $content | Should -Match '2024/2025'
            # The resultaträkning/balansräkning header must not carry a second year column.
            $content | Should -Not -Match 'Not\s+2024/2025\s+2023/2024'
        }

        It 'Should throw if the destination exists without -Force' {
            $out = Join-Path $TestDrive 'existing.txt'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out
            { Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out } |
                Should -Throw '*already exists*'
        }

        It 'Should overwrite an existing file with -Force' {
            $out = Join-Path $TestDrive 'force.txt'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out
            { Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out -Force } |
                Should -Not -Throw
        }
    }
}
