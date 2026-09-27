BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Test-LedgerFiscalYear' {
    BeforeAll {
        $CommandName = 'Test-LedgerFiscalYear'
        $Command = Get-Command -Name $CommandName

        function New-CheckJournal {
            param ([string]$Path)
            New-LedgerJournal -Path $Path -Name 'Kontroll AB' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $Path -StartDate '2024-01-01' -EndDate '2024-12-31'
            '1910 Kassa', '3010 Försäljning', '5010 Lokalhyra', '2440 Leverantörsskulder', '8999 Årets resultat', '2099 Årets resultat EK' |
                ForEach-Object {
                    $n, $nm = $_ -split ' ', 2
                    Add-LedgerAccount -JournalPath $Path -AccountNumber $n -AccountName $nm
                }
        }

        function Get-CheckStatus {
            param ($Results, [string]$Check)
            ($Results | Where-Object { $_.Check -eq $Check }).Status
        }
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
            $Param.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $Param.Aliases | Should -Contain 'Name'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            $FiscalYear = '2024-01_2024-12'
            New-CheckJournal -Path $JournalPath
        }

        It 'Should return one result object per check' {
            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Results | Should -Not -BeNullOrEmpty
            $Results.Check | Should -Contain 'VerificationsBalance'
            $Results.Check | Should -Contain 'VerificationNumbering'
            $Results.Check | Should -Contain 'NoEmptyVerifications'
            $Results.Check | Should -Contain 'LedgerBalances'
            $Results.Check | Should -Contain 'OpeningBalanceBalances'
            $Results.Check | Should -Contain 'OpeningBalanceMatchesPrevious'
        }

        It 'Should include the fiscal year on each result' {
            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            ($Results | Select-Object -ExpandProperty FiscalYear -Unique) | Should -Be $FiscalYear
        }

        It 'Should pass all hard checks for a clean fiscal year' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-01' `
                -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 5000 }
                @{ Account = '3010'; Amount = -5000 }
            )

            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            (Get-CheckStatus $Results 'VerificationsBalance') | Should -Be 'Pass'
            (Get-CheckStatus $Results 'VerificationNumbering') | Should -Be 'Pass'
            (Get-CheckStatus $Results 'NoEmptyVerifications') | Should -Be 'Pass'
            (Get-CheckStatus $Results 'LedgerBalances') | Should -Be 'Pass'
        }

        It 'Should report Info for numbering when there are no verifications' {
            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            (Get-CheckStatus $Results 'VerificationNumbering') | Should -Be 'Info'
        }

        It 'Should fail VerificationNumbering when there is a gap' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-01' `
                -Description 'Ett' -Rows @(@{ Account = '1910'; Amount = 100 }, @{ Account = '3010'; Amount = -100 })
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-02' `
                -Description 'Två' -Rows @(@{ Account = '1910'; Amount = 200 }, @{ Account = '3010'; Amount = -200 })
            Remove-Item (Join-Path $JournalPath $FiscalYear 'ver0001.txt') -Force

            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            (Get-CheckStatus $Results 'VerificationNumbering') | Should -Be 'Fail'
        }

        It 'Should fail VerificationsBalance for an unbalanced verification' {
            # Write an unbalanced verification file directly (bypassing Add-LedgerEntry).
            $VerPath = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            Set-Content -Path $VerPath -Encoding UTF8 -Value @(
                'Date: 2024-03-01'
                'Description: Obalanserad'
                ''
                "1910`t500"
                "3010`t-400"
            )

            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            (Get-CheckStatus $Results 'VerificationsBalance') | Should -Be 'Fail'
            (Get-CheckStatus $Results 'LedgerBalances') | Should -Be 'Fail'
        }

        It 'Should fail NoEmptyVerifications for a single-row verification' {
            $VerPath = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            Set-Content -Path $VerPath -Encoding UTF8 -Value @(
                'Date: 2024-03-01'
                'Description: Tom'
                ''
                "1910`t0"
            )

            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            (Get-CheckStatus $Results 'NoEmptyVerifications') | Should -Be 'Fail'
        }

        It 'Should report Info for opening balance checks when there is none' {
            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            (Get-CheckStatus $Results 'OpeningBalanceBalances') | Should -Be 'Info'
            (Get-CheckStatus $Results 'OpeningBalanceMatchesPrevious') | Should -Be 'Info'
        }
    }

    Context 'Opening balance reconciliation' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-CheckJournal -Path $JournalPath

            # Prior year with a profit, closed (booking the result to 2099).
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -Date '2024-03-01' `
                -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 5000 }
                @{ Account = '3010'; Amount = -5000 }
            )
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-01-01' -EndDate '2025-12-31'
            $NextYear = '2025-01_2025-12'
        }

        It 'Should pass reconciliation after Copy-LedgerOpeningBalance' {
            Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2024-01_2024-12' -ToFiscalYear $NextYear

            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $NextYear

            (Get-CheckStatus $Results 'OpeningBalanceMatchesPrevious') | Should -Be 'Pass'
            (Get-CheckStatus $Results 'OpeningBalanceBalances') | Should -Be 'Pass'
        }

        It 'Should warn when the opening balance does not match the previous closing' {
            # Write an opening balance that does not reconcile with 2024.
            Set-Content -Path (Join-Path $JournalPath $NextYear 'ib.txt') -Encoding UTF8 -Value @(
                "1910`t9999"
                "2099`t-9999"
            )

            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $NextYear

            (Get-CheckStatus $Results 'OpeningBalanceMatchesPrevious') | Should -Be 'Warning'
        }
    }

    Context 'Holdings' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            $FiscalYear = '2024-01_2024-12'
            New-CheckJournal -Path $JournalPath
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1350' -AccountName 'Andelar och värdepapper'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1810' -AccountName 'Andelar i börsnoterade företag'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-02-01' -Description 'Köp värdepapper' -Rows @(
                @{ Account = '1350'; Amount = 100000 }, @{ Account = '1810'; Amount = 10000 }, @{ Account = '1910'; Amount = -110000 })
        }

        It 'Should report Info when there are no holdings' {
            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear
            (Get-CheckStatus $Results 'HoldingsValuation') | Should -Be 'Info'
            (Get-CheckStatus $Results 'HoldingsReconcile') | Should -Be 'Info'
        }

        It 'Should pass when holdings are above book value and reconcile' {
            Set-LedgerHolding -JournalPath $JournalPath -FiscalYear $FiscalYear -Account 1350 -Name 'Investor B' `
                -Quantity 500 -Price 265.40 -PriceDate '2024-12-31' -BookValue 100000
            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear
            (Get-CheckStatus $Results 'HoldingsValuation') | Should -Be 'Pass'
            (Get-CheckStatus $Results 'HoldingsReconcile') | Should -Be 'Pass'
        }

        It 'Should warn about a lasting decline for a financial fixed asset below book value' {
            Set-LedgerHolding -JournalPath $JournalPath -FiscalYear $FiscalYear -Account 1350 -Name 'Investor B' -Quantity 300 -Price 265.40
            $Results = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Check = $Results | Where-Object Check -eq 'HoldingsValuation'
            $Check.Status | Should -Be 'Warning'
            $Check.Detail | Should -Match 'Account 1350.*lasting'
        }

        It 'Should warn about the lower of cost and market value for a short-term holding' {
            Set-LedgerHolding -JournalPath $JournalPath -FiscalYear $FiscalYear -Account 1810 -Name 'Spiltan Räntefond' -Quantity 800 -Price 11.83
            $Check = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear | Where-Object Check -eq 'HoldingsValuation'
            $Check.Status | Should -Be 'Warning'
            $Check.Detail | Should -Match 'Account 1810.*lägsta värdets princip'
        }

        It 'Should warn when the holdings book values do not match the ledger balance' {
            Set-LedgerHolding -JournalPath $JournalPath -FiscalYear $FiscalYear -Account 1350 -Name 'Investor B' `
                -Quantity 500 -Price 265.40 -PriceDate '2024-12-31' -BookValue 90000
            $Check = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear | Where-Object Check -eq 'HoldingsReconcile'
            $Check.Status | Should -Be 'Warning'
            $Check.Detail | Should -Match 'does not match the ledger balance'
        }

        It 'Should not reconcile book values when some holdings on the account lack one' {
            Set-LedgerHolding -JournalPath $JournalPath -FiscalYear $FiscalYear -Account 1350 -Name 'Investor B' `
                -Quantity 500 -Price 265.40 -PriceDate '2024-12-31' -BookValue 60000
            Set-LedgerHolding -JournalPath $JournalPath -FiscalYear $FiscalYear -Account 1350 -Name 'Atlas Copco A' `
                -Quantity 100 -Price 150 -PriceDate '2024-12-31'
            (Get-CheckStatus (Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear) 'HoldingsReconcile') | Should -Be 'Pass'
        }

        It 'Should warn when a price date is not the balance date' {
            Set-LedgerHolding -JournalPath $JournalPath -FiscalYear $FiscalYear -Account 1350 -Name 'Investor B' `
                -Quantity 500 -Price 265.40 -PriceDate '2024-12-30'
            $Check = Test-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear | Where-Object Check -eq 'HoldingsReconcile'
            $Check.Status | Should -Be 'Warning'
            $Check.Detail | Should -Match 'not the balance date 2024-12-31'
        }
    }
}
