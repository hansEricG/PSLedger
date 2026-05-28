BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerFiscalYear' {
    BeforeAll {
        $CommandName = 'Get-LedgerFiscalYear'
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
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
        }

        It 'Should return all fiscal years in the journal' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2023-01-01' -EndDate '2023-12-31'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Result = Get-LedgerFiscalYear -JournalPath $JournalPath

            $Result.Count | Should -Be 2
        }

        It 'Should return objects with Name, StartDate, EndDate, and Status' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Result = Get-LedgerFiscalYear -JournalPath $JournalPath

            $Result.Name | Should -Be '2024-01_2024-12'
            $Result.StartDate | Should -Be '2024-01-01'
            $Result.EndDate | Should -Be '2024-12-31'
            $Result.Status | Should -Be 'Open'
        }

        It 'Should support broken fiscal years' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-07-01' -EndDate '2025-06-30'

            $Result = Get-LedgerFiscalYear -JournalPath $JournalPath

            $Result.Name | Should -Be '2024-07_2025-06'
            $Result.StartDate | Should -Be '2024-07-01'
            $Result.EndDate | Should -Be '2025-06-30'
        }

        It 'Should sort results by StartDate' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-01-01' -EndDate '2025-12-31'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2023-01-01' -EndDate '2023-12-31'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Result = Get-LedgerFiscalYear -JournalPath $JournalPath

            $Result[0].Name | Should -Be '2023-01_2023-12'
            $Result[1].Name | Should -Be '2024-01_2024-12'
            $Result[2].Name | Should -Be '2025-01_2025-12'
        }

        It 'Should return empty if no fiscal years exist' {
            $Result = Get-LedgerFiscalYear -JournalPath $JournalPath

            $Result | Should -BeNullOrEmpty
        }

        It 'Should throw if journal path does not exist' {
            { Get-LedgerFiscalYear -JournalPath (Join-Path $TestDrive 'nonexistent.ledger') } | Should -Throw
        }
    }
}
