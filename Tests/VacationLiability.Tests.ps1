BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force

    function New-VacationTestJournal {
        param([string]$Root)
        $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $path -Name 'Lön AB' -CompanyType AB | Out-Null
        Import-LedgerChart -JournalPath $path -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $path -StartDate '2024-01-01' -EndDate '2024-12-31'
        return $path
    }

    function Get-Balance {
        param($JournalPath, $Account)
        $row = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' |
            Where-Object { $_.AccountNumber -eq $Account }
        if ($row) { [decimal]$row.Balance } else { [decimal]0 }
    }
}

Describe 'Add-LedgerVacationLiability' {
    BeforeAll {
        $Command = Get-Command -Name 'Add-LedgerVacationLiability'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }
        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
        It 'Should have a mandatory Date parameter' {
            $Command.Parameters['Date'].Attributes.Mandatory | Should -Contain $true
        }
        It 'Should support ShouldProcess' {
            $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-VacationTestJournal -Root $TestDrive
        }

        It 'Should book an increase as debit 7290 and credit 2920' {
            $result = Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-12-31' -Amount 45000
            $result.Change | Should -Be 45000
            Get-Balance $JournalPath '7290' | Should -Be 45000
            Get-Balance $JournalPath '2920' | Should -Be -45000
        }

        It 'Should reverse the signs for a decrease' {
            Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-06-30' -Amount 50000 | Out-Null
            Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-12-31' -Amount -20000 | Out-Null
            Get-Balance $JournalPath '2920' | Should -Be -30000
            Get-Balance $JournalPath '7290' | Should -Be 30000
        }

        It 'Should book employer contributions with -IncludeEmployerContributions' {
            $result = Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-12-31' -Amount 45000 -IncludeEmployerContributions
            $result.EmployerContribution | Should -Be 14139
            Get-Balance $JournalPath '7510' | Should -Be 14139
            Get-Balance $JournalPath '2940' | Should -Be -14139
        }

        It 'Should use a custom employer contribution rate' {
            $result = Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-12-31' -Amount 10000 -IncludeEmployerContributions -EmployerContributionRate 0.10
            $result.EmployerContribution | Should -Be 1000
        }

        It 'Should adjust to a target balance from the current balance' {
            Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-06-30' -Amount 30000 | Out-Null
            $result = Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-12-31' -TargetBalance 50000
            $result.Change | Should -Be 20000
            Get-Balance $JournalPath '2920' | Should -Be -50000
        }

        It 'Should produce a balanced verification' {
            $result = Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-12-31' -Amount 45000 -IncludeEmployerContributions
            $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -VerificationNumber $result.VerificationNumber
            ($entry.Rows | Measure-Object -Property Amount -Sum).Sum | Should -Be 0
        }

        It 'Should throw when the change is zero' {
            { Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-12-31' -Amount 0 } |
                Should -Throw '*Nothing to book*'
        }

        It 'Should throw when no fiscal year covers the date' {
            { Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2030-12-31' -Amount 1000 } |
                Should -Throw '*No fiscal year*'
        }

        It 'Should not write anything with -WhatIf' {
            Add-LedgerVacationLiability -JournalPath $JournalPath -Date '2024-12-31' -Amount 45000 -WhatIf
            Get-Balance $JournalPath '2920' | Should -Be 0
        }
    }
}
