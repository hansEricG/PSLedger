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
    }
}
