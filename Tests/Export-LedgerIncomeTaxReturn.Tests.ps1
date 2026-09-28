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

        It 'Should have optional PostalCode, City, ContactPerson, Email, TaxAdjustment parameters and Force and NoAutomaticAdjustment switches' {
            foreach ($p in 'PostalCode', 'City', 'ContactPerson', 'Email', 'TaxAdjustment') {
                $Command.Parameters[$p] | Should -Not -BeNullOrEmpty
                $Command.Parameters[$p].Attributes.Mandatory | Should -Not -Contain $true
            }
            $Command.Parameters['TaxAdjustment'].ParameterType | Should -Be ([hashtable])
            $Command.Parameters['Force'].SwitchParameter | Should -BeTrue
            $Command.Parameters['NoAutomaticAdjustment'].SwitchParameter | Should -BeTrue
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

        It 'Should map the income statement as printed on the form (costs positive on minus rows)' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2R-2024P4' 7410 | Should -Be 100000    # Nettoomsättning
            Get-Uppgift $blk 'INK2R-2024P4' 7513 | Should -Be 20000    # Övriga externa kostnader
            Get-Uppgift $blk 'INK2R-2024P4' 7528 | Should -Be 15000    # Skatt
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
            Get-Uppgift $blk 'INK2S-2024P4' 7670 | Should -Be 80000    # överskott
        }

        It 'Should carry the surplus to INK2 1.1 (SRU 7104, överskott av näringsverksamhet)' {
            Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest | Out-Null
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2-2024P4' 7104 | Should -Be 80000
        }

        It 'Should add supplied tax adjustments to INK2S and into the surplus' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                -TaxAdjustment @{ '7654' = 940 }
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2S-2024P4' 7654 | Should -Be 940
            Get-Uppgift $blk 'INK2S-2024P4' 7670 | Should -Be 80940
            $r.SurplusDeficit | Should -Be 80940
        }

        It 'Should subtract supplied 77xx deduction fields from the surplus' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                -TaxAdjustment @{ '7654' = 940; '7754' = 395 }
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2S-2024P4' 7754 | Should -Be 395
            Get-Uppgift $blk 'INK2S-2024P4' 7670 | Should -Be 80545
            Get-Uppgift $blk 'INK2-2024P4' 7104 | Should -Be 80545
            $r.SurplusDeficit | Should -Be 80545
        }

        It 'Should let an explicit 4.15 override the computed surplus' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                -TaxAdjustment @{ '4.15' = 12345 }
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2S-2024P4' 7670 | Should -Be 12345
            Get-Uppgift $blk 'INK2-2024P4' 7104 | Should -Be 12345
            Get-Uppgift $blk 'INK2-2024P4' 7114 | Should -BeNullOrEmpty
            $r.SurplusDeficit | Should -Be 12345
        }

        It 'Should let an explicit 4.16 (SRU 7770) override the computed surplus with a deficit' {
            $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                -TaxAdjustment @{ '7770' = 500 }
            $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
            Get-Uppgift $blk 'INK2S-2024P4' 7770 | Should -Be 500
            Get-Uppgift $blk 'INK2S-2024P4' 7670 | Should -BeNullOrEmpty
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
            $lines = [long](Get-Uppgift $blk 'INK2R-2024P4' 7410) + [long](Get-Uppgift $blk 'INK2R-2024P4' 7417) -
                [long](Get-Uppgift $blk 'INK2R-2024P4' 7513) - [long](Get-Uppgift $blk 'INK2R-2024P4' 7528)
            Get-Uppgift $blk 'INK2R-2024P4' 7450 | Should -Be $lines
            Get-Uppgift $blk 'INK2S-2024P4' 7650 | Should -Be $lines
            $assets = (Get-Uppgift $blk 'INK2R-2024P4' 7251) + (Get-Uppgift $blk 'INK2R-2024P4' 7281)
            $equityLiab = (Get-Uppgift $blk 'INK2R-2024P4' 7301) + (Get-Uppgift $blk 'INK2R-2024P4' 7302) +
                (Get-Uppgift $blk 'INK2R-2024P4' 7365) + (Get-Uppgift $blk 'INK2R-2024P4' 7369)
            $equityLiab | Should -Be $assets
            $r.SurplusDeficit | Should -Be ($lines + 15000)
        }

        Context 'Form rows and official field codes' {
            It 'Should use period P3 for a fiscal year ending in August' {
                New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-09-01' -EndDate '2026-08-31' | Out-Null
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear '2025-09_2026-08' -Path $Dest
                $r.Period | Should -Be '2026P3'
            }

            It 'Should use period P2 for a fiscal year ending in June' {
                New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-07-01' -EndDate '2026-06-30' | Out-Null
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear '2025-07_2026-06' -Path $Dest
                $r.Period | Should -Be '2026P2'
            }

            It 'Should report dividends (8210) on 3.15 (+) and write-downs of shares (8271) on 3.17' {
                foreach ($a in @(@('8210', 'Utdelning på andelar i andra företag'), @('8271', 'Nedskrivning'), @('1359', 'Värdereglering'))) {
                    Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $a[0] -AccountName $a[1]
                }
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-05-01' `
                    -Description 'Utdelning och nedskrivning' -Rows @(
                        @{ Account = '1930'; Amount = 3000 }, @{ Account = '8210'; Amount = -3000 },
                        @{ Account = '8271'; Amount = 1000 }, @{ Account = '1359'; Amount = -1000 })
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                    -WarningAction SilentlyContinue
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2R-2024P4' 7416 | Should -Be 3000
                Get-Uppgift $blk 'INK2R-2024P4' 7521 | Should -Be 1000
                Get-Uppgift $blk 'INK2R-2024P4' 7423 | Should -BeNullOrEmpty
                $r.NetResult | Should -Be 67000
            }

            It 'Should report a net loss on a split row in its (-) field as a positive amount' {
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '8250' -AccountName 'Rearesultat andelar'
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-05-01' `
                    -Description 'Förlust avyttring' -Rows @(
                        @{ Account = '8250'; Amount = 2500 }, @{ Account = '1930'; Amount = -2500 })
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2R-2024P4' 7520 | Should -Be 2500
                Get-Uppgift $blk 'INK2R-2024P4' 7416 | Should -BeNullOrEmpty
                $r.NetResult | Should -Be 62500
            }

            It 'Should report a booked tax income as a negative amount on 3.25 and 4.3a' {
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-12-31' `
                    -Description 'Skatteintäkt' -Rows @(
                        @{ Account = '2440'; Amount = 20000 }, @{ Account = '8910'; Amount = -20000 })
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2R-2024P4' 7528 | Should -Be -5000
                Get-Uppgift $blk 'INK2S-2024P4' 7651 | Should -Be -5000
                $r.NetResult | Should -Be 85000
                $r.SurplusDeficit | Should -Be 80000
            }

            It 'Should accept a row on the form as -TaxAdjustment key' {
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                    -TaxAdjustment @{ '4.6a' = 940; '4.13-' = 100 }
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2S-2024P4' 7654 | Should -Be 940
                Get-Uppgift $blk 'INK2S-2024P4' 7762 | Should -Be 100
                $r.SurplusDeficit | Should -Be 80840
            }

            It 'Should require a (+)/(-) suffix for a split INK2S row' {
                { Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                        -TaxAdjustment @{ '4.13' = 100 } } | Should -Throw "*'4.13+' or '4.13-'*"
            }

            It 'Should reject unknown fields and årets resultat as -TaxAdjustment keys' {
                { Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                        -TaxAdjustment @{ '4.99' = 1 } } | Should -Throw '*Unknown INK2S field*'
                { Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                        -TaxAdjustment @{ '7650' = 1 } } | Should -Throw '*årets resultat*'
            }

            It 'Should throw on a negative amount in a field that only accepts positive amounts' {
                { Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                        -TaxAdjustment @{ '4.13+' = -100 } } | Should -Throw '*cannot be negative*'
            }

            It 'Should not count information-only fields (4.17-4.22) in the surplus' {
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                    -TaxAdjustment @{ '4.21' = 5000 }
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2S-2024P4' 8022 | Should -Be 5000
                $r.SurplusDeficit | Should -Be 80000
            }

            It 'Should list every written field with its row on the form in Fields' {
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest
                $f = $r.Fields | Where-Object { $_.Form -eq 'INK2R' -and $_.Box -eq '3.7' }
                $f.SruCode | Should -Be 7513
                $f.Amount | Should -Be 20000
                ($r.Fields | Where-Object { $_.Form -eq 'INK2' -and $_.Box -eq '1.1' }).Amount | Should -Be 80000
                ($r.Fields | Where-Object { $_.Form -eq 'INK2S' -and $_.Box -eq '4.15' }).Amount | Should -Be 80000
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                ($blk | Where-Object { $_ -match '^#UPPGIFT (?!701[12] )' }).Count | Should -Be $r.Fields.Count
            }
        }

        Context 'Automatic tax adjustments' {
            BeforeEach {
                foreach ($a in @(@('8314', 'Skattefria ränteintäkter'), @('8423', 'Räntekostnader för skatter och avgifter'),
                        @('6072', 'Representation, ej avdragsgill'), @('1350', 'Aktier'), @('1359', 'Värdereglering'),
                        @('8271', 'Nedskrivning av andelar i andra företag'),
                        @('8281', 'Återföring av nedskrivning av andelar i andra företag'))) {
                    Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $a[0] -AccountName $a[1]
                }
            }

            It 'Should deduct skattefria ränteintäkter (8314) on 4.5c (7754)' {
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-04-01' `
                    -Description 'Intäktsränta skattekonto' -Rows @(
                        @{ Account = '1930'; Amount = 395 }, @{ Account = '8314'; Amount = -395 })
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2S-2024P4' 7754 | Should -Be 395
                $r.SurplusDeficit | Should -Be 80000
            }

            It 'Should add back non-deductible costs (6072, 8423) on 4.3c (7653)' {
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-04-01' `
                    -Description 'Representation och kostnadsränta' -Rows @(
                        @{ Account = '6072'; Amount = 700 }, @{ Account = '8423'; Amount = 45 },
                        @{ Account = '1930'; Amount = -745 })
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2S-2024P4' 7653 | Should -Be 745
                $r.SurplusDeficit | Should -Be 80000
            }

            It 'Should add back write-downs of shares (827x) on 4.3b (7652) and warn about the assumption' {
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-12-31' `
                    -Description 'Nedskrivning Investor B' -Rows @(
                        @{ Account = '8271'; Amount = 12000 }, @{ Account = '1359'; Amount = -12000 })
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                    -WarningVariable warn -WarningAction SilentlyContinue
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2S-2024P4' 7652 | Should -Be 12000
                $r.SurplusDeficit | Should -Be 80000
                ($warn -join ' ') | Should -Match 'kapitalplaceringsaktier'
            }

            It 'Should deduct a net reversal of share write-downs (828x) on 4.5c (7754) and warn' {
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-12-31' `
                    -Description 'Återföring nedskrivning Investor B' -Rows @(
                        @{ Account = '1359'; Amount = 5000 }, @{ Account = '8281'; Amount = -5000 })
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                    -WarningVariable warn -WarningAction SilentlyContinue
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2S-2024P4' 7754 | Should -Be 5000
                Get-Uppgift $blk 'INK2S-2024P4' 7652 | Should -BeNullOrEmpty
                $r.SurplusDeficit | Should -Be 80000
                $warn | Should -Not -BeNullOrEmpty
            }

            It 'Should let -TaxAdjustment replace a derived amount without warning' {
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-12-31' `
                    -Description 'Nedskrivning lageraktier' -Rows @(
                        @{ Account = '8271'; Amount = 12000 }, @{ Account = '1359'; Amount = -12000 })
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                    -TaxAdjustment @{ '7652' = 0 } -WarningVariable warn -WarningAction SilentlyContinue
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2S-2024P4' 7652 | Should -BeNullOrEmpty
                $r.SurplusDeficit | Should -Be 68000
                $warn | Should -BeNullOrEmpty
            }

            It 'Should derive nothing with -NoAutomaticAdjustment' {
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-12-31' `
                    -Description 'Nedskrivning och ränta' -Rows @(
                        @{ Account = '8271'; Amount = 12000 }, @{ Account = '1359'; Amount = -12000 },
                        @{ Account = '1930'; Amount = 395 }, @{ Account = '8314'; Amount = -395 })
                $r = Export-LedgerIncomeTaxReturn -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $Dest `
                    -NoAutomaticAdjustment -WarningVariable warn -WarningAction SilentlyContinue
                $blk = Get-Content -LiteralPath (Join-Path $Dest 'BLANKETTER.SRU')
                Get-Uppgift $blk 'INK2S-2024P4' 7652 | Should -BeNullOrEmpty
                Get-Uppgift $blk 'INK2S-2024P4' 7754 | Should -BeNullOrEmpty
                $r.SurplusDeficit | Should -Be 68395
                $warn | Should -BeNullOrEmpty
            }
        }
    }
}
