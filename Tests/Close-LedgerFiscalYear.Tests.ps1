BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Close-LedgerFiscalYear' {
    BeforeAll {
        $CommandName = 'Close-LedgerFiscalYear'
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

        It 'Should support ShouldProcess (-WhatIf / -Confirm)' {
            $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
            $Command.Parameters.ContainsKey('Confirm') | Should -BeTrue
        }

        It 'Should have an optional EquityAccount parameter of type String' {
            $Param = $Command.Parameters['EquityAccount']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have an optional ResultAccount parameter of type String' {
            $Param = $Command.Parameters['ResultAccount']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have a SkipResultEntry switch parameter' {
            $Param = $Command.Parameters['SkipResultEntry']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'
        }

        It 'Should set fiscal year status to Closed' {
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $YearFile = Join-Path $JournalPath $FiscalYear 'year.txt'
            $Content = Get-Content $YearFile -Raw
            $Content | Should -Match 'Status: Closed'
        }

        It 'Should preserve StartDate and EndDate in year.txt' {
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $YearFile = Join-Path $JournalPath $FiscalYear 'year.txt'
            $Content = Get-Content $YearFile -Raw
            $Content | Should -Match 'StartDate: 2024-01-01'
            $Content | Should -Match 'EndDate: 2024-12-31'
        }

        It 'Should prevent Add-LedgerEntry on a closed fiscal year' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Rows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )

            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-06-01' -Description 'Ska inte gå' -Rows $Rows } |
                Should -Throw '*Closed*'
        }

        It 'Should throw if fiscal year does not exist' {
            { Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear '2099-01_2099-12' } | Should -Throw
        }

        It 'Should throw if fiscal year is already closed' {
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            { Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear } | Should -Throw '*already closed*'
        }

        It 'Should be reflected in Get-LedgerFiscalYear output' {
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Result = Get-LedgerFiscalYear -JournalPath $JournalPath
            $Result.Status | Should -Be 'Closed'
        }

        It 'Should not create a verification when there is no result to book' {
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $VerFiles = Get-ChildItem -Path (Join-Path $JournalPath $FiscalYear) -Filter 'ver*.txt' -File -ErrorAction SilentlyContinue
            @($VerFiles).Count | Should -Be 0
        }
    }

    Context 'Result booking' {
        BeforeAll {
            function New-ProfitJournal {
                param ([string]$Path, [string]$CompanyType, [string]$EquityAccount)
                if ($CompanyType) {
                    New-LedgerJournal -Path $Path -Name 'Bokslut AB' -CompanyType $CompanyType
                }
                else {
                    New-LedgerJournal -Path $Path -Name 'Bokslut AB'
                }
                New-LedgerFiscalYear -JournalPath $Path -StartDate '2024-01-01' -EndDate '2024-12-31'
                Add-LedgerAccount -JournalPath $Path -AccountNumber '1910' -AccountName 'Kassa'
                Add-LedgerAccount -JournalPath $Path -AccountNumber '3010' -AccountName 'Försäljning'
                Add-LedgerAccount -JournalPath $Path -AccountNumber '8999' -AccountName 'Årets resultat'
                if ($EquityAccount) {
                    Add-LedgerAccount -JournalPath $Path -AccountNumber $EquityAccount -AccountName 'Årets resultat, eget kapital'
                }
                # A 5000 profit: debit 1910, credit 3010.
                Add-LedgerEntry -JournalPath $Path -FiscalYear '2024-01_2024-12' -Date '2024-06-01' `
                    -Description 'Försäljning' -Rows @(
                    @{ Account = '1910'; Amount = 5000 }
                    @{ Account = '3010'; Amount = -5000 }
                )
            }
        }

        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            $FiscalYear = '2024-01_2024-12'
        }

        It 'Should book the net result to the CompanyType default equity account (AB -> 2099)' {
            New-ProfitJournal -Path $JournalPath -CompanyType 'AB' -EquityAccount '2099'

            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            ($Balance | Where-Object AccountNumber -eq '2099').Balance | Should -Be -5000
            ($Balance | Where-Object AccountNumber -eq '8999').Balance | Should -Be 5000
        }

        It 'Should net the profit and loss accounts to zero after booking' {
            New-ProfitJournal -Path $JournalPath -CompanyType 'AB' -EquityAccount '2099'

            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            $PLSum = ($Balance | Where-Object { $_.AccountNumber -match '^[3-8]' } | Measure-Object -Property Balance -Sum).Sum
            $PLSum | Should -Be 0
        }

        It 'Should date the result verification at the year end date' {
            New-ProfitJournal -Path $JournalPath -CompanyType 'AB' -EquityAccount '2099'

            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $ResultEntry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear |
                Where-Object { $_.Description -eq 'Årets resultat (bokslut)' }
            $ResultEntry | Should -Not -BeNullOrEmpty
            $ResultEntry.Date | Should -Be '2024-12-31'
        }

        It 'Should transfer the result to 2019 for an EF journal' {
            New-ProfitJournal -Path $JournalPath -CompanyType 'EF' -EquityAccount '2019'

            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear

            $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            ($Balance | Where-Object AccountNumber -eq '2019').Balance | Should -Be -5000
        }

        It 'Should honour an explicit -EquityAccount override' {
            New-ProfitJournal -Path $JournalPath -CompanyType 'AB' -EquityAccount '2091'

            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear -EquityAccount '2091'

            $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            ($Balance | Where-Object AccountNumber -eq '2091').Balance | Should -Be -5000
        }

        It 'Should not book a result when -SkipResultEntry is used' {
            New-ProfitJournal -Path $JournalPath -CompanyType 'AB' -EquityAccount '2099'

            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear -SkipResultEntry

            $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            ($Balance | Where-Object AccountNumber -eq '8999') | Should -BeNullOrEmpty
            (Get-LedgerFiscalYear -JournalPath $JournalPath).Status | Should -Be 'Closed'
        }

        It 'Should throw when there is a result but no CompanyType and no -EquityAccount' {
            New-ProfitJournal -Path $JournalPath

            { Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear } | Should -Throw '*CompanyType*'
        }

        It 'Should not book or close the year with -WhatIf' {
            New-ProfitJournal -Path $JournalPath -CompanyType 'AB' -EquityAccount '2099'

            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear -WhatIf

            (Get-LedgerFiscalYear -JournalPath $JournalPath).Status | Should -Be 'Open'
            $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            ($Balance | Where-Object AccountNumber -eq '8999') | Should -BeNullOrEmpty
        }
    }
}
