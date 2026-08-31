BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'SupportsShouldProcess coverage' {
    # Every command that writes persistent journal data should honour -WhatIf and
    # -Confirm so callers can preview or gate changes.
    Context 'Write commands expose -WhatIf / -Confirm' {
        $WriteCommands = @(
            # Register writers
            'Add-LedgerAccount', 'Add-LedgerCustomer', 'Add-LedgerSupplier', 'Add-LedgerEmployee',
            'Add-LedgerDimension', 'Add-LedgerObject', 'New-LedgerRecurringEntry', 'Import-LedgerChart',
            # Verification writers
            'Add-LedgerEntry', 'Add-LedgerReversal', 'Copy-LedgerOpeningBalance', 'Add-LedgerAccrual',
            'Add-LedgerInvoicePayment', 'Add-LedgerSupplierPayment', 'Add-LedgerInvoiceFee',
            'Add-LedgerInvoiceInterest', 'Add-LedgerCreditInvoice', 'Add-LedgerInvoiceReminder',
            # Document / record creators
            'New-LedgerJournal', 'New-LedgerFiscalYear', 'New-LedgerInvoice', 'New-LedgerSupplierInvoice',
            'New-LedgerPayslip', 'Add-LedgerAttachment', 'Add-LedgerDocument',
            # Orchestrators / removers
            'Invoke-LedgerInvoicePosting', 'Invoke-LedgerPayrollPosting', 'Invoke-LedgerSupplierInvoicePosting',
            'Invoke-LedgerRecurringEntry', 'Import-LedgerSie', 'Remove-LedgerRecurringEntry'
        )

        It '<_> supports ShouldProcess' -ForEach $WriteCommands {
            $Command = Get-Command -Name $_
            Test-TDDSupportsShouldProcess -Command $Command | Should -BeTrue
        }
    }

    Context '-WhatIf does not write data' {
        BeforeEach {
            $JournalName = [guid]::NewGuid().ToString('N')
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
        }

        It 'New-LedgerJournal -WhatIf does not create the journal' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB' -WhatIf
            Test-Path $JournalPath | Should -BeFalse
        }

        It 'New-LedgerFiscalYear -WhatIf does not create the fiscal year directory' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31' -WhatIf
            Test-Path (Join-Path $JournalPath '2024-01_2024-12') | Should -BeFalse
        }

        It 'Add-LedgerAccount -WhatIf does not add the account' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa' -WhatIf
            Get-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' | Should -BeNullOrEmpty
        }

        It 'Add-LedgerEntry -WhatIf does not write a verification file' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'

            $rows = @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' `
                -Date '2024-03-01' -Description 'Testverifikation' -Rows $rows -WhatIf

            $verFile = Join-Path $JournalPath '2024-01_2024-12' 'ver0001.txt'
            Test-Path $verFile | Should -BeFalse
        }

        It 'Add-LedgerAttachment -WhatIf does not copy the file' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' `
                -Date '2024-03-01' -Description 'Testverifikation' `
                -Rows @(@{ Account = '1910'; Amount = 1000 }, @{ Account = '3010'; Amount = -1000 })

            $source = Join-Path $TestDrive 'kvitto.pdf'
            Set-Content -Path $source -Value 'dummy'

            Add-LedgerAttachment -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' `
                -VerificationNumber 1 -Path $source -WhatIf

            $dest = Join-Path $JournalPath '2024-01_2024-12' 'ver0001' 'kvitto.pdf'
            Test-Path $dest | Should -BeFalse
        }

        It 'Invoke-LedgerInvoicePosting -WhatIf leaves the invoice as Draft and books nothing' {
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1510' -AccountName 'Kundfordringar'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '2610' -AccountName 'Utgående moms'
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Kund AB'
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-01' `
                -Description 'Konsultarvode' `
                -Rows @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25; VatAccount = '2610' })

            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 -WhatIf

            $invoice = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1
            $invoice.Status | Should -Be 'Draft'
            $invoice.BookedVerification | Should -BeNullOrEmpty
            Test-Path (Join-Path $JournalPath '2024-01_2024-12' 'ver0001.txt') | Should -BeFalse
        }
    }
}
