BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerEntry' {
    BeforeAll {
        $CommandName = 'Add-LedgerEntry'
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

        It 'Should have a mandatory FiscalYear parameter of type String' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory Date parameter of type DateTime' {
            $Param = $Command.Parameters['Date']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'DateTime'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory Description parameter of type String' {
            $Param = $Command.Parameters['Description']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory Rows parameter' {
            $Param = $Command.Parameters['Rows']
            $Param | Should -Not -BeNullOrEmpty
            $Param.Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'
            $Rows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )
        }

        It 'Should create a verification file ver0001.txt' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Försäljning kontant' -Rows $Rows

            $VerFile = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            Test-Path $VerFile | Should -BeTrue
        }

        It 'Should auto-increment verification number' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Ver 1' -Rows $Rows
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-16' -Description 'Ver 2' -Rows $Rows

            $VerFile = Join-Path $JournalPath $FiscalYear 'ver0002.txt'
            Test-Path $VerFile | Should -BeTrue
        }

        It 'Should write date to the verification file' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Test' -Rows $Rows

            $Content = Get-Content (Join-Path $JournalPath $FiscalYear 'ver0001.txt') -Raw
            $Content | Should -Match '2024-01-15'
        }

        It 'Should write description to the verification file' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Försäljning kontant' -Rows $Rows

            $Content = Get-Content (Join-Path $JournalPath $FiscalYear 'ver0001.txt') -Raw
            $Content | Should -Match 'Försäljning kontant'
        }

        It 'Should write account rows to the verification file' {
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Test' -Rows $Rows

            $Content = Get-Content (Join-Path $JournalPath $FiscalYear 'ver0001.txt') -Raw
            $Content | Should -Match '1910'
            $Content | Should -Match '1000'
            $Content | Should -Match '3010'
            $Content | Should -Match '-1000'
        }

        It 'Should throw if rows do not balance (sum != 0)' {
            $BadRows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -500 }
            )

            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Obalanserad' -Rows $BadRows } | Should -Throw
        }

        It 'Should throw if fiscal year directory does not exist' {
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2099-01_2099-12' -Date '2024-01-15' -Description 'Test' -Rows $Rows } | Should -Throw
        }

        It 'Should throw if an account in Rows does not exist in chart of accounts' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'

            $BadRows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '9999'; Amount = -1000 }
            )

            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Okänt konto' -Rows $BadRows } |
                Should -Throw '*9999*'
        }

        It 'Should succeed when all accounts exist in chart of accounts' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'

            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Alla konton finns' -Rows $Rows } |
                Should -Not -Throw
        }

        It 'Should skip account validation when no accounts.txt exists' {
            # No accounts added — accounts.txt does not exist
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-15' -Description 'Utan kontoplan' -Rows $Rows } |
                Should -Not -Throw
        }

        It 'Should throw if date is before fiscal year start' {
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2023-12-31' -Description 'Före start' -Rows $Rows } |
                Should -Throw '*outside fiscal year*'
        }

        It 'Should throw if date is after fiscal year end' {
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2025-01-01' -Description 'Efter slut' -Rows $Rows } |
                Should -Throw '*outside fiscal year*'
        }

        It 'Should accept date on fiscal year boundary dates' {
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-01-01' -Description 'Första dagen' -Rows $Rows } |
                Should -Not -Throw
            { Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-12-31' -Description 'Sista dagen' -Rows $Rows } |
                Should -Not -Throw
        }
    }
}
