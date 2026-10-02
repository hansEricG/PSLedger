# Contract test for the on-disk format described in docs/File-format.md.
# The reference journal in Fixtures/FileFormat MUST NOT be edited to make a failing test pass:
# a failure here means a change breaks existing journals and needs a schema bump and a migration.

BeforeAll {
    $script:OriginalUserExt = $env:PSLEDGER_USER_EXTENSIONS
    $script:IsolatedUserExt = Join-Path $TestDrive 'no-user-extensions'
    New-Item -ItemType Directory -Path $IsolatedUserExt -Force | Out-Null
    $env:PSLEDGER_USER_EXTENSIONS = $IsolatedUserExt

    Import-Module (Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1') -Force

    $script:Fixture = Join-Path $PSScriptRoot 'Fixtures' 'FileFormat' 'Exempel.ledger'
    Copy-Item -Path $Fixture -Destination $TestDrive -Recurse -Force
    $script:J = Join-Path $TestDrive 'Exempel.ledger'
    $script:Y = '2024-01_2024-12'
}

AfterAll {
    $env:PSLEDGER_USER_EXTENSIONS = $script:OriginalUserExt
}

Describe 'File format contract' {
    Context 'Fixture' {
        It 'Should be at the current schema version' {
            $current = & (Get-Module PSLedger) { $script:CurrentSchemaVersion }
            (Get-LedgerJournal -Path $J).SchemaVersion | Should -Be $current
        }

        It 'Should store every text file as UTF-8 without BOM' {
            $files = Get-ChildItem -Path $Fixture -Recurse -File -Filter '*.txt'
            $files.Count | Should -BeGreaterThan 20
            foreach ($file in $files) {
                $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
                    Should -BeFalse -Because "$($file.Name) must not start with a BOM"
            }
        }
    }

    Context 'Journal and chart of accounts' {
        It 'Should read journal.txt' {
            $journal = Get-LedgerJournal -Path $J
            $journal.Name | Should -Be 'Exempel AB'
            $journal.OrgNumber | Should -Be '556677-8899'
            $journal.CompanyType | Should -Be 'AB'
            $journal.SchemaVersion | Should -Be 2
        }

        It 'Should read accounts.txt including Swedish characters' {
            (Get-LedgerAccount -JournalPath $J -AccountNumber 1930).AccountName | Should -Be 'Företagskonto'
            (Get-LedgerAccount -JournalPath $J -AccountNumber 2640).AccountName | Should -Be 'Ingående moms'
            @(Get-LedgerAccount -JournalPath $J).Count | Should -BeGreaterThan 100
        }

        It 'Should read dimensions.txt and objects.txt' {
            (Get-LedgerDimension -JournalPath $J -DimensionNumber 1).Name | Should -Be 'Kostnadsställe'
            $object = Get-LedgerObject -JournalPath $J -DimensionNumber 1 -ObjectNumber 10
            $object.Name | Should -Be 'Administration'
        }
    }

    Context 'Fiscal years and verifications' {
        It 'Should read year.txt for every fiscal year' {
            $years = @(Get-LedgerFiscalYear -JournalPath $J)
            $years.Name | Should -Be @('2023-01_2023-12', '2024-01_2024-12')
            $years[0].Status | Should -Be 'Closed'
            $years[1].Status | Should -Be 'Open'
            [datetime]$years[1].StartDate | Should -Be ([datetime]'2024-01-01')
            [datetime]$years[1].EndDate | Should -Be ([datetime]'2024-12-31')
        }

        It 'Should read a verification with objects and a row comment' {
            $entry = Get-LedgerEntry -JournalPath $J -FiscalYear $Y -VerificationNumber 1
            [datetime]$entry.Date | Should -Be ([datetime]'2024-02-01')
            $entry.Description | Should -Be 'Kontorsmaterial'
            $entry.Rows.Count | Should -Be 3
            $entry.Rows[0].Account | Should -Be 6110
            $entry.Rows[0].Amount | Should -Be 800
            $entry.Rows[0].Objects[1] | Should -Be 10
            $entry.Rows[0].Comment | Should -Be 'Pennor'
            $entry.Rows[2].Amount | Should -Be (-1000)
        }

        It 'Should read amounts with varying number of decimals' {
            $entry = Get-LedgerEntry -JournalPath $J -FiscalYear $Y -VerificationNumber 6
            ($entry.Rows | Measure-Object -Property Amount -Sum).Sum | Should -Be 0
            ($entry.Rows | Where-Object Account -EQ 2710).Amount | Should -Be (-9000)
            ($entry.Rows | Where-Object Account -EQ 7510).Amount | Should -Be 9426
        }

        It 'Should read all verifications in the fiscal year' {
            @(Get-LedgerEntry -JournalPath $J -FiscalYear $Y).Count | Should -Be 7
            @(Get-LedgerEntry -JournalPath $J -FiscalYear '2023-01_2023-12').Count | Should -Be 1
        }

        It 'Should read attachments and year documents' {
            (Get-LedgerAttachment -JournalPath $J -FiscalYear $Y -VerificationNumber 1).FileName | Should -Be 'kvitto.pdf'
            (Get-LedgerDocument -JournalPath $J -FiscalYear $Y).FileName | Should -Be 'avtal.pdf'
        }
    }

    Context 'Opening balance, holdings and report input' {
        It 'Should read ib.txt as opening balances' {
            $balance = Get-LedgerBalance -JournalPath $J -FiscalYear $Y
            ($balance | Where-Object AccountNumber -EQ 1930).OpeningBalance | Should -Be 25000
            ($balance | Where-Object AccountNumber -EQ 2081).OpeningBalance | Should -Be (-25000)
            ($balance | Where-Object AccountNumber -EQ 1930).Balance | Should -Be 14955
        }

        It 'Should read holdings.txt' {
            $holding = Get-LedgerHolding -JournalPath $J -FiscalYear $Y
            $holding.Account | Should -Be 1310
            $holding.Name | Should -Be 'Investor B'
            $holding.Isin | Should -Be 'SE0015811963'
            $holding.Quantity | Should -Be 100
            $holding.Price | Should -Be 250.5
            $holding.Currency | Should -Be 'SEK'
            $holding.BookValue | Should -Be 20000
            $holding.MarketValue | Should -Be 25050
        }

        It 'Should read report.txt' {
            $reportInput = Get-LedgerReportInput -JournalPath $J -FiscalYear $Y
            $reportInput.AverageEmployees | Should -Be 1
            $reportInput.SigningPlace | Should -Be 'Stockholm'
            [datetime]$reportInput.SigningDate | Should -Be ([datetime]'2025-03-15')
            $reportInput.SignificantEvents | Should -Be 'Bolaget har startat.'
        }
    }

    Context 'Customers, suppliers and invoices' {
        It 'Should read customers.txt and suppliers.txt' {
            $customer = Get-LedgerCustomer -JournalPath $J -CustomerNumber 10
            $customer.Name | Should -Be 'Volvo AB'
            $customer.OrgNumber | Should -Be '556012-5790'
            $customer.Email | Should -Be 'faktura@volvo.example'
            $customer.PaymentTermsDays | Should -Be 30
            $customer.HourlyRate | Should -Be 1100

            $supplier = Get-LedgerSupplier -JournalPath $J -SupplierNumber 100
            $supplier.Name | Should -Be 'Telia AB'
            $supplier.PaymentTermsDays | Should -Be 20
        }

        It 'Should read a paid customer invoice with rows and payments' {
            $invoice = Get-LedgerInvoice -JournalPath $J -InvoiceNumber 1
            $invoice.Status | Should -Be 'Paid'
            $invoice.CustomerNumber | Should -Be 10
            $invoice.InvoiceDate | Should -Be ([datetime]'2024-03-01')
            $invoice.DueDate | Should -Be ([datetime]'2024-03-31')
            $invoice.BookedVerification | Should -Be 2
            $invoice.BookedFiscalYear | Should -Be $Y
            $invoice.OcrReference | Should -Be '133'
            $invoice.Rows.Count | Should -Be 1
            $invoice.Rows[0].Account | Should -Be 3010
            $invoice.Rows[0].VatRate | Should -Be 0.25
            $invoice.Rows[0].Quantity | Should -Be 10
            $invoice.Rows[0].Unit | Should -Be 'h'
            $invoice.Rows[0].UnitPrice | Should -Be 1000
            $invoice.Total | Should -Be 12500
            $invoice.Payments.Count | Should -Be 1
            $invoice.Payments[0].VerificationNumber | Should -Be 3
            $invoice.RemainingAmount | Should -Be 0
        }

        It 'Should read a draft invoice' {
            $invoice = Get-LedgerInvoice -JournalPath $J -InvoiceNumber 2
            $invoice.Status | Should -Be 'Draft'
            $invoice.BookedVerification | Should -BeNullOrEmpty
            $invoice.Rows[0].Quantity | Should -Be 7.5
            $invoice.Rows[0].Description | Should -Be 'Volvo integration – Anna Andersson, april 2024'
            $invoice.Total | Should -Be 11250
        }

        It 'Should read a supplier invoice' {
            $invoice = Get-LedgerSupplierInvoice -JournalPath $J -InvoiceNumber 1
            $invoice.SupplierNumber | Should -Be 100
            $invoice.SupplierReference | Should -Be 'T-4711'
            $invoice.Status | Should -Be 'Paid'
            $invoice.PayableAccount | Should -Be 2440
            $invoice.Rows[0].Account | Should -Be 6210
            $invoice.Total | Should -Be 500
            $invoice.Payments[0].VerificationNumber | Should -Be 5
            $invoice.RemainingAmount | Should -Be 0
        }
    }

    Context 'Payroll' {
        It 'Should read employees.txt' {
            $employee = Get-LedgerEmployee -JournalPath $J -EmployeeNumber 1
            $employee.Name | Should -Be 'Anna Andersson'
            $employee.PersonalNumber | Should -Be '19800101-1234'
            $employee.SalaryAccount | Should -Be 7210
            $employee.TaxRate | Should -Be 0.3
        }

        It 'Should read a booked payslip' {
            $payslip = Get-LedgerPayslip -JournalPath $J -PayslipNumber 1
            $payslip.Status | Should -Be 'Booked'
            $payslip.PayDate | Should -Be ([datetime]'2024-03-25')
            $payslip.GrossSalary | Should -Be 30000
            $payslip.TaxAmount | Should -Be 9000
            $payslip.EmployerContributionRate | Should -Be 0.3142
            $payslip.NetPay | Should -Be 21000
            $payslip.EmployerContribution | Should -Be 9426
            $payslip.BookedVerification | Should -Be 6
        }
    }

    Context 'Bank' {
        It 'Should read a bank statement' {
            $statement = Get-LedgerBankStatement -JournalPath $J -StatementNumber 1
            $statement.BankAccount | Should -Be 1930
            $statement.Source | Should -Be 'Csv'
            $statement.FileName | Should -Be 'bank.csv'
            $statement.FromDate | Should -Be ([datetime]'2024-03-25')
            $statement.ToDate | Should -Be ([datetime]'2024-03-31')
            $statement.OpeningBalance | Should -Be 24500
            $statement.ClosingBalance | Should -Be 36455
            $statement.Transactions | Should -Be 3
            $statement.Matched | Should -Be 3
        }

        It 'Should read bank transactions and their matches' {
            $transactions = @(Get-LedgerBankTransaction -JournalPath $J)
            $transactions.Count | Should -Be 3
            $transactions[0].Amount | Should -Be 12500
            $transactions[0].Reference | Should -Be '133'
            $transactions[0].MatchType | Should -Be 'Entry'
            $transactions[0].VerificationNumber | Should -Be 3
            $transactions[2].Amount | Should -Be (-45)
            $transactions[2].MatchType | Should -Be 'Rule'
            $transactions[2].MatchRef | Should -Be 'Bankavgift'
            $transactions[2].FiscalYear | Should -Be $Y
        }

        It 'Should read bank rules' {
            $rule = Get-LedgerBankRule -JournalPath $J
            $rule.Pattern | Should -Be 'Bankavgift'
            $rule.Account | Should -Be 6570
            $rule.VatRate | Should -Be 0
        }
    }

    Context 'Time reporting' {
        It 'Should read resources and projects' {
            $resource = Get-LedgerTimeResource -JournalPath $J -ResourceId 'anna'
            $resource.Name | Should -Be 'Anna Andersson'
            $resource.EmployeeNumber | Should -Be 1
            $resource.CostRate | Should -Be 450
            $resource.IsDefault | Should -BeTrue

            $project = Get-LedgerProject -JournalPath $J -ProjectNumber 'P1'
            $project.Name | Should -Be 'Volvo integration'
            $project.CustomerNumber | Should -Be 10
            $project.HourlyRate | Should -Be 1200
            $project.Status | Should -Be 'Active'
        }

        It 'Should read time entries across monthly files' {
            $entries = @(Get-LedgerTimeEntry -JournalPath $J)
            $entries.Count | Should -Be 3
            $entries[0].Hours | Should -Be 7.5
            $entries[0].Billable | Should -BeTrue
            $entries[0].Status | Should -Be 'Invoiced'
            $entries[0].InvoiceNumber | Should -Be 2
            $entries[1].Billable | Should -BeFalse
            $entries[1].Text | Should -Be 'Möte'
            $entries[2].Date | Should -Be ([datetime]'2024-05-02')
            $entries[2].Status | Should -Be 'Open'
        }
    }

    Context 'Recurring entries' {
        It 'Should read a recurring entry template' {
            $template = Get-LedgerRecurringEntry -JournalPath $J -Name 'hyra'
            $template.Description | Should -Be 'Lokalhyra'
            $template.Schedule | Should -Be 'monthly'
            $template.DayOfMonth | Should -Be 1
            $template.StartDate | Should -Be ([datetime]'2024-01-01')
            $template.EndDate | Should -Be ([datetime]'2024-12-31')
            $template.LastGenerated | Should -BeNullOrEmpty
            $template.Rows.Count | Should -Be 2
            $template.Rows[0].Account | Should -Be 5010
            $template.Rows[1].Amount | Should -Be (-5000)
        }
    }

    Context 'Writing' {
        It 'Should write a verification in the documented format' {
            $rows = @(
                New-LedgerEntryRow -Debit 6110 -Amount 120.5 -Objects @{ 1 = 10 } -Comment 'Papper'
                New-LedgerEntryRow -Credit 1930 -Amount 120.5
            )
            Add-LedgerEntry -JournalPath $J -FiscalYear $Y -Date '2024-04-02' -Description 'Kontorsmaterial' -Rows $rows

            $lines = [System.IO.File]::ReadAllLines((Join-Path $J $Y 'ver0008.txt'))
            $lines | Should -Contain 'Date: 2024-04-02'
            $lines | Should -Contain 'Description: Kontorsmaterial'
            $lines | Should -Contain "6110`t120.5`t{1:10}`tPapper"
            $lines | Should -Contain "1930`t-120.5"
        }
    }
}
