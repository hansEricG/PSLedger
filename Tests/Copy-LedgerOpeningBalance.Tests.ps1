BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Copy-LedgerOpeningBalance' {
    BeforeAll {
        $CommandName = 'Copy-LedgerOpeningBalance'
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

        It 'Should have an optional FromFiscalYear parameter of type String that binds from Name' {
            $Param = $Command.Parameters['FromFiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
            $Param.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $Param.Aliases | Should -Contain 'Name'
        }

        It 'Should have a mandatory ToFiscalYear parameter of type String' {
            $Param = $Command.Parameters['ToFiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Mini'

            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-01-01' -EndDate '2025-12-31'

            # Create entries in 2024
            $Rows1 = @(
                @{ Account = '1910'; Amount = 50000 }
                @{ Account = '3010'; Amount = -50000 }
            )
            $Rows2 = @(
                @{ Account = '4010'; Amount = 20000 }
                @{ Account = '2440'; Amount = -20000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -Date '2024-06-01' -Description 'Försäljning' -Rows $Rows1
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -Date '2024-06-15' -Description 'Inköp' -Rows $Rows2
        }

        It 'Should create ib.txt in target fiscal year' {
            Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12'

            $IbFile = Join-Path $JournalPath '2025-01_2025-12' 'ib.txt'
            Test-Path $IbFile | Should -BeTrue
        }

        It 'Should not create a verification for the opening balance' {
            Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12'

            $Entries = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2025-01_2025-12')
            $Entries.Count | Should -Be 0
        }

        It 'Should carry balances into the target OpeningBalance' {
            Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12'

            $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2025-01_2025-12'
            $Kassa = $Balance | Where-Object { $_.AccountNumber -eq '1910' }
            $Kassa.OpeningBalance | Should -Be 50000

            $Lev = $Balance | Where-Object { $_.AccountNumber -eq '2440' }
            $Lev.OpeningBalance | Should -Be -20000
        }

        It 'Should only include balance sheet accounts (1xxx and 2xxx)' {
            Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12'

            $IbFile = Join-Path $JournalPath '2025-01_2025-12' 'ib.txt'
            foreach ($Line in (Get-Content $IbFile)) {
                ($Line -split "`t")[0] | Should -Match '^[12]'
            }
        }

        It 'Should produce a balanced opening balance (sum of amounts = 0)' {
            Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12'

            $IbFile = Join-Path $JournalPath '2025-01_2025-12' 'ib.txt'
            $Sum = [decimal]0
            foreach ($Line in (Get-Content $IbFile)) {
                $Sum += [decimal](($Line -split "`t")[1])
            }
            $Sum | Should -Be 0
        }

        It 'Should throw if target already has an opening balance' {
            Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12'

            { Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12' } |
                Should -Throw '*already has an opening balance*'
        }

        It 'Should throw if source fiscal year does not exist' {
            { Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2000-01_2000-12' -ToFiscalYear '2025-01_2025-12' } |
                Should -Throw '*not found*'
        }

        It 'Should throw if target fiscal year does not exist' {
            { Copy-LedgerOpeningBalance -JournalPath $JournalPath -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2099-01_2099-12' } |
                Should -Throw '*not found*'
        }
    }
}
