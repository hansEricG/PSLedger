BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
}

Describe 'Add-LedgerAccrual' {
    Context 'Function metadata' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command Add-LedgerAccrual
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter' {
            $param = (Get-Command Add-LedgerAccrual).Parameters['JournalPath']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeFalse
        }

        It 'Should have mandatory Amount parameter of type decimal' {
            $param = (Get-Command Add-LedgerAccrual).Parameters['Amount']
            $param.ParameterType | Should -Be ([decimal])
        }

        It 'Should have mandatory ReversalFiscalYear parameter' {
            $param = (Get-Command Add-LedgerAccrual).Parameters['ReversalFiscalYear']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'accrual.ledger'
            New-LedgerJournal -Path $jp -Name 'Accrual AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2025-01-01' -EndDate '2025-12-31'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1710' -AccountName 'Förutbetalda kostnader'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '5010' -AccountName 'Lokalkostnader'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '6310' -AccountName 'Försäkringar'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1730' -AccountName 'Förutbetalda försäkringspremier'
        }

        It 'Should create accrual and reversal verifications' {
            $result = Add-LedgerAccrual -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Description 'Förutbetald hyra jan' `
                -ExpenseAccount '5010' -AccrualAccount '1710' -Amount 8000 `
                -ReversalFiscalYear '2025-01_2025-12' -ReversalDate '2025-01-01'

            $result.Amount | Should -Be 8000
            $result.ExpenseAccount | Should -Be '5010'
            $result.AccrualAccount | Should -Be '1710'
        }

        It 'Should debit accrual account and credit expense in accrual entry' {
            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $accrualEntry = $entries | Where-Object { $_.Description -match 'periodisering' }
            $accrualEntry | Should -Not -BeNullOrEmpty
            $accrualEntry.Rows[0].Account | Should -Be '1710'
            $accrualEntry.Rows[0].Amount | Should -Be 8000
            $accrualEntry.Rows[1].Account | Should -Be '5010'
            $accrualEntry.Rows[1].Amount | Should -Be -8000
        }

        It 'Should debit expense and credit accrual account in reversal entry' {
            $entries = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2025-01_2025-12')
            $reversalEntry = $entries | Where-Object { $_.Description -match 'återföring' }
            $reversalEntry | Should -Not -BeNullOrEmpty
            $reversalEntry.Rows[0].Account | Should -Be '5010'
            $reversalEntry.Rows[0].Amount | Should -Be 8000
            $reversalEntry.Rows[1].Account | Should -Be '1710'
            $reversalEntry.Rows[1].Amount | Should -Be -8000
        }

        It 'Should include description markers for cross-reference' {
            $entries2024 = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12')
            $entries2025 = @(Get-LedgerEntry -JournalPath $jp -FiscalYear '2025-01_2025-12')
            $entries2024[0].Description | Should -Match 'periodisering'
            $entries2025[0].Description | Should -Match 'återföring'
        }

        It 'Should throw if amount is zero or negative' {
            { Add-LedgerAccrual -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Description 'Bad' `
                -ExpenseAccount '5010' -AccrualAccount '1710' -Amount 0 `
                -ReversalFiscalYear '2025-01_2025-12' -ReversalDate '2025-01-01' } |
                Should -Throw '*must be positive*'
        }

        It 'Should throw if reversal fiscal year does not exist' {
            { Add-LedgerAccrual -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Description 'Bad' `
                -ExpenseAccount '5010' -AccrualAccount '1710' -Amount 1000 `
                -ReversalFiscalYear '2026-01_2026-12' -ReversalDate '2026-01-01' } |
                Should -Throw '*does not exist*'
        }

        It 'Should work with insurance scenario' {
            $result = Add-LedgerAccrual -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -Date '2024-12-31' -Description 'Försäkring Q1' `
                -ExpenseAccount '6310' -AccrualAccount '1730' -Amount 12000 `
                -ReversalFiscalYear '2025-01_2025-12' -ReversalDate '2025-01-01'

            $result.Amount | Should -Be 12000
            $result.Description | Should -Be 'Försäkring Q1'
        }
    }
}
