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
            [int]$moms.MomsIngaende | Should -Be 2000
            [int]$moms.MomsBetala | Should -Be 500
        }

        It 'Should compute MomsBetala as output VAT minus input VAT' {
            $result = Export-LedgerVatDeclaration -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate '2024-01-01' -ToDate '2024-03-31' -Path $OutPath
            $result.Boxes.'49' | Should -Be 500
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
            [int]$xml.eSKDUpload.Moms.MomsIngaende | Should -Be 0
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
