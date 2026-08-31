BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
}

Describe 'Atomic file writes and rollback' {
    Context 'Persistent writes leave no temporary files' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            New-LedgerJournal -Path $JournalPath -Name 'Faktura AB' -CompanyType AB
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1510' -AccountName 'Kundfordringar'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2610' -AccountName 'Utgående moms'
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
        }

        It 'Saving an invoice writes the file and leaves no .tmp_* residue' {
            $rows = @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Tjänst' -Rows $rows

            $invoiceDir = Join-Path $JournalPath 'invoices'
            $invoiceFile = Join-Path $invoiceDir 'inv0001.txt'
            Test-Path $invoiceFile | Should -BeTrue

            $temps = @(Get-ChildItem -Path $invoiceDir -Force -Filter '.tmp_*' -ErrorAction SilentlyContinue)
            $temps.Count | Should -Be 0
        }
    }

    Context 'Add-LedgerCreditInvoice rolls back a partial booking' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            New-LedgerJournal -Path $JournalPath -Name 'Faktura AB' -CompanyType AB
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1510' -AccountName 'Kundfordringar'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2610' -AccountName 'Utgående moms'
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
            $rows = @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Tjänst' -Rows $rows
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
        }

        It 'Leaves the original invoice, verifications and invoice files unchanged when a save fails' {
            # Force the credit-note save to fail after the reversing verification
            # has been booked, so the catch/rollback path runs.
            Mock -ModuleName PSLedger Save-LedgerInvoiceFile { throw 'simulated write failure' }

            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-03-20' } |
                Should -Throw '*simulated write failure*'

            # Original invoice is still the posted receivable, not credited.
            $original = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1
            $original.Status | Should -Be 'Booked'

            # No credit note file was left behind.
            Test-Path (Join-Path $JournalPath 'invoices' 'inv0002.txt') | Should -BeFalse

            # The reversing verification was rolled back: only the original posting remains.
            $entries = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12')
            $entries.Count | Should -Be 1
            Test-Path (Join-Path $JournalPath '2024-01_2024-12' 'ver0002.txt') | Should -BeFalse
        }
    }
}

Describe 'Warnings for malformed data files' {
    Context 'accounts.txt' {
        It 'Warns about a malformed account row but still returns the valid accounts' {
            $JournalPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            New-LedgerJournal -Path $JournalPath -Name 'Faktura AB' -CompanyType AB
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'

            # Corrupt the chart with a line that does not match '<number><TAB><name>'.
            $accountsFile = Join-Path $JournalPath 'accounts.txt'
            Add-Content -Path $accountsFile -Value 'this-is-not-a-valid-row' -Encoding UTF8

            $warnings = @()
            $accounts = Get-LedgerAccount -JournalPath $JournalPath -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings.Count | Should -BeGreaterThan 0
            ($warnings -join ' ') | Should -BeLike '*malformed account row*'
            @($accounts).Count | Should -Be 1
            $accounts.AccountNumber | Should -Be '1910'
        }
    }

    Context 'ib.txt' {
        It 'Warns about a malformed opening balance row but still reads the valid ones' {
            $JournalPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            New-LedgerJournal -Path $JournalPath -Name 'Faktura AB' -CompanyType AB
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2081' -AccountName 'Aktiekapital'

            $ibFile = Join-Path $JournalPath '2024-01_2024-12' 'ib.txt'
            Set-Content -Path $ibFile -Encoding UTF8 -Value @(
                "1910`t15000.00"
                'garbage line without a tab'
                "2081`t-15000.00"
            )

            $warnings = @()
            $balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings.Count | Should -BeGreaterThan 0
            ($warnings -join ' ') | Should -BeLike '*malformed opening balance row*'
            ($balance | Where-Object AccountNumber -eq '1910').Balance | Should -Be 15000
        }
    }
}
