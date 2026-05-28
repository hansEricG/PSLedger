BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
}

Describe 'Recurring Entries' {
    BeforeAll {
        $jp = Join-Path $TestDrive 'recurring.ledger'
        New-LedgerJournal -Path $jp -Name 'Recurring AB'
        New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
        Add-LedgerAccount -JournalPath $jp -AccountNumber '5010' -AccountName 'Lokalkostnader'
        Add-LedgerAccount -JournalPath $jp -AccountNumber '2440' -AccountName 'Leverantörsskulder'
        Add-LedgerAccount -JournalPath $jp -AccountNumber '6210' -AccountName 'Telekommunikation'
        Add-LedgerAccount -JournalPath $jp -AccountNumber '2640' -AccountName 'Ingående moms'

        # Create base templates for cross-Context testing
        New-LedgerRecurringEntry -JournalPath $jp -Name 'Hyra' `
            -Description 'Hyra kontor' -Schedule 'monthly' -DayOfMonth 1 `
            -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
            @{ Account = '5010'; Amount = 8000 }
            @{ Account = '2440'; Amount = -8000 }
        )
    }

    Context 'New-LedgerRecurringEntry' {
        It 'Should have CmdletBinding' {
            (Get-Command New-LedgerRecurringEntry).CmdletBinding | Should -BeTrue
        }

        It 'Should create a recurring entry template' {
            New-LedgerRecurringEntry -JournalPath $jp -Name 'El' `
                -Description 'Elräkning' -Schedule 'monthly' -DayOfMonth 25 `
                -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
                @{ Account = '5010'; Amount = 2000 }
                @{ Account = '2440'; Amount = -2000 }
            )

            $filePath = Join-Path $jp 'recurring' 'El.txt'
            Test-Path $filePath | Should -BeTrue
        }

        It 'Should store all metadata in the template file' {
            $content = Get-Content (Join-Path $jp 'recurring' 'El.txt') -Encoding UTF8
            ($content -join "`n") | Should -Match 'Name:'
            ($content -join "`n") | Should -Match 'Schedule:'
            ($content -join "`n") | Should -Match 'DayOfMonth:'
        }

        It 'Should reject unbalanced rows' {
            { New-LedgerRecurringEntry -JournalPath $jp -Name 'Bad' `
                -Description 'Bad' -Schedule 'monthly' -DayOfMonth 1 `
                -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
                @{ Account = '5010'; Amount = 8000 }
                @{ Account = '2440'; Amount = -5000 }
            ) } | Should -Throw '*do not balance*'
        }

        It 'Should reject duplicate names' {
            { New-LedgerRecurringEntry -JournalPath $jp -Name 'Hyra' `
                -Description 'Dup' -Schedule 'monthly' -DayOfMonth 1 `
                -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
                @{ Account = '5010'; Amount = 1000 }
                @{ Account = '2440'; Amount = -1000 }
            ) } | Should -Throw '*already exists*'
        }
    }

    Context 'Get-LedgerRecurringEntry' {
        It 'Should have CmdletBinding' {
            (Get-Command Get-LedgerRecurringEntry).CmdletBinding | Should -BeTrue
        }

        It 'Should list all templates' {
            New-LedgerRecurringEntry -JournalPath $jp -Name 'Telefon' `
                -Description 'Telefonabonnemang' -Schedule 'monthly' -DayOfMonth 15 `
                -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
                @{ Account = '6210'; Amount = 500 }
                @{ Account = '2640'; Amount = 125 }
                @{ Account = '2440'; Amount = -625 }
            )

            $templates = @(Get-LedgerRecurringEntry -JournalPath $jp)
            $templates.Count | Should -BeGreaterOrEqual 2
        }

        It 'Should filter by name' {
            $tmpl = Get-LedgerRecurringEntry -JournalPath $jp -Name 'Hyra'
            $tmpl.Name | Should -Be 'Hyra'
            $tmpl.DayOfMonth | Should -Be 1
            $tmpl.Rows.Count | Should -Be 2
        }

        It 'Should return null for non-existent name' {
            $tmpl = Get-LedgerRecurringEntry -JournalPath $jp -Name 'NonExist'
            $tmpl | Should -BeNullOrEmpty
        }
    }

    Context 'Remove-LedgerRecurringEntry' {
        It 'Should have CmdletBinding' {
            (Get-Command Remove-LedgerRecurringEntry).CmdletBinding | Should -BeTrue
        }

        It 'Should remove a template' {
            New-LedgerRecurringEntry -JournalPath $jp -Name 'TempRemove' `
                -Description 'Remove me' -Schedule 'monthly' -DayOfMonth 5 `
                -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
                @{ Account = '5010'; Amount = 100 }
                @{ Account = '2440'; Amount = -100 }
            )

            Remove-LedgerRecurringEntry -JournalPath $jp -Name 'TempRemove'
            $tmpl = Get-LedgerRecurringEntry -JournalPath $jp -Name 'TempRemove'
            $tmpl | Should -BeNullOrEmpty
        }

        It 'Should throw if template does not exist' {
            { Remove-LedgerRecurringEntry -JournalPath $jp -Name 'NonExist' } |
                Should -Throw '*not found*'
        }
    }

    Context 'Invoke-LedgerRecurringEntry' {
        BeforeAll {
            # Use a fresh journal for invoke tests
            $script:invokeJp = Join-Path $TestDrive 'invoke.ledger'
            New-LedgerJournal -Path $script:invokeJp -Name 'Invoke AB'
            New-LedgerFiscalYear -JournalPath $script:invokeJp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $script:invokeJp -AccountNumber '5010' -AccountName 'Lokalkostnader'
            Add-LedgerAccount -JournalPath $script:invokeJp -AccountNumber '2440' -AccountName 'Leverantörsskulder'

            New-LedgerRecurringEntry -JournalPath $script:invokeJp -Name 'Hyra' `
                -Description 'Kontorshyra' -Schedule 'monthly' -DayOfMonth 1 `
                -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
                @{ Account = '5010'; Amount = 10000 }
                @{ Account = '2440'; Amount = -10000 }
            )
        }

        It 'Should have CmdletBinding' {
            (Get-Command Invoke-LedgerRecurringEntry).CmdletBinding | Should -BeTrue
        }

        It 'Should generate entries through a specified date' {
            $result = Invoke-LedgerRecurringEntry -JournalPath $script:invokeJp -Through '2024-03-15'
            $result.Generated | Should -Be 3

            $entries = @(Get-LedgerEntry -JournalPath $script:invokeJp -FiscalYear '2024-01_2024-12')
            $entries.Count | Should -Be 3
        }

        It 'Should be idempotent — second run generates nothing' {
            $result = Invoke-LedgerRecurringEntry -JournalPath $script:invokeJp -Through '2024-03-15'
            $result.Generated | Should -Be 0

            $entries = @(Get-LedgerEntry -JournalPath $script:invokeJp -FiscalYear '2024-01_2024-12')
            $entries.Count | Should -Be 3
        }

        It 'Should generate additional entries for new months' {
            $result = Invoke-LedgerRecurringEntry -JournalPath $script:invokeJp -Through '2024-06-30'
            $result.Generated | Should -Be 3

            $entries = @(Get-LedgerEntry -JournalPath $script:invokeJp -FiscalYear '2024-01_2024-12')
            $entries.Count | Should -Be 6
        }

        It 'Should update LastGenerated in the template' {
            $tmpl = Get-LedgerRecurringEntry -JournalPath $script:invokeJp -Name 'Hyra'
            $tmpl.LastGenerated | Should -Be ([datetime]'2024-06-01')
        }

        It 'Should respect EndDate and not generate beyond it' {
            $result = Invoke-LedgerRecurringEntry -JournalPath $script:invokeJp -Through '2025-06-30'
            # Should generate Jul-Dec (6 more months)
            $result.Generated | Should -Be 6

            $entries = @(Get-LedgerEntry -JournalPath $script:invokeJp -FiscalYear '2024-01_2024-12')
            $entries.Count | Should -Be 12
        }

        It 'Should filter by name' {
            $result = Invoke-LedgerRecurringEntry -JournalPath $script:invokeJp -Name 'Hyra' -Through '2025-12-31'
            $result.Generated | Should -Be 0
        }
    }
}
