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
            $bal | Should -Match 'Balanserat resultat\s+170.000\s+0'
            $bal | Should -Match 'Årets resultat\s+210.000\s+170.000'
            $bal | Should -Match 'Summa eget kapital och skulder\s+480.000\s+270.000'
            $bal | Should -Not -Match '(?<!\d)[−-]\d'
            $bal | Should -Not -Match '(?m)^Resultat\s'
        }

        It 'Should include the notes section with numbered notes' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $content | Should -Match 'Redovisnings- och värderingsprinciper'
            $content | Should -Match 'Not 1'
            $content | Should -Match 'Marknadsvärde'
        }

        It 'Should show the changes in equity in the förvaltningsberättelse, not as a note' {
            $content = Get-Content (Join-Path $TestDrive 'report.txt') -Raw
            $fb = $content.Substring(0, $content.IndexOf('Resultaträkning'))
            $fb | Should -Match 'Förändringar i eget kapital'
            $content | Should -Not -Match 'Not \d+\s+Förändring'
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

        It 'Should use the K3 financial lines with impairments on a line of their own' {
            $fp = Join-Path $TestDrive 'fink3.ledger'
            New-LedgerJournal -Path $fp -Name 'Finans K3 AB' -OrgNumber '556000-0002' -CompanyType 'AB'
            foreach ($a in @(@('1930', 'Företagskonto'), @('2081', 'Aktiekapital'), @('8210', 'Utdelning'), @('8271', 'Nedskrivning'), @('8311', 'Ränteintäkter'), @('8410', 'Räntekostnader'))) {
                Add-LedgerAccount -JournalPath $fp -AccountNumber $a[0] -AccountName $a[1]
            }
            New-LedgerFiscalYear -JournalPath $fp -StartDate '2025-01-01' -EndDate '2025-12-31'
            $ffy = '2025-01_2025-12'
            Add-LedgerEntry -JournalPath $fp -FiscalYear $ffy -Date '2025-06-01' -Description 'Finansiellt' -Rows @(
                @{ Account = '1930'; Amount = 2000 }, @{ Account = '8210'; Amount = -5000 }, @{ Account = '8271'; Amount = 3500 },
                @{ Account = '8311'; Amount = -700 }, @{ Account = '8410'; Amount = 200 })
            Set-LedgerReportInput -JournalPath $fp -FiscalYear $ffy -Framework K3
            $out = Join-Path $TestDrive 'fink3.txt'
            Export-LedgerAnnualReport -JournalPath $fp -FiscalYear $ffy -Path $out
            $content = Get-Content $out -Raw
            $content | Should -Match 'Intäkter från övriga värdepapper och fordringar som är anläggningstillgångar\s+5.000'
            $content | Should -Match 'Nedskrivningar av finansiella anläggningstillgångar och kortfristiga placeringar\s+−3.500'
            $content | Should -Match 'Övriga ränteintäkter och liknande intäkter\s+700'
            $content | Should -Match 'Räntekostnader och liknande kostnader\s+−200'
            $content | Should -Match 'Resultat efter finansiella poster\s+2.000'
            # No earlier year, so no transition note.
            $content | Should -Not -Match 'Övergång till K3'
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

        It 'Should keep the vinstdisposition together in the Word document' {
            $out = Join-Path $TestDrive 'keep.docx'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear $fy2 -Path $out -Format Word
            Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
            $zip = [System.IO.Compression.ZipFile]::OpenRead($out)
            try {
                $r = New-Object System.IO.StreamReader($zip.GetEntry('word/document.xml').Open())
                try { $doc = [xml]$r.ReadToEnd() } finally { $r.Dispose() }
            }
            finally { $zip.Dispose() }
            $ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
            $ns.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
            $paras = @($doc.SelectNodes('//w:body//w:p', $ns))
            $texts = $paras | ForEach-Object { $_.InnerText }
            $start = [array]::IndexOf($texts, 'Till årsstämmans förfogande står följande medel (kronor):')
            $end = (0..($texts.Count - 1) | Where-Object { $texts[$_] -like 'Föreslagen utdelning per aktie*' } | Select-Object -First 1)
            $start | Should -BeGreaterThan 0
            $end | Should -BeGreaterThan $start
            for ($i = $start; $i -lt $end; $i++) {
                $paras[$i].SelectSingleNode('w:pPr/w:keepNext', $ns) | Should -Not -BeNullOrEmpty -Because "paragraph $i ('$($texts[$i])') must keep with next"
            }
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

    Context 'K3' {
        BeforeAll {
            $kp = Join-Path $TestDrive 'k3.ledger'
            New-LedgerJournal -Path $kp -Name 'Krypto AB' -OrgNumber '556111-2222' -CompanyType 'AB'
            Set-LedgerJournal -JournalPath $kp -Metadata @{ RegisteredOffice = 'Gävle'; BoardMembers = 'Anna Andersson' }
            foreach ($a in @(
                    @('1090', 'Kryptotillgångar'),
                    @('1098', 'Ackumulerade nedskrivningar kryptotillgångar'),
                    @('1350', 'Andra långfristiga värdepappersinnehav'),
                    @('1930', 'Företagskonto'),
                    @('2081', 'Aktiekapital'),
                    @('2091', 'Balanserad vinst'),
                    @('2099', 'Årets resultat'),
                    @('2510', 'Skatteskulder'),
                    @('3011', 'Försäljning'),
                    @('7710', 'Nedskrivningar av immateriella anläggningstillgångar'),
                    @('8999', 'Årets resultat'))) {
                Add-LedgerAccount -JournalPath $kp -AccountNumber $a[0] -AccountName $a[1]
            }

            New-LedgerFiscalYear -JournalPath $kp -StartDate '2023-09-01' -EndDate '2024-08-31'
            $k1 = '2023-09_2024-08'
            Add-LedgerEntry -JournalPath $kp -FiscalYear $k1 -Date '2023-09-01' -Description 'Aktiekapital' -Rows @(
                @{ Account = '1930'; Amount = 100000 }, @{ Account = '2081'; Amount = -100000 })
            Add-LedgerEntry -JournalPath $kp -FiscalYear $k1 -Date '2023-10-01' -Description 'Köp bitcoin' -Rows @(
                @{ Account = '1350'; Amount = 50000 }, @{ Account = '1930'; Amount = -50000 })
            Close-LedgerFiscalYear -JournalPath $kp -FiscalYear $k1

            New-LedgerFiscalYear -JournalPath $kp -StartDate '2024-09-01' -EndDate '2025-08-31'
            $k2 = '2024-09_2025-08'
            Copy-LedgerOpeningBalance -JournalPath $kp -FromFiscalYear $k1 -ToFiscalYear $k2
            Add-LedgerEntry -JournalPath $kp -FiscalYear $k2 -Date '2024-09-01' -Description 'Omklassificering vid övergång till K3' -Rows @(
                @{ Account = '1090'; Amount = 50000 }, @{ Account = '1350'; Amount = -50000 })
            Add-LedgerEntry -JournalPath $kp -FiscalYear $k2 -Date '2025-01-15' -Description 'Försäljning' -Rows @(
                @{ Account = '1930'; Amount = 20000 }, @{ Account = '3011'; Amount = -20000 })
            Add-LedgerEntry -JournalPath $kp -FiscalYear $k2 -Date '2025-08-31' -Description 'Nedskrivning bitcoin' -Rows @(
                @{ Account = '7710'; Amount = 8000 }, @{ Account = '1098'; Amount = -8000 })
            Add-LedgerEntry -JournalPath $kp -FiscalYear $k2 -Date '2025-08-31' -Description 'Inbetald preliminärskatt' -Rows @(
                @{ Account = '2510'; Amount = 500 }, @{ Account = '1930'; Amount = -500 })
            Set-LedgerReportInput -JournalPath $kp -FiscalYear $k2 -Framework K3 `
                -TransitionNote 'Kryptotillgångar har omklassificerats från finansiella till immateriella anläggningstillgångar.' `
                -DeferredTaxStatement 'Uppskjuten skattefordran på underskottsavdrag redovisas inte.' `
                -Ownership 'Anna Andersson äger samtliga aktier.' -EventsAfterBalanceDate 'Inga väsentliga händelser.'

            $out = Join-Path $TestDrive 'k3.txt'
            Export-LedgerAnnualReport -JournalPath $kp -FiscalYear $k2 -Path $out
            $k3Content = Get-Content $out -Raw
        }

        It 'Should state K3 in the accounting principles with principles for crypto assets and income taxes' {
            $k3Content | Should -Match 'upprättats enligt årsredovisningslagen och Bokföringsnämndens allmänna råd BFNAR 2012:1 Årsredovisning och koncernredovisning \(K3\)'
            $k3Content | Should -Not -Match 'upprättats enligt årsredovisningslagen och Bokföringsnämndens allmänna råd BFNAR 2016:10'
            $k3Content | Should -Match 'Kryptotillgångar: Innehav som bolaget avser att behålla långsiktigt'
            $k3Content | Should -Match 'skrivs därför inte av'
            $k3Content | Should -Match 'Inkomstskatter: .+Uppskjuten skattefordran på underskottsavdrag redovisas inte\.'
        }

        It 'Should include a transition note in the first K3 year' {
            $k3Content | Should -Match 'Övergång till K3'
            $k3Content | Should -Match 'Tidpunkten för övergången är den 1 september 2024\.'
            $k3Content | Should -Match 'har inte räknats om enligt K3'
            $k3Content | Should -Match 'Kryptotillgångar har omklassificerats'
        }

        It 'Should not include a transition note once the previous year is K3' {
            New-LedgerFiscalYear -JournalPath $kp -StartDate '2025-09-01' -EndDate '2026-08-31'
            Set-LedgerReportInput -JournalPath $kp -FiscalYear '2025-09_2026-08' -Framework K3
            $out = Join-Path $TestDrive 'k3-second.txt'
            Export-LedgerAnnualReport -JournalPath $kp -FiscalYear '2025-09_2026-08' -Path $out
            (Get-Content $out -Raw) | Should -Not -Match 'Övergång till K3'
        }

        It 'Should present crypto assets and current tax receivables as K3 balance sheet posts' {
            $bal = $k3Content.Substring($k3Content.IndexOf('Balansräkning'))
            $bal = $bal.Substring(0, $bal.IndexOf('Noter'))
            $bal | Should -Match 'Immateriella anläggningstillgångar'
            $bal | Should -Match 'Kryptotillgångar\s+\d\s+42.000\s+0'
            $bal | Should -Match 'Andra långfristiga värdepappersinnehav\s+\d\s+0\s+50.000'
            $bal | Should -Match 'Aktuella skattefordringar\s+500'
        }

        It 'Should use the K3 depreciation line in the resultaträkning' {
            $k3Content | Should -Match 'Avskrivningar och nedskrivningar av materiella och immateriella anläggningstillgångar\s+−8.000'
        }

        It 'Should include a movement schedule for the crypto assets with impairments' {
            $k3Content | Should -Match 'Not \d\s+Kryptotillgångar'
            $k3Content | Should -Match 'Årets inköp\s+50.000'
            $k3Content | Should -Match 'Årets nedskrivningar\s+−8.000'
        }

        It 'Should state pledged assets, contingent liabilities, events after the balance date and ownership' {
            $k3Content | Should -Match 'Ställda säkerheter: Inga'
            $k3Content | Should -Match 'Eventualförpliktelser: Inga'
            $k3Content | Should -Match 'Väsentliga händelser efter räkenskapsårets slut\s+Inga väsentliga händelser\.'
            $fb = $k3Content.Substring(0, $k3Content.IndexOf('Resultaträkning'))
            $fb | Should -Match 'Ägarförhållanden\s+Anna Andersson äger samtliga aktier\.'
        }

        It 'Should keep the K2 layout for the K2 year' {
            $out = Join-Path $TestDrive 'k3-prev.txt'
            Export-LedgerAnnualReport -JournalPath $kp -FiscalYear $k1 -Path $out
            $content = Get-Content $out -Raw
            $content | Should -Match 'BFNAR 2016:10'
            $content | Should -Not -Match 'Ställda säkerheter'
            $content | Should -Not -Match 'Kryptotillgångar'
        }
    }

    Context 'Holdings' {
        BeforeAll {
            $hp = Join-Path $TestDrive 'holdings.ledger'
            New-LedgerJournal -Path $hp -Name 'Innehav AB' -OrgNumber '556222-3333' -CompanyType 'AB'
            Set-LedgerJournal -JournalPath $hp -Metadata @{ RegisteredOffice = 'Gävle'; BoardMembers = 'Anna Andersson' }
            foreach ($a in @(
                    @('1350', 'Andra långfristiga värdepappersinnehav'),
                    @('1930', 'Företagskonto'),
                    @('2081', 'Aktiekapital'),
                    @('2099', 'Årets resultat'),
                    @('8999', 'Årets resultat'))) {
                Add-LedgerAccount -JournalPath $hp -AccountNumber $a[0] -AccountName $a[1]
            }
            New-LedgerFiscalYear -JournalPath $hp -StartDate '2024-09-01' -EndDate '2025-08-31'
            $hy = '2024-09_2025-08'
            Add-LedgerEntry -JournalPath $hp -FiscalYear $hy -Date '2024-09-01' -Description 'Aktiekapital' -Rows @(
                @{ Account = '1930'; Amount = 100000 }, @{ Account = '2081'; Amount = -100000 })
            Add-LedgerEntry -JournalPath $hp -FiscalYear $hy -Date '2024-10-01' -Description 'Köp värdepapper' -Rows @(
                @{ Account = '1350'; Amount = 80000 }, @{ Account = '1930'; Amount = -80000 })
        }

        It 'Should include the shareholding note with the holdings total when only holdings are recorded' {
            Set-LedgerHolding -JournalPath $hp -FiscalYear $hy -Account 1350 -Name 'Investor B' -Quantity 400 -Price 250
            $out = Join-Path $TestDrive 'holdings.txt'
            Export-LedgerAnnualReport -JournalPath $hp -FiscalYear $hy -Path $out
            $content = Get-Content $out -Raw
            $content | Should -Match 'Aktier och andelar'
            $content | Should -Match 'Marknadsvärde\s+100.000'
        }

        It 'Should warn when the holdings are below book value' {
            Set-LedgerHolding -JournalPath $hp -FiscalYear $hy -Account 1350 -Name 'Investor B' -Price 150
            $out = Join-Path $TestDrive 'holdings-below.txt'
            Export-LedgerAnnualReport -JournalPath $hp -FiscalYear $hy -Path $out -WarningVariable w -WarningAction SilentlyContinue
            ($w -join ' ') | Should -Match 'below book value'
        }
    }
}
