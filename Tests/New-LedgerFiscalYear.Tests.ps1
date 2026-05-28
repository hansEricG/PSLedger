BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'New-LedgerFiscalYear' {
    BeforeAll {
        $CommandName = 'New-LedgerFiscalYear'
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

        It 'Should have a mandatory StartDate parameter of type DateTime' {
            $Param = $Command.Parameters['StartDate']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'DateTime'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory EndDate parameter of type DateTime' {
            $Param = $Command.Parameters['EndDate']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'DateTime'
            $Param.Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
        }

        It 'Should create a subdirectory for the fiscal year' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'

            $YearDir = Join-Path $JournalPath '2024-01_2024-12'
            Test-Path $YearDir -PathType Container | Should -BeTrue
        }

        It 'Should create a year.txt file in the fiscal year directory' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'

            $YearFile = Join-Path $JournalPath '2024-01_2024-12' 'year.txt'
            Test-Path $YearFile | Should -BeTrue
        }

        It 'Should write StartDate and EndDate to year.txt' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Content = Get-Content (Join-Path $JournalPath '2024-01_2024-12' 'year.txt') -Raw
            $Content | Should -Match '2024-01-01'
            $Content | Should -Match '2024-12-31'
        }

        It 'Should write Status as Open' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'

            $Content = Get-Content (Join-Path $JournalPath '2024-01_2024-12' 'year.txt') -Raw
            $Content | Should -Match 'Status:\s*Open'
        }

        It 'Should support broken fiscal years' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-07-01' -EndDate '2025-06-30'

            $YearDir = Join-Path $JournalPath '2024-07_2025-06'
            Test-Path $YearDir -PathType Container | Should -BeTrue
        }

        It 'Should throw if the fiscal year directory already exists' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'

            { New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31' } | Should -Throw
        }

        It 'Should throw if EndDate is before StartDate' {
            { New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-12-31' -EndDate '2024-01-01' } | Should -Throw
        }

        It 'Should throw if journal path does not exist' {
            { New-LedgerFiscalYear -JournalPath 'C:\nonexistent' -StartDate '2024-01-01' -EndDate '2024-12-31' } | Should -Throw
        }
    }
}
