BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerBalance' {
    BeforeAll {
        $CommandName = 'Get-LedgerBalance'
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
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'

            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2440' -AccountName 'Leverantörsskulder'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning tjänster'

            $Rows1 = @(
                @{ Account = '1910'; Amount = 5000 }
                @{ Account = '3010'; Amount = -5000 }
            )
            $Rows2 = @(
                @{ Account = '1910'; Amount = 3000 }
                @{ Account = '3010'; Amount = -3000 }
            )
            $Rows3 = @(
                @{ Account = '2440'; Amount = -2000 }
                @{ Account = '1910'; Amount = 2000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Försäljning 1' -Rows $Rows1
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-02-10' -Description 'Försäljning 2' -Rows $Rows2
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-01' -Description 'Skuld leverantör' -Rows $Rows3
        }

        It 'Should return one object per account that has transactions' {
            $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result.Count | Should -Be 3
        }

        It 'Should return objects with AccountNumber, AccountName, Debit, Credit, and Balance' {
            $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Kassa = $Result | Where-Object { $_.AccountNumber -eq '1910' }
            $Kassa.AccountName | Should -Be 'Kassa'
            $Kassa.Debit | Should -Be 10000
            $Kassa.Credit | Should -Be 0
            $Kassa.Balance | Should -Be 10000
        }

        It 'Should calculate credit as absolute value of negative amounts' {
            $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Sales = $Result | Where-Object { $_.AccountNumber -eq '3010' }
            $Sales.AccountName | Should -Be 'Försäljning tjänster'
            $Sales.Debit | Should -Be 0
            $Sales.Credit | Should -Be 8000
            $Sales.Balance | Should -Be -8000
        }

        It 'Should handle accounts with both debit and credit transactions' {
            $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Lev = $Result | Where-Object { $_.AccountNumber -eq '2440' }
            $Lev.AccountName | Should -Be 'Leverantörsskulder'
            $Lev.Debit | Should -Be 0
            $Lev.Credit | Should -Be 2000
            $Lev.Balance | Should -Be -2000
        }

        It 'Should sort results by AccountNumber' {
            $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result[0].AccountNumber | Should -Be '1910'
            $Result[1].AccountNumber | Should -Be '2440'
            $Result[2].AccountNumber | Should -Be '3010'
        }

        It 'Should return empty if no entries exist' {
            $EmptyJournal = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $EmptyJournal -Name 'Tom AB'
            New-LedgerFiscalYear -JournalPath $EmptyJournal -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Result = Get-LedgerBalance -JournalPath $EmptyJournal -FiscalYear '2024-01_2024-12'

            $Result | Should -BeNullOrEmpty
        }

        It 'Should throw if fiscal year directory does not exist' {
            { Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2099-01_2099-12' } | Should -Throw
        }

        It 'Should show AccountName as empty string for accounts not in chart' {
            # Simulate a legacy entry with an account that is not in the current chart
            $VerFile = Join-Path $JournalPath $FiscalYear 'ver0004.txt'
            @(
                'Date: 2024-04-01'
                'Description: Legacy post'
                ''
                "9999`t100"
                "1910`t-100"
            ) | Set-Content -Path $VerFile -Encoding UTF8

            $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Unknown = $Result | Where-Object { $_.AccountNumber -eq '9999' }
            $Unknown.AccountName | Should -Be ''
        }

        It 'Should have total debit equal total credit (double-entry proof)' {
            $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear

            $TotalDebit = ($Result | Measure-Object -Property Debit -Sum).Sum
            $TotalCredit = ($Result | Measure-Object -Property Credit -Sum).Sum
            $TotalDebit | Should -Be $TotalCredit
        }

        Context 'Opening balance (ingående saldo)' {
            BeforeEach {
                # Account 1910 starts with an opening balance of 4000 (debit),
                # offset by equity account 2010 (credit).
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2010' -AccountName 'Eget kapital'
                $IbFile = Join-Path $JournalPath $FiscalYear 'ver0000.txt'
                @(
                    'Date: 2024-01-01'
                    'Description: Ingående balans'
                    ''
                    "1910`t4000"
                    "2010`t-4000"
                ) | Set-Content -Path $IbFile -Encoding UTF8
            }

            It 'Should report the opening balance separately from transactions' {
                $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
                $Kassa = $Result | Where-Object { $_.AccountNumber -eq '1910' }

                $Kassa.OpeningBalance | Should -Be 4000
                # Transactions only: 5000 + 3000 + 2000 = 10000 debit, no credit
                $Kassa.Debit | Should -Be 10000
                $Kassa.Credit | Should -Be 0
            }

            It 'Should compute Balance as OpeningBalance + Debit - Credit (utgående saldo)' {
                $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
                $Kassa = $Result | Where-Object { $_.AccountNumber -eq '1910' }

                # 4000 opening + 10000 debit - 0 credit = 14000
                $Kassa.Balance | Should -Be 14000
            }

            It 'Should not count opening balance amounts in Debit or Credit' {
                $Result = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
                $Equity = $Result | Where-Object { $_.AccountNumber -eq '2010' }

                $Equity.OpeningBalance | Should -Be -4000
                $Equity.Debit | Should -Be 0
                $Equity.Credit | Should -Be 0
                $Equity.Balance | Should -Be -4000
            }
        }
    }
}
