BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Export-LedgerIncomeTaxReturn' {
    BeforeAll {
        $CommandName = 'Export-LedgerIncomeTaxReturn'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional JournalPath, an optional FiscalYear that binds from Name, and a mandatory Path parameter' {
            $journalPathParam = $Command.Parameters['JournalPath']
            $journalPathParam | Should -Not -BeNullOrEmpty
            $journalPathParam.Attributes.Mandatory | Should -Not -Contain $true

            $fiscalYearParam = $Command.Parameters['FiscalYear']
            $fiscalYearParam | Should -Not -BeNullOrEmpty
            $fiscalYearParam.Attributes.Mandatory | Should -Not -Contain $true
            $fiscalYearParam.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $fiscalYearParam.Aliases | Should -Contain 'Name'

            $pathParam = $Command.Parameters['Path']
            $pathParam | Should -Not -BeNullOrEmpty
            $pathParam.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have optional PostalCode, City, ContactPerson, Email, TaxAdjustment parameters and a Force switch' {
            foreach ($p in 'PostalCode', 'City', 'ContactPerson', 'Email', 'TaxAdjustment') {
                $Command.Parameters[$p] | Should -Not -BeNullOrEmpty
                $Command.Parameters[$p].Attributes.Mandatory | Should -Not -Contain $true
            }
            $Command.Parameters['TaxAdjustment'].ParameterType | Should -Be ([hashtable])
            $Command.Parameters['Force'].SwitchParameter | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testbolaget AB' -OrgNumber '556677-8899' `
                -Metadata @{ PostalCode = '11122'; City = 'Stockholm' } | Out-Null
            foreach ($a in @(
                    @('1930', 'Företagskonto'), @('1510', 'Kundfordringar'), @('2081', 'Aktiekapital'),
                    @('2440', 'Leverantörsskulder'), @('2610', 'Utgående moms'), @('2640', 'Ingående moms'),
                    @('3010', 'Försäljning'), @('5010', 'Lokalhyra'), @('8910', 'Skatt'))) {
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $a[0] -AccountName $a[1]
            }
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31' | Out-Null
            $FiscalYear = '2024-01_2024-12'

            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-02' `
                -Description 'Aktiekapital' -Rows @(
                    @{ Account = '1930'; Amount = 25000 }, @{ Account = '2081'; Amount = -25000 })
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' `
                -Description 'Försäljning' -Rows @(
                    @{ Account = '1510'; Amount = 125000 }, @{ Account = '3010'; Amount = -100000 },
                    @{ Account = '2610'; Amount = -25000 })
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-02-01' `
                -Description 'Hyra' -Rows @(
                    @{ Account = '5010'; Amount = 20000 }, @{ Account = '2640'; Amount = 5000 },
                    @{ Account = '2440'; Amount = -25000 })
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-01' `
                -Description 'Skatt' -Rows @(
                    @{ Account = '8910'; Amount = 15000 }, @{ Account = '2440'; Amount = -15000 })

            $Dest = Join-Path $TestDrive "$JournalName-sru"

            function Get-Uppgift {
                param($Content, $Blankett, $Code)
                $inBlock = $false
                foreach ($line in $Content) {
                    if ($line -eq "#BLANKETT $Blankett") { $inBlock = $true; continue }
                    if ($line -eq '#BLANKETTSLUT') { $inBlock = $false; continue }
                    if ($inBlock -and $line -match "^#UPPGIFT $Code (-?\d+)$") { return [long]$Matches[1] }
                }
                return $null
            }
        }

        It 'Should write both INFO.SRU and BLANKETTER.SRU into the destination directory' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            Test-Path -LiteralPath (Join-Path $Dest 'INFO.SRU') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU') | Should -BeTrue
        }

        It 'Should write the 12-digit organisation number and correct period' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest
            $r.OrgNumber | Should -Be '165566778899'
            $r.Period | Should -Be '2024P4'
            $info = Get-Content -LiteralPath (Join-Path $Dest 'INFO.SRU')
            $info | Should -Contain '#ORGNR 165566778899'
            $info | Should -Contain '#POSTNR 11122'
            $info | Should -Contain '#POSTORT Stockholm'
        }

        It 'Should include three blankett blocks and a terminating #FIL_SLUT' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            $blk | Should -Contain '#BLANKETT INK2-2024P4'
            $blk | Should -Contain '#BLANKETT INK2R-2024P4'
            $blk | Should -Contain '#BLANKETT INK2S-2024P4'
            $blk[-1] | Should -Be '#FIL_SLUT'
        }

        It 'Should map the income statement with SRU signs (revenue positive, costs negative)' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2R-2024P4' 7410 | Should -Be 100000    # Nettoomsättning
            Get-Uppgift $blk 'INK2R-2024P4' 7513 | Should -Be -20000    # Övriga externa kostnader
            Get-Uppgift $blk 'INK2R-2024P4' 7528 | Should -Be -15000    # Skatt
        }

        It 'Should map the balance sheet as positive amounts and balance assets against equity and liabilities' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            $assets = (Get-Uppgift $blk 'INK2R-2024P4' 7251) + (Get-Uppgift $blk 'INK2R-2024P4' 7281)
            $equityLiab = (Get-Uppgift $blk 'INK2R-2024P4' 7301) + (Get-Uppgift $blk 'INK2R-2024P4' 7302) +
                (Get-Uppgift $blk 'INK2R-2024P4' 7365) + (Get-Uppgift $blk 'INK2R-2024P4' 7369)
            $assets | Should -Be 150000
            $equityLiab | Should -Be 150000
        }

        It 'Should fold årets resultat into fritt eget kapital (7302)' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2R-2024P4' 7302 | Should -Be 65000
        }

        It 'Should report årets resultat as the INK2R income statement closing line (7450)' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2R-2024P4' 7450 | Should -Be 65000
        }

        It 'Should report årets resultat and non-deductible tax on INK2S and compute the surplus' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest
            $r.NetResult | Should -Be 65000
            $r.SurplusDeficit | Should -Be 80000
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2S-2024P4' 7650 | Should -Be 65000    # årets resultat, vinst
            Get-Uppgift $blk 'INK2S-2024P4' 7651 | Should -Be 15000    # skatt (ej avdragsgill)
            Get-Uppgift $blk 'INK2S-2024P4' 8020 | Should -Be 80000    # överskott
        }

        It 'Should carry the surplus to INK2 field 7113 (överskott av näringsverksamhet)' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2-2024P4' 7113 | Should -Be 80000
        }

        It 'Should add supplied tax adjustments to INK2S and into the surplus' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                -TaxAdjustment @{ '7654' = 940 }
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2S-2024P4' 7654 | Should -Be 940
            Get-Uppgift $blk 'INK2S-2024P4' 8020 | Should -Be 80940
            $r.SurplusDeficit | Should -Be 80940
        }

        It 'Should subtract supplied 77xx deduction fields from the surplus' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                -TaxAdjustment @{ '7654' = 940; '7754' = 395 }
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2S-2024P4' 7754 | Should -Be 395
            Get-Uppgift $blk 'INK2S-2024P4' 8020 | Should -Be 80545
            Get-Uppgift $blk 'INK2-2024P4' 7113 | Should -Be 80545
            $r.SurplusDeficit | Should -Be 80545
        }

        It 'Should let an explicit 8020 override the computed surplus' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                -TaxAdjustment @{ '8020' = 12345 }
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2S-2024P4' 8020 | Should -Be 12345
            Get-Uppgift $blk 'INK2-2024P4' 7113 | Should -Be 12345
            Get-Uppgift $blk 'INK2-2024P4' 7114 | Should -BeNullOrEmpty
            $r.SurplusDeficit | Should -Be 12345
        }

        It 'Should let an explicit 8021 override the computed surplus with a deficit' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                -TaxAdjustment @{ '8021' = 500 }
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2S-2024P4' 8021 | Should -Be 500
            Get-Uppgift $blk 'INK2S-2024P4' 8020 | Should -BeNullOrEmpty
            Get-Uppgift $blk 'INK2-2024P4' 7114 | Should -Be 500
            $r.SurplusDeficit | Should -Be -500
        }

        It 'Should write the files with ISO-8859-1 encoding preserving Swedish characters' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $Dest 'INFO.SRU'))
            $decoded = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)
            $decoded | Should -Match 'Testbolaget AB'
            # 'ö' in Stockholm-area names must be a single ISO-8859-1 byte 0xF6, never a UTF-8 pair.
            ($bytes -contains 0xC3) | Should -BeFalse
        }

        It 'Should refuse to overwrite existing files without -Force' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            { Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest } |
                Should -Throw '*already exists*'
        }

        It 'Should overwrite existing files with -Force' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            { Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest -Force } |
                Should -Not -Throw
        }

        It 'Should throw when the submitter postal code and city are unavailable' {
            $NoAddr = Join-Path $TestDrive 'NoAddr.ledger'
            New-LedgerJournal -Path $NoAddr -Name 'Utan Adress AB' -OrgNumber '556000-0100' | Out-Null
            New-LedgerFiscalYear -JournalPath $NoAddr -StartDate '2024-01-01' -EndDate '2024-12-31' | Out-Null
            { Export-LedgerIncomeTaxReturn -JournalPath $NoAddr -FiscalYear '2024-01_2024-12' `
                -Path (Join-Path $TestDrive 'noaddr-sru') } | Should -Throw '*postal code*'
        }

        It 'Should throw when the journal has no OrgNumber' {
            $NoOrg = Join-Path $TestDrive 'NoOrg.ledger'
            New-LedgerJournal -Path $NoOrg -Name 'Utan Orgnr AB' | Out-Null
            New-LedgerFiscalYear -JournalPath $NoOrg -StartDate '2024-01-01' -EndDate '2024-12-31' | Out-Null
            { Export-LedgerIncomeTaxReturn -JournalPath $NoOrg -FiscalYear '2024-01_2024-12' `
                -Path (Join-Path $TestDrive 'noorg-sru') -PostalCode '11122' -City 'Stockholm' } |
                Should -Throw '*OrgNumber*'
        }

        It 'Should not double count årets resultat in fritt eget kapital when 8999/2099 is booked' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2099' -AccountName 'Årets resultat'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '8999' -AccountName 'Årets resultat'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-12-31' `
                -Description 'Årets resultat' -Rows @(
                    @{ Account = '8999'; Amount = 65000 }, @{ Account = '2099'; Amount = -65000 })
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2R-2024P4' 7302 | Should -Be 65000
            Get-Uppgift $blk 'INK2R-2024P4' 7450 | Should -Be 65000
            $r.NetResult | Should -Be 65000
            $r.SurplusDeficit | Should -Be 80000
        }

        It 'Should report a debit balance on 25xx skatteskulder as a receivable (7261)' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2510' -AccountName 'Skatteskulder'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-06-12' `
                -Description 'Preliminärskatt' -Rows @(
                    @{ Account = '2510'; Amount = 4000 }, @{ Account = '1930'; Amount = -4000 })
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2R-2024P4' 7261 | Should -Be 4000
            Get-Uppgift $blk 'INK2R-2024P4' 7368 | Should -BeNullOrEmpty
        }

        It 'Should report a credit balance on the skattekonto (163x) as a skatteskuld (7368)' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1630' -AccountName 'Skattekonto'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-06-12' `
                -Description 'Debiterad skatt' -Rows @(
                    @{ Account = '1630'; Amount = -3000 }, @{ Account = '2440'; Amount = 3000 })
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2R-2024P4' 7368 | Should -Be 3000
            Get-Uppgift $blk 'INK2R-2024P4' 7261 | Should -BeNullOrEmpty
        }

        It 'Should derive årets resultat and fritt eget kapital from the truncated lines so the form ties out' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '6570' -AccountName 'Bankkostnader'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '8310' -AccountName 'Ränteintäkter'
            # Öre on 6570 (cost 0,70) and 8310 (income 0,60) truncate to 0 per line,
            # while the raw result drops by 0,10 kr.
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-07-01' `
                -Description 'Öresposter' -Rows @(
                    @{ Account = '6570'; Amount = 0.70 }, @{ Account = '8310'; Amount = -0.60 },
                    @{ Account = '1930'; Amount = -0.10 })
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            $lines = 0
            foreach ($c in 7410, 7513, 7528, 7417) { $lines += [long](Get-Uppgift $blk 'INK2R-2024P4' $c) }
            Get-Uppgift $blk 'INK2R-2024P4' 7450 | Should -Be $lines
            Get-Uppgift $blk 'INK2S-2024P4' 7650 | Should -Be $lines
            $assets = (Get-Uppgift $blk 'INK2R-2024P4' 7251) + (Get-Uppgift $blk 'INK2R-2024P4' 7281)
            $equityLiab = (Get-Uppgift $blk 'INK2R-2024P4' 7301) + (Get-Uppgift $blk 'INK2R-2024P4' 7302) +
                (Get-Uppgift $blk 'INK2R-2024P4' 7365) + (Get-Uppgift $blk 'INK2R-2024P4' 7369)
            $equityLiab | Should -Be $assets
            $r.SurplusDeficit | Should -Be ($lines + 15000)
        }
    }
}
