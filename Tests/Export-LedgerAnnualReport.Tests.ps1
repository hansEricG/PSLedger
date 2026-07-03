BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
}

Describe 'Export-LedgerAnnualReport' {
    Context 'Function metadata' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command Export-LedgerAnnualReport
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should have a mandatory Path parameter' {
            $param = (Get-Command Export-LedgerAnnualReport).Parameters['Path']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        }

        It 'Should have a Format parameter validating Text and Markdown' {
            $param = (Get-Command Export-LedgerAnnualReport).Parameters['Format']
            $validate = $param.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] })
            $validate.ValidValues | Should -Contain 'Text'
            $validate.ValidValues | Should -Contain 'Markdown'
        }

        It 'Should have a Force switch parameter' {
            $param = (Get-Command Export-LedgerAnnualReport).Parameters['Force']
            $param.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'export.ledger'
            New-LedgerJournal -Path $jp -Name 'Export AB' -OrgNumber '556677-8899' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2023-01-01' -EndDate '2023-12-31'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '4010' -AccountName 'Inköp'

            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-06-01' `
                -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 80000 }
                @{ Account = '3010'; Amount = -80000 }
            )
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-06-01' `
                -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 100000 }
                @{ Account = '3010'; Amount = -100000 }
            )
        }

        It 'Should create a text report file' {
            $out = Join-Path $TestDrive 'report.txt'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12' -Path $out
            Test-Path $out | Should -BeTrue
        }

        It 'Should include the header with company name and org number' {
            $out = Join-Path $TestDrive 'report.txt'
            $content = Get-Content $out -Raw
            $content | Should -Match 'Export AB'
            $content | Should -Match '556677-8899'
            $content | Should -Match '2024-01-01 - 2024-12-31'
        }

        It 'Should include both statement sections' {
            $out = Join-Path $TestDrive 'report.txt'
            $content = Get-Content $out -Raw
            $content | Should -Match 'Resultaträkning'
            $content | Should -Match 'Balansräkning'
        }

        It 'Should include the net sales line and comparison column' {
            $out = Join-Path $TestDrive 'report.txt'
            $content = Get-Content $out -Raw
            $content | Should -Match 'Nettoomsättning'
            $content | Should -Match '2023'
            $content | Should -Match '2024'
        }

        It 'Should write a Markdown report with tables' {
            $out = Join-Path $TestDrive 'report.md'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12' -Path $out -Format Markdown
            $content = Get-Content $out -Raw
            $content | Should -Match '# Årsredovisning'
            $content | Should -Match '## Resultaträkning'
            $content | Should -Match '\| Nettoomsättning \|'
        }

        It 'Should omit the comparison column with -NoComparison' {
            $out = Join-Path $TestDrive 'nocomp.md'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12' -Path $out -Format Markdown -NoComparison
            $content = Get-Content $out -Raw
            $content | Should -Match '\| Post \| 2024 \|'
            $content | Should -Not -Match '\| Post \| 2024 \| 2023 \|'
        }

        It 'Should throw if the destination exists without -Force' {
            $out = Join-Path $TestDrive 'existing.txt'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12' -Path $out
            { Export-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12' -Path $out } |
                Should -Throw '*already exists*'
        }

        It 'Should overwrite an existing file with -Force' {
            $out = Join-Path $TestDrive 'force.txt'
            Export-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12' -Path $out
            { Export-LedgerAnnualReport -JournalPath $jp -FiscalYear '2024-01_2024-12' -Path $out -Force } |
                Should -Not -Throw
        }
    }
}
