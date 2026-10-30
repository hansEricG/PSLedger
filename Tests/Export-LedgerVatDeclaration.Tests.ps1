BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Export-LedgerVatDeclaration' {
    BeforeAll {
        $CommandName = 'Export-LedgerVatDeclaration'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional JournalPath, an optional FiscalYear that binds from Name, and mandatory FromDate, ToDate and Path parameters' {
            $journalPathParam = $Command.Parameters['JournalPath']
            $journalPathParam | Should -Not -BeNullOrEmpty
            $journalPathParam.Attributes.Mandatory | Should -Not -Contain $true

            $fiscalYearParam = $Command.Parameters['FiscalYear']
            $fiscalYearParam | Should -Not -BeNullOrEmpty
            $fiscalYearParam.Attributes.Mandatory | Should -Not -Contain $true
            $fiscalYearParam.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $fiscalYearParam.Aliases | Should -Contain 'Name'

            foreach ($p in 'FromDate', 'ToDate', 'Path') {
                $Param = $Command.Parameters[$p]
                $Param | Should -Not -BeNullOrEmpty
                $Param.Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'Should have an optional Period parameter and a Force switch' {
            $periodParam = $Command.Parameters['Period']
            $periodParam | Should -Not -BeNullOrEmpty
            $periodParam.Attributes.Mandatory | Should -Not -Contain $true

            $forceParam = $Command.Parameters['Force']
            $forceParam | Should -Not -BeNullOrEmpty
            $forceParam.SwitchParameter | Should -BeTrue
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

            $OutPath = Join-Path $TestDrive "$JournalName-moms-q1.xml"
        }

        It 'Should write an eSKD file to the destination path' {
            Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath | Out-Null
            Test-Path -LiteralPath $OutPath | Should -BeTrue
        }

        It 'Should produce a valid eSKDUpload XML document with OrgNr and period' {
            Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath | Out-Null
            [xml]$xml = Get-Content -LiteralPath $OutPath -Raw
            $xml.eSKDUpload.Version | Should -Be '6.0'
            $xml.eSKDUpload.OrgNr | Should -Be '556677-8899'
            $xml.eSKDUpload.Moms.Period | Should -Be '202403'
        }

        It 'Should map the VAT boxes to the correct eSKD tags' {
            Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath | Out-Null
            [xml]$xml = Get-Content -LiteralPath $OutPath -Raw
            $moms = $xml.eSKDUpload.Moms
            [int]$moms.ForsMomsEjAnnan | Should -Be 10000
            [int]$moms.MomsUtgHog | Should -Be 2500
            [int]$moms.MomsIngAvdr | Should -Be 2000
            [int]$moms.MomsBetala | Should -Be 500
        }

        It 'Should compute MomsBetala as output VAT minus input VAT' {
            $result = Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath
            $result.Boxes.'49' | Should -Be 500
        }

        It 'Should write the extra boxes with activity and include them in MomsBetala' {
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

            $result = Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath
            [xml]$xml = Get-Content -LiteralPath $OutPath -Raw
            $moms = $xml.eSKDUpload.Moms
            [int]$moms.InkopTjanstAnnatEg | Should -Be 4000
            [int]$moms.MomsInkopUtgHog | Should -Be 1000
            [int]$moms.MomsIngAvdr | Should -Be 3000
            [int]$moms.MomsBetala | Should -Be 500
            $result.Boxes.'21' | Should -Be 4000
            $result.Boxes.'30' | Should -Be 1000
            @($moms.ChildNodes.Name) | Should -Be @('Period', 'ForsMomsEjAnnan', 'InkopTjanstAnnatEg',
                'MomsUtgHog', 'MomsUtgMedel', 'MomsUtgLag', 'MomsInkopUtgHog', 'MomsIngAvdr', 'MomsBetala')
        }

        It 'Should return a summary object with Path, OrgNumber and Period' {
            $result = Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath
            $result.OrgNumber | Should -Be '556677-8899'
            $result.Period | Should -Be '202403'
            $result.Path | Should -Be ([System.IO.Path]::GetFullPath($OutPath))
        }

        It 'Should honour an explicit Period override' {
            $result = Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Period '202401' -Path $OutPath
            $result.Period | Should -Be '202401'
            [xml]$xml = Get-Content -LiteralPath $OutPath -Raw
            $xml.eSKDUpload.Moms.Period | Should -Be '202401'
        }

        It 'Should respect date-range filtering for the reported boxes' {
            Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-01-31' -Path $OutPath | Out-Null
            [xml]$xml = Get-Content -LiteralPath $OutPath -Raw
            [int]$xml.eSKDUpload.Moms.MomsIngAvdr | Should -Be 0
            [int]$xml.eSKDUpload.Moms.MomsUtgHog | Should -Be 2500
        }

        It 'Should be written with ISO-8859-1 encoding declared in the prolog' {
            Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath | Out-Null
            $firstLine = (Get-Content -LiteralPath $OutPath -TotalCount 1)
            $firstLine | Should -Match 'encoding="ISO-8859-1"'
        }

        It 'Should refuse to overwrite an existing file without -Force' {
            Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath | Out-Null
            { Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath } |
                Should -Throw '*already exists*'
        }

        It 'Should overwrite an existing file with -Force' {
            Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath | Out-Null
            { Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath -Force } |
                Should -Not -Throw
        }

        It 'Should throw when the journal has no OrgNumber' {
            $NoOrgPath = Join-Path $TestDrive 'NoOrg.ledger'
            New-LedgerJournal -Path $NoOrgPath -Name 'Utan Orgnr AB'
            New-LedgerFiscalYear -JournalPath $NoOrgPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            { Export-LedgerVatDeclaration -JournalPath $NoOrgPath -FiscalYear '2024-01_2024-12' `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path (Join-Path $TestDrive 'noorg.xml') } |
                Should -Throw '*OrgNumber*'
        }
    }
}

Describe 'VAT declaration reference examples' {
    # Expected values are hand-calculated, not derived from PSLedger mappings.
    # Skatteverket: fields 05/07, 37/38, 48/49 and 50/60-62:
    # https://www.skatteverket.se/foretag/moms/deklareramoms/fyllaimomsdeklarationen.4.3a2a542410ab40a421c80004214.html
    # eSKD names and order:
    # https://www.skatteverket.se/foretag/moms/deklareramoms/lamnamomsdeklarationviafilietjansten.4.2fb39afe18dabf1e4d223cc.html
    It 'Should report and export <Case>' -ForEach @(
        @{
            Case = 'import VAT at three rates with full input deduction'
            Rows = @(
                # Taxable value 11,000 = customs value 10,000 + duty 500 + freight 500.
                @{ Account = '4545'; Amount = 11000 }; @{ Account = '4598'; Amount = -11000 }
                @{ Account = '2615'; Amount = -2750 }; @{ Account = '2645'; Amount = 2750 }
                @{ Account = '4546'; Amount = 2000 }; @{ Account = '4598'; Amount = -2000 }
                @{ Account = '2625'; Amount = -240 }; @{ Account = '2645'; Amount = 240 }
                @{ Account = '4547'; Amount = 1000 }; @{ Account = '4598'; Amount = -1000 }
                @{ Account = '2635'; Amount = -60 }; @{ Account = '2645'; Amount = 60 }
            )
            Rules = @()
            Expected = @{ 5 = 0; 10 = 0; 11 = 0; 12 = 0; 48 = 3050; 49 = 0; 50 = 14000; 60 = 2750; 61 = 240; 62 = 60 }
            XmlAmounts = [ordered]@{
                ForsMomsEjAnnan = 0; MomsUlagImport = 14000
                MomsUtgHog = 0; MomsUtgMedel = 0; MomsUtgLag = 0
                MomsImportUtgHog = 2750; MomsImportUtgMedel = 240; MomsImportUtgLag = 60
                MomsIngAvdr = 3050; MomsBetala = 0
            }
        }
        @{
            Case = 'a period containing sales and purchase credit notes'
            Rows = @(
                @{ Account = '1510'; Amount = -1250 }; @{ Account = '3010'; Amount = 1000 }; @{ Account = '2610'; Amount = 250 }
                @{ Account = '2440'; Amount = 500 }; @{ Account = '5010'; Amount = -400 }; @{ Account = '2640'; Amount = -100 }
            )
            Rules = @()
            Expected = @{ 5 = -1000; 10 = -250; 11 = 0; 12 = 0; 48 = -100; 49 = -150 }
            XmlAmounts = [ordered]@{
                ForsMomsEjAnnan = -1000; MomsUtgHog = -250; MomsUtgMedel = 0; MomsUtgLag = 0
                MomsIngAvdr = -100; MomsBetala = -150
            }
        }
        @{
            Case = 'triangular trade as the intermediary without acquisition VAT'
            Rows = @(
                @{ Account = '4512'; Amount = 10000 }; @{ Account = '2440'; Amount = -10000 }
                @{ Account = '1510'; Amount = 12500 }; @{ Account = '3107'; Amount = -12500 }
            )
            Rules = @()
            Expected = @{ 5 = 0; 10 = 0; 11 = 0; 12 = 0; 37 = 10000; 38 = 12500; 48 = 0; 49 = 0 }
            XmlAmounts = [ordered]@{
                ForsMomsEjAnnan = 0; InkopVaruMellan3p = 10000; ForsVaruMellan3p = 12500
                MomsUtgHog = 0; MomsUtgMedel = 0; MomsUtgLag = 0; MomsIngAvdr = 0; MomsBetala = 0
            }
        }
        @{
            Case = 'separately booked positive VMB alongside a loss-making sale'
            # Purchase 100, sale 500 => margin 400, taxable base 320, VAT 80.
            # The purchase-price component on 3223 is explicitly excluded.
            # Booking convention: https://www.bokio.se/hjalp/bokforing/bokforingshjalp/hur-bokfor-jag-vinstmarginalbeskattning/
            Rows = @(
                @{ Account = '4211'; Amount = 100 }; @{ Account = '1930'; Amount = -100 }
                @{ Account = '1930'; Amount = 500 }; @{ Account = '3211'; Amount = -320 }
                @{ Account = '3223'; Amount = -100 }; @{ Account = '2616'; Amount = -80 }
                @{ Account = '4212'; Amount = 600 }; @{ Account = '1930'; Amount = -600 }
                @{ Account = '1930'; Amount = 500 }; @{ Account = '3212'; Amount = -500 }
            )
            Rules = @("3223`t-")
            Expected = @{ 5 = 0; 7 = 320; 10 = 80; 11 = 0; 12 = 0; 48 = 0; 49 = 80 }
            XmlAmounts = [ordered]@{
                ForsMomsEjAnnan = 0; UlagMargbesk = 320; MomsUtgHog = 80
                MomsUtgMedel = 0; MomsUtgLag = 0; MomsIngAvdr = 0; MomsBetala = 80
            }
        }
    ) {
        $journal = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).ledger"
        New-LedgerJournal -Path $journal -Name 'Momsreferens AB' -OrgNumber '556677-8899'
        New-LedgerFiscalYear -JournalPath $journal -StartDate '2024-01-01' -EndDate '2024-12-31'
        foreach ($account in $Rows.Account | Sort-Object -Unique) {
            Add-LedgerAccount -JournalPath $journal -AccountNumber $account -AccountName "Konto $account"
        }
        if ($Rules.Count -gt 0) { Set-Content -LiteralPath (Join-Path $journal 'vat.txt') -Value $Rules }
        Add-LedgerEntry -JournalPath $journal -FiscalYear '2024-01_2024-12' -Date '2024-01-15' -Description $Case -Rows $Rows
        $period = @{ JournalPath = $journal; FiscalYear = '2024-01_2024-12'; FromDate = '2024-01-01'; ToDate = '2024-01-31' }
        $report = @(Get-LedgerVatReport @period)
        @($report.Box | Sort-Object) | Should -Be @($Expected.Keys | Sort-Object)
        foreach ($box in $report) { $box.Amount | Should -Be $Expected[$box.Box] }

        $path = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).xml"
        Export-LedgerVatDeclaration @period -Path $path | Out-Null
        [xml]$xml = Get-Content -LiteralPath $path -Raw
        $moms = $xml.eSKDUpload.Moms
        @($moms.ChildNodes.Name) | Should -Be (@('Period') + @($XmlAmounts.Keys))
        foreach ($tag in $XmlAmounts.Keys) { [long]$moms.$tag | Should -Be $XmlAmounts[$tag] }
    }
}
