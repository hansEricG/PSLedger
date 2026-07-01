BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerLedger' {
    BeforeAll {
        $CommandName = 'Get-LedgerLedger'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have an optional FiscalYear parameter of type String that binds from Name' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
            $Param.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $Param.Aliases | Should -Contain 'Name'
        }

        It 'Should have a mandatory Account parameter of type String' {
            $Param = $Command.Parameters['Account']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have optional FromDate and ToDate parameters' {
            $Command.Parameters['FromDate'].ParameterType.Name | Should -Be 'DateTime'
            $Command.Parameters['ToDate'].ParameterType.Name | Should -Be 'DateTime'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa och bank'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '5010' -AccountName 'Lokalhyra'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'

            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-01-15' -Description 'Försäljning kontant' -Rows @(
                    @{ Account = '1910'; Amount = 5000 }
                    @{ Account = '3010'; Amount = -5000 }
                )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-02-01' -Description 'Hyra kontor' -Rows @(
                    @{ Account = '5010'; Amount = 8000 }
                    @{ Account = '1910'; Amount = -8000 }
                )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date '2024-03-10' -Description 'Försäljning faktura' -Rows @(
                    @{ Account = '1910'; Amount = 3000 }
                    @{ Account = '3010'; Amount = -3000 }
                )
        }

        It 'Should return transactions in chronological order' {
            $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910')
            $result.Count | Should -Be 3
            $result[0].Date | Should -Be '2024-01-15'
            $result[1].Date | Should -Be '2024-02-01'
            $result[2].Date | Should -Be '2024-03-10'
        }

        It 'Should calculate running balance correctly' {
            $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910')
            $result[0].Balance | Should -Be 5000
            $result[1].Balance | Should -Be -3000
            $result[2].Balance | Should -Be 0
        }

        It 'Should split amount into Debit and Credit columns' {
            $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910')
            $result[0].Debit | Should -Be 5000
            $result[0].Credit | Should -Be 0
            $result[1].Debit | Should -Be 0
            $result[1].Credit | Should -Be 8000
        }

        It 'Should include VerificationNumber and Description' {
            $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910')
            $result[0].VerificationNumber | Should -Be 1
            $result[0].Description | Should -Be 'Försäljning kontant'
        }

        It 'Should filter by FromDate' {
            $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910' -FromDate '2024-02-01')
            $result.Count | Should -Be 2
            $result[0].Date | Should -Be '2024-02-01'
        }

        It 'Should filter by ToDate' {
            $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910' -ToDate '2024-01-31')
            $result.Count | Should -Be 1
            $result[0].Date | Should -Be '2024-01-15'
        }

        It 'Should filter by both FromDate and ToDate' {
            $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910' -FromDate '2024-02-01' -ToDate '2024-02-28')
            $result.Count | Should -Be 1
            $result[0].Description | Should -Be 'Hyra kontor'
        }

        It 'Should return nothing for an account with no transactions' {
            $result = Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '5010' -FromDate '2024-06-01'
            $result | Should -BeNullOrEmpty
        }

        It 'Should return nothing when the fiscal year has no entries' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-01-01' -EndDate '2025-12-31'
            $result = Get-LedgerLedger -JournalPath $JournalPath -FiscalYear '2025-01_2025-12' -Account '1910'
            $result | Should -BeNullOrEmpty
        }

        Context 'Opening balance (ingående saldo)' {
            BeforeEach {
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2010' -AccountName 'Eget kapital'
                # Account 1910 starts the year with an opening balance of 4000 (debit).
                $IbFile = Join-Path $JournalPath $FiscalYear 'ib.txt'
                @(
                    "1910`t4000"
                    "2010`t-4000"
                ) | Set-Content -Path $IbFile -Encoding UTF8
            }

            It 'Should show the opening balance as the first row' {
                $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910')
                $result[0].Description | Should -Be 'Ingående balans'
                $result[0].Debit | Should -Be 0
                $result[0].Credit | Should -Be 0
                $result[0].Balance | Should -Be 4000
            }

            It 'Should continue the running balance from the opening balance' {
                $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910')
                # IB 4000, +5000 sale, -8000 rent, +3000 sale
                $result[1].Balance | Should -Be 9000
                $result[2].Balance | Should -Be 1000
                $result[3].Balance | Should -Be 4000
            }

            It 'Should not list the opening balance as a regular transaction row' {
                $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910')
                # 1 opening row + 3 transaction rows
                $result.Count | Should -Be 4
                $transactionRows = $result | Select-Object -Skip 1
                ($transactionRows | Where-Object Description -eq 'Ingående balans') | Should -BeNullOrEmpty
            }

            It 'Should carry pre-FromDate transactions into the opening row balance' {
                # IB 4000 + 5000 (2024-01-15, before FromDate) = 9000 brought forward.
                $result = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910' -FromDate '2024-02-01')
                $result[0].Description | Should -Be 'Ingående balans'
                $result[0].Balance | Should -Be 9000
                $result[0].Date | Should -Be '2024-02-01'
                # First in-range transaction: -8000 -> 1000, then +3000 -> 4000.
                $result[1].Balance | Should -Be 1000
                $result[2].Balance | Should -Be 4000
                $result.Count | Should -Be 3
            }

            It 'Should keep the closing balance correct regardless of FromDate' {
                $full = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910')
                $filtered = @(Get-LedgerLedger -JournalPath $JournalPath -FiscalYear $FiscalYear -Account '1910' -FromDate '2024-02-01')
                $filtered[-1].Balance | Should -Be $full[-1].Balance
            }
        }
    }
}
