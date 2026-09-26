BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
    Import-Module TDDUtils -Force
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

        It 'Should present equity and liabilities in the balansräkning as positive amounts' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $bal = $content.Substring($content.IndexOf('Balansräkning'))
            $bal = $bal.Substring(0, $bal.IndexOf('Noter'))
            $bal | Should -Match 'Balanserat resultat\s+\d\s+170.000\s+0'
            $bal | Should -Match 'Årets resultat\s+\d\s+210.000\s+170.000'
            $bal | Should -Match 'Summa eget kapital och skulder\s+480.000\s+270.000'
            $bal | Should -Not -Match '(?<!\d)[−-]\d'
            $bal | Should -Not -Match '(?m)^Resultat\s'
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

        It 'Should use the K2 line items, subtotals and equity split in the statements' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $inc = $content.Substring($content.IndexOf('Resultaträkning'))
            $inc = $inc.Substring(0, $inc.IndexOf('Balansräkning'))
            $inc | Should -Match '2024-09-01 – 2025-08-31\s+2023-09-01 – 2024-08-31'
            $inc | Should -Match 'Övriga externa kostnader\s+−40.000\s+−30.000'
            $inc | Should -Match '(?m)^Rörelseresultat\s+210.000\s+170.000'

            $bal = $content.Substring($content.IndexOf('Balansräkning'))
            $bal = $bal.Substring(0, $bal.IndexOf('Noter'))
            $bal | Should -Match 'Not\s+2025-08-31\s+2024-08-31'
            $bal | Should -Match 'Finansiella anläggningstillgångar'
            $bal | Should -Match 'Andra långfristiga värdepappersinnehav\s+1, 2\s+80.000\s+80.000'
            $bal | Should -Match 'Summa anläggningstillgångar\s+80.000\s+80.000'
            $bal | Should -Match 'Kassa och bank\s+400.000\s+190.000'
            $bal | Should -Match 'Summa omsättningstillgångar\s+400.000\s+190.000'
            $bal | Should -Match 'Bundet eget kapital'
            $bal | Should -Match 'Fritt eget kapital'
            $bal | Should -Not -Match 'Summa kortfristiga skulder'
        }

        It 'Should show soliditet in the flerårsöversikt and the closing sentence of the förvaltningsberättelse' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $content | Should -Match 'Soliditet \(%\)\s+100,0\s+100,0'
            $content | Should -Match 'Bolagets resultat och ställning i övrigt framgår av efterföljande resultat- och balansräkning'
        }

        It 'Should show comparison figures in the fixed-asset note' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $content | Should -Match 'Ingående anskaffningsvärde\s+80.000\s+0'
            $content | Should -Match 'Årets inköp\s+0\s+80.000'
        }

        It 'Should include the comparative figures note when recorded' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy2 -ComparativeFiguresNote 'Jämförelsetalen har rättats.'
            try {
                $out = Join-Path $TestDrive 'comparatives.txt'
                Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out
                (Get-Content $out -Raw) | Should -Match 'Jämförelsetal\s+Jämförelsetalen har rättats\.'
            }
            finally {
                Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy2 -ComparativeFiguresNote ''
            }
        }

        It 'Should split the financial items into the statutory lines' {
            $fp = Join-Path $TestDrive 'fin.ledger'
            New-LedgerJournal -Path $fp -Name 'Finans AB' -OrgNumber '556000-0001' -CompanyType 'AB'
            foreach ($a in @(@('1930', 'Företagskonto'), @('2081', 'Aktiekapital'), @('8210', 'Utdelning'), @('8271', 'Nedskrivning'), @('8311', 'Ränteintäkter'), @('8410', 'Räntekostnader'))) {
                Add-LedgerAccount -JournalPath $fp -AccountNumber $a[0] -AccountName $a[1]
            }
            New-LedgerFiscalYear -JournalPath $fp -StartDate '2025-01-01' -EndDate '2025-12-31'
            $ffy = '2025-01_2025-12'
            Add-LedgerEntry -JournalPath $fp -FiscalYear $ffy -Date '2025-01-01' -Description 'Aktiekapital' -Rows @(
                @{ Account = '1930'; Amount = 50000 }, @{ Account = '2081'; Amount = -50000 })
            Add-LedgerEntry -JournalPath $fp -FiscalYear $ffy -Date '2025-06-01' -Description 'Finansiellt' -Rows @(
                @{ Account = '1930'; Amount = 2000 }, @{ Account = '8210'; Amount = -5000 }, @{ Account = '8271'; Amount = 3500 },
                @{ Account = '8311'; Amount = -700 }, @{ Account = '8410'; Amount = 200 })
            $out = Join-Path $TestDrive 'fin.txt'
            Export-LedgerAnnualReport -JournalPath $fp -FiscalYear $ffy -Path $out
            $content = Get-Content $out -Raw
            $content | Should -Match 'Resultat från övriga finansiella anläggningstillgångar\s+1.500'
            $content | Should -Match 'Övriga ränteintäkter och liknande resultatposter\s+700'
            $content | Should -Match 'Räntekostnader och liknande resultatposter\s+−200'
            $content | Should -Match 'Resultat efter finansiella poster\s+2.000'
            $content | Should -Not -Match 'Resultat före skatt'
        }

        It 'Should place the fastställelseintyg on the cover, before the förvaltningsberättelse' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $content.IndexOf('Fastställelseintyg') | Should -BeLessThan $content.IndexOf('Förvaltningsberättelse')
            # Defaults: place from RegisteredOffice, signer is the first board member, no meeting date yet.
            $content | Should -Match 'Gävle den ____________'
            $content | Should -Match 'årsstämma den ____________\.'
            $cert = $content.Substring(0, $content.IndexOf('Förvaltningsberättelse'))
            $cert | Should -Match 'Anna Andersson'
            $cert | Should -Not -Match 'Bertil Bengtsson'
        }

        It 'Should use the meeting date, place and signer from the report input in the fastställelseintyg' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy2 -AnnualMeetingDate '2025-12-01' -CertificatePlace 'Sandviken' -CertificateSigner 'Bertil Bengtsson'
            try {
                $out = Join-Path $TestDrive 'cert.txt'
                Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out
                $content = Get-Content $out -Raw
                $cert = $content.Substring(0, $content.IndexOf('Förvaltningsberättelse'))
                $cert | Should -Match 'årsstämma den 1 december 2025\.'
                $cert | Should -Match 'Sandviken den ____________'
                $cert | Should -Match 'Bertil Bengtsson'
            }
            finally {
                Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy2 -AnnualMeetingDate '' -CertificatePlace '' -CertificateSigner ''
            }
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

        It 'Should give the Word document styles, a page-numbered footer and page breaks' {
            $out = Join-Path $TestDrive 'layout.docx'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out -Format Word

            Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
            $zip = [System.IO.Compression.ZipFile]::OpenRead($out)
            try {
                $read = {
                    param($name)
                    $r = New-Object System.IO.StreamReader($zip.GetEntry($name).Open())
                    try { $r.ReadToEnd() } finally { $r.Dispose() }
                }
                $zip.Entries.FullName | Should -Contain 'word/styles.xml'
                $zip.Entries.FullName | Should -Contain 'word/footer1.xml'
                foreach ($part in 'word/document.xml', 'word/styles.xml', 'word/footer1.xml', 'word/_rels/document.xml.rels', '[Content_Types].xml') {
                    { [xml](& $read $part) } | Should -Not -Throw
                }
                $footer = & $read 'word/footer1.xml'
                $footer | Should -Match 'PAGE'
                $footer | Should -Match 'NUMPAGES'
                $doc = & $read 'word/document.xml'
                $doc | Should -Match '<w:br w:type="page"/>'
                $doc | Should -Match 'footerReference'
                $doc | Should -Match '<w:titlePg/>'
            }
            finally { $zip.Dispose() }
        }

        It 'Should render sum rows in bold in Markdown and include the board introduction in text' {
            $md = Join-Path $TestDrive 'layout.md'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $md -Format Markdown
            (Get-Content $md -Raw) | Should -Match '\*\*Summa tillgångar\*\*'

            $txt = Join-Path $TestDrive 'layout.txt'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $txt
            (Get-Content $txt -Raw) | Should -Match 'Styrelsen för .+ avger följande årsredovisning'
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
