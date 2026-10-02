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

            # The rolled-back verification is also removed from the integrity chain.
            (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear '2024-01_2024-12').Status | Should -Be 'Valid'
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

Describe 'Single-line text fields' {
    BeforeEach {
        $JournalPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
        New-LedgerJournal -Path $JournalPath -Name 'Text AB' -CompanyType AB
        New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1930' -AccountName 'Företagskonto'
        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '6110' -AccountName 'Kontorsmateriel'
        $multi = "Rad ett`r`nrad`ttvå`n"
    }

    It 'Normalises tabs and line breaks in register text fields' {
        Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name $multi -Email "a@b.se`t"
        Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '20' -Name $multi
        Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name $multi
        Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name $multi
        Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber '10' -Name $multi
        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '6570' -AccountName $multi

        foreach ($file in 'customers.txt', 'suppliers.txt', 'employees.txt', 'dimensions.txt', 'objects.txt') {
            @(Get-Content (Join-Path $JournalPath $file)).Count | Should -Be 1 -Because $file
        }
        (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10').Name | Should -Be 'Rad ett rad två'
        (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10').Email | Should -Be 'a@b.se'
        (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10').PaymentTermsDays | Should -Be 30
        (Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '20').Name | Should -Be 'Rad ett rad två'
        (Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1').Name | Should -Be 'Rad ett rad två'
        (Get-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber '10').Name | Should -Be 'Rad ett rad två'
        (Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '6570').AccountName | Should -Be 'Rad ett rad två'
    }

    It 'Normalises text when a register entry is updated' {
        Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
        Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '20' -Name 'Telia AB'
        Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name 'Anna'
        Set-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name $multi
        Set-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '20' -Name $multi
        Set-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name $multi

        (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10').Name | Should -Be 'Rad ett rad två'
        (Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '20').Name | Should -Be 'Rad ett rad två'
        (Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1').Name | Should -Be 'Rad ett rad två'
    }

    It 'Normalises the verification description' {
        $rows = @(
            New-LedgerEntryRow -Debit 6110 -Amount 100
            New-LedgerEntryRow -Credit 1930 -Amount 100
        )
        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -Date '2024-02-01' -Description $multi -Rows $rows

        $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -VerificationNumber 1
        $entry.Description | Should -Be 'Rad ett rad två'
        $entry.Rows.Count | Should -Be 2
    }

    It 'Normalises document descriptions and references' {
        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1510' -AccountName 'Kundfordringar'
        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2610' -AccountName 'Utgående moms'
        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2440' -AccountName 'Leverantörsskulder'
        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2640' -AccountName 'Ingående moms'
        Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
        Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '20' -Name 'Telia AB'
        Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '1' -Name 'Anna' -TaxRate 0.3

        New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-01' -Description $multi `
            -Rows @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25; VatAccount = '2610' })
        New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '20' -Date '2024-03-05' -Description $multi `
            -SupplierReference "T-1`n2" -Rows @(@{ Account = '6110'; Amount = 400; VatRate = 0.25; VatAccount = '2640' })
        New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -PayDate '2024-03-25' -GrossSalary 30000 -Description $multi

        $invoice = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1
        $invoice.Description | Should -Be 'Rad ett rad två'
        $invoice.Rows.Count | Should -Be 1
        $supplierInvoice = Get-LedgerSupplierInvoice -JournalPath $JournalPath -InvoiceNumber 1
        $supplierInvoice.Description | Should -Be 'Rad ett rad två'
        $supplierInvoice.SupplierReference | Should -Be 'T-1 2'
        (Get-LedgerPayslip -JournalPath $JournalPath -PayslipNumber 1).Description | Should -Be 'Rad ett rad två'
    }

    It 'Normalises the journal name and metadata' {
        Set-LedgerJournal -JournalPath $JournalPath -Name $multi -Metadata @{ Address = "Gatan 1`nVåning 2" }
        $journal = Get-LedgerJournal -Path $JournalPath
        $journal.Name | Should -Be 'Rad ett rad två'
        $journal.Metadata['Address'] | Should -Be 'Gatan 1 Våning 2'
    }

    It 'Rejects identifiers with tabs or line breaks' {
        { Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber "1`n0" -Name 'X' } | Should -Throw '*CustomerNumber must not contain tabs or line breaks*'
        { Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber "2`t0" -Name 'X' } | Should -Throw '*SupplierNumber must not contain*'
        { Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber "1`r" -Name 'X' } | Should -Throw '*EmployeeNumber must not contain*'
        { Add-LedgerAccount -JournalPath $JournalPath -AccountNumber "1`t2" -AccountName 'X' } | Should -Throw '*AccountNumber must not contain*'
        Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Kostnadsställe'
        { Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber "1`n0" -Name 'X' } | Should -Throw '*ObjectNumber must not contain*'
    }
}

Describe 'Atomic register writes' {
    BeforeEach {
        $JournalPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
        New-LedgerJournal -Path $JournalPath -Name 'Register AB' -CompanyType AB
    }

    It 'Appends to a register without temporary files and keeps the existing lines' {
        Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
        Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '11' -Name 'Scania AB'
        Set-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Email 'faktura@volvo.example'

        @(Get-LedgerCustomer -JournalPath $JournalPath).CustomerNumber | Should -Be @('10', '11')
        @(Get-ChildItem -Path $JournalPath -Force -Filter '.tmp_*').Count | Should -Be 0
    }

    It 'Leaves the register unchanged when the write fails' {
        Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
        $file = Join-Path $JournalPath 'customers.txt'
        $before = Get-Content -Raw $file

        Mock -ModuleName PSLedger Set-Content { throw 'simulated write failure' }
        { Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '11' -Name 'Scania AB' } | Should -Throw '*simulated write failure*'

        Get-Content -Raw $file | Should -Be $before
        @(Get-ChildItem -Path $JournalPath -Force -Filter '.tmp_*').Count | Should -Be 0
    }

    It 'Resolves relative paths against the PowerShell location' {
        Push-Location $JournalPath
        try {
            Add-LedgerAccount -JournalPath . -AccountNumber '1930' -AccountName 'Företagskonto'
        }
        finally {
            Pop-Location
        }
        (Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '1930').AccountName | Should -Be 'Företagskonto'
    }

    # Only Windows refuses to replace a file another process holds open.
    It 'Retries when another process briefly holds the file open' -Skip:(-not $IsWindows) {
        Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
        $file = Join-Path $JournalPath 'customers.txt'
        $script:Lock = [System.IO.File]::Open($file, 'Open', 'Read', 'Read')
        Mock -ModuleName PSLedger Start-Sleep { $script:Lock.Dispose() }
        try {
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '11' -Name 'Scania AB'
        }
        finally {
            $script:Lock.Dispose()
        }

        Should -Invoke -ModuleName PSLedger Start-Sleep -Times 1 -Exactly
        @(Get-LedgerCustomer -JournalPath $JournalPath).CustomerNumber | Should -Be @('10', '11')
        @(Get-ChildItem -Path $JournalPath -Force -Filter '.tmp_*').Count | Should -Be 0
    }

    It 'Gives up and leaves the file unchanged when it stays locked' -Skip:(-not $IsWindows) {
        Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
        $file = Join-Path $JournalPath 'customers.txt'
        $before = Get-Content -Raw $file
        Mock -ModuleName PSLedger Start-Sleep { }
        $lock = [System.IO.File]::Open($file, 'Open', 'Read', 'Read')
        try {
            { Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '11' -Name 'Scania AB' } | Should -Throw
        }
        finally {
            $lock.Dispose()
        }

        Should -Invoke -ModuleName PSLedger Start-Sleep -Times 4 -Exactly
        Get-Content -Raw $file | Should -Be $before
        @(Get-ChildItem -Path $JournalPath -Force -Filter '.tmp_*').Count | Should -Be 0
    }
}