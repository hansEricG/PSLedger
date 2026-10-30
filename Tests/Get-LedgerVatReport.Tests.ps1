BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerVatReport' {
    BeforeAll {
        $CommandName = 'Get-LedgerVatReport'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter, an optional FiscalYear parameter that binds from Name, and mandatory FromDate and ToDate parameters' {
            $journalPathParam = $Command.Parameters['JournalPath']
            $journalPathParam | Should -Not -BeNullOrEmpty
            $journalPathParam.Attributes.Mandatory | Should -Not -Contain $true

            $fiscalYearParam = $Command.Parameters['FiscalYear']
            $fiscalYearParam | Should -Not -BeNullOrEmpty
            $fiscalYearParam.Attributes.Mandatory | Should -Not -Contain $true
            $fiscalYearParam.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $fiscalYearParam.Aliases | Should -Contain 'Name'

            foreach ($p in 'FromDate', 'ToDate') {
                $Param = $Command.Parameters[$p]
                $Param | Should -Not -BeNullOrEmpty
                $Param.Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Moms AB' -OrgNumber '556677-8899'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2610' -AccountName 'Utgående moms 25%'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2640' -AccountName 'Ingående moms'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning tjänster'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '5010' -AccountName 'Lokalhyra'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2440' -AccountName 'Leverantörsskulder'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'

            # Sale: 10000 + 2500 moms = 12500
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-01-15' -Description 'Försäljning konsultarvode' -Rows @(
                    @{ Account = '1910'; Amount = 12500 }
                    @{ Account = '3010'; Amount = -10000 }
                    @{ Account = '2610'; Amount = -2500 }
                )

            # Purchase: hyra 8000 + moms 2000
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-02-01' -Description 'Hyra kontor' -Rows @(
                    @{ Account = '5010'; Amount = 8000 }
                    @{ Account = '2640'; Amount = 2000 }
                    @{ Account = '2440'; Amount = -10000 }
                )
        }

        It 'Should return Box 05 with taxable sales amount' {
            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31'
            $box05 = $result | Where-Object Box -eq 5
            $box05.Amount | Should -Be 10000
        }

        It 'Should return Box 10 with output VAT 25%' {
            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31'
            $box10 = $result | Where-Object Box -eq 10
            $box10.Amount | Should -Be 2500
        }

        It 'Should return Box 48 with input VAT' {
            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31'
            $box48 = $result | Where-Object Box -eq 48
            $box48.Amount | Should -Be 2000
        }

        It 'Should return Box 49 with VAT to pay (output - input)' {
            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31'
            $box49 = $result | Where-Object Box -eq 49
            $box49.Amount | Should -Be 500
        }

        It 'Should respect date range filtering' {
            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-01-31'
            $box48 = $result | Where-Object Box -eq 48
            $box48.Amount | Should -Be 0
            $box10 = $result | Where-Object Box -eq 10
            $box10.Amount | Should -Be 2500
        }

        It 'Should show negative Box 49 when input VAT exceeds output' {
            # Add a purchase with more input VAT than the sale generated
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-01' -Description 'Stor inventarieinköp' -Rows @(
                    @{ Account = '5010'; Amount = 20000 }
                    @{ Account = '2640'; Amount = 5000 }
                    @{ Account = '2440'; Amount = -25000 }
                )

            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31'
            $box49 = $result | Where-Object Box -eq 49
            $box49.Amount | Should -BeLessThan 0
        }

        It 'Should report reverse-charge purchases in boxes 21, 30 and 48 and keep box 49 net' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '4535' -AccountName 'Inköp av tjänster från annat EU-land, 25 %'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '4598' -AccountName 'Justering, omvänd moms'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2614' -AccountName 'Utgående moms omvänd skattskyldighet, 25 %'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2645' -AccountName 'Beräknad ingående moms på förvärv från utlandet'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-05' -Description 'Programvarulicens från Irland' -Rows @(
                    @{ Account = '4535'; Amount = 4000 }
                    @{ Account = '4598'; Amount = -4000 }
                    @{ Account = '2645'; Amount = 1000 }
                    @{ Account = '2614'; Amount = -1000 }
                )

            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31'
            ($result | Where-Object Box -eq 21).Amount | Should -Be 4000
            ($result | Where-Object Box -eq 30).Amount | Should -Be 1000
            ($result | Where-Object Box -eq 48).Amount | Should -Be 3000
            ($result | Where-Object Box -eq 49).Amount | Should -Be 500
        }

        It 'Should report sales outside Sweden in their own boxes instead of box 05' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3308' -AccountName 'Försäljning tjänster till annat EU-land'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3105' -AccountName 'Försäljning varor till land utanför EU'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-10' -Description 'Konsultuppdrag Tyskland och export Norge' -Rows @(
                    @{ Account = '1910'; Amount = 9000 }
                    @{ Account = '3308'; Amount = -6000 }
                    @{ Account = '3105'; Amount = -3000 }
                )

            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31'
            ($result | Where-Object Box -eq 39).Amount | Should -Be 6000
            ($result | Where-Object Box -eq 36).Amount | Should -Be 3000
            ($result | Where-Object Box -eq 5).Amount | Should -Be 10000
        }

        It 'Should only return boxes 05, 10, 11, 12, 48 and 49 when no other box has activity' {
            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31'
            $result.Box | Should -Be @(5, 10, 11, 12, 48, 49)
        }

        It 'Should exclude negative VMB sales without reducing a positive taxable margin' {
            foreach ($account in '3211', '3212', '4212', '2616') {
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $account -AccountName $account
            }
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-01' `
                -Description 'Negativ VMB: inköp 600, försäljning 500' -Rows @(
                    @{ Account = '4212'; Amount = 600 }
                    @{ Account = '1910'; Amount = -600 }
                    @{ Account = '1910'; Amount = 500 }
                    @{ Account = '3212'; Amount = -500 }
                )
            $negative = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-03-01' -ToDate '2024-03-31'
            $negative | Where-Object Amount -ne 0 | Should -BeNullOrEmpty

            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-02' `
                -Description 'Separat bokförd positiv vinstmarginal' -Rows @(
                    @{ Account = '1910'; Amount = 400 }
                    @{ Account = '3211'; Amount = -320 }
                    @{ Account = '2616'; Amount = -80 }
                )
            $mixed = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-03-01' -ToDate '2024-03-31'
            ($mixed | Where-Object Box -eq 7).Amount | Should -Be 320
            ($mixed | Where-Object Box -eq 10).Amount | Should -Be 80
            ($mixed | Where-Object Box -eq 5).Amount | Should -Be 0
        }

        It 'Should distinguish voluntarily taxed rent from other taxable rent' {
            foreach ($account in '3913', '3914') {
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $account -AccountName $account
            }
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-01' `
                -Description 'Hyresintäkter' -Rows @(
                    @{ Account = '1910'; Amount = 3750 }
                    @{ Account = '3913'; Amount = -2000 }
                    @{ Account = '3914'; Amount = -1000 }
                    @{ Account = '2610'; Amount = -750 }
                )
            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-03-01' -ToDate '2024-03-31'
            ($result | Where-Object Box -eq 8).Amount | Should -Be 2000
            ($result | Where-Object Box -eq 5).Amount | Should -Be 1000
            ($result | Where-Object Box -eq 10).Amount | Should -Be 750
        }

        It 'Should apply vat.txt overrides before the default mapping' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3300' -AccountName 'Försäljning tjänster EU'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-12' -Description 'Konsultuppdrag Danmark' -Rows @(
                    @{ Account = '1910'; Amount = 7000 }
                    @{ Account = '3300'; Amount = -7000 }
                )
            Set-Content -LiteralPath (Join-Path $JournalPath 'vat.txt') -Encoding UTF8 -Value @(
                '; PSLedger VAT mapping: Account or range, Box'
                "3300`t39"
                "2640-2649`t-"
            )

            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -WarningVariable warnings -WarningAction SilentlyContinue
            ($result | Where-Object Box -eq 39).Amount | Should -Be 7000
            ($result | Where-Object Box -eq 5).Amount | Should -Be 10000
            ($result | Where-Object Box -eq 48).Amount | Should -Be 0
            $warnings | Should -BeNullOrEmpty
        }

        It 'Should throw on a vat.txt line with an unknown box' {
            Set-Content -LiteralPath (Join-Path $JournalPath 'vat.txt') -Encoding UTF8 -Value "3300`t99"
            { Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' } | Should -Throw '*line 1*not a VAT declaration box*'
        }

        It 'Should warn about an unmapped account in 3100-3399 that falls into box 05' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3300' -AccountName 'Försäljning tjänster EU'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-12' -Description 'Konsultuppdrag Danmark' -Rows @(
                    @{ Account = '1910'; Amount = 7000 }
                    @{ Account = '3300'; Amount = -7000 }
                )

            $result = Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -WarningVariable warnings -WarningAction SilentlyContinue
            ($result | Where-Object Box -eq 5).Amount | Should -Be 17000
            $warnings | Should -HaveCount 1
            "$warnings" | Should -BeLike '*3300*vat.txt*'
        }
    }
}
