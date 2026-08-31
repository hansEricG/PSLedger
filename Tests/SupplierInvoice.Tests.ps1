BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force

    function New-SupInvTestJournal {
        param([string]$Root)
        $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $path -Name 'Faktura AB' -CompanyType AB | Out-Null
        Import-LedgerChart -JournalPath $path -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $path -StartDate '2024-01-01' -EndDate '2024-12-31'
        Add-LedgerSupplier -JournalPath $path -SupplierNumber '100' -Name 'Kontorsbolaget AB' -PaymentTermsDays 30
        return $path
    }
}

Describe 'New-LedgerSupplierInvoice' {
    BeforeAll {
        $Command = Get-Command -Name 'New-LedgerSupplierInvoice'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }
        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
        It 'Should have mandatory SupplierNumber, Description and Rows parameters' {
            foreach ($p in 'SupplierNumber', 'Description', 'Rows') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-SupInvTestJournal -Root $TestDrive
            $rows = @(@{ Account = '5010'; Amount = 8000; VatRate = 0.25; VatAccount = '2640' })
        }

        It 'Should create sup0001.txt for the first invoice' {
            New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Date '2024-03-10' -Description 'Hyra' -Rows $rows
            Test-Path (Join-Path $JournalPath 'supplierinvoices\sup0001.txt') | Should -BeTrue
        }

        It 'Should compute Net, Vat and gross totals' {
            $inv = New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Date '2024-03-10' -Description 'Hyra' -Rows $rows -PassThru
            $inv.NetTotal | Should -Be 8000
            $inv.VatTotal | Should -Be 2000
            $inv.Total | Should -Be 10000
            $inv.Status | Should -Be 'Draft'
        }

        It 'Should store the supplier invoice number and reference' {
            $inv = New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Date '2024-03-10' -Description 'Hyra' -SupplierInvoiceNo 'F-99123' -Reference '1234567' -Rows $rows -PassThru
            $inv.SupplierInvoiceNo | Should -Be 'F-99123'
            $inv.Reference | Should -Be '1234567'
        }

        It 'Should default the payable account to 2440' {
            $inv = New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Date '2024-03-10' -Description 'Hyra' -Rows $rows -PassThru
            $inv.PayableAccount | Should -Be '2440'
        }

        It 'Should calculate DueDate from supplier payment terms' {
            $inv = New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Date '2024-03-10' -Description 'Hyra' -Rows $rows -PassThru
            $inv.DueDate.ToString('yyyy-MM-dd') | Should -Be '2024-04-09'
        }

        It 'Should reject an unknown supplier' {
            { New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '999' -Description 'X' -Rows $rows } | Should -Throw '*does not exist*'
        }

        It 'Should reject a non-positive amount' {
            { New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Description 'X' -Rows @(@{ Account = '5010'; Amount = -5 }) } | Should -Throw '*greater than zero*'
        }
    }
}

Describe 'Invoke-LedgerSupplierInvoicePosting' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-SupInvTestJournal -Root $TestDrive
            New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Date '2024-03-10' -Description 'Hyra' `
                -Rows @(@{ Account = '5010'; Amount = 8000; VatRate = 0.25; VatAccount = '2640' }) | Out-Null
        }

        It 'Should post a balanced verification (debit cost + input VAT, credit payable)' {
            Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($b | Where-Object AccountNumber -eq '5010').Balance | Should -Be 8000
            ($b | Where-Object AccountNumber -eq '2640').Balance | Should -Be 2000
            ($b | Where-Object AccountNumber -eq '2440').Balance | Should -Be -10000
        }

        It 'Should mark the invoice Booked and record the verification' {
            $inv = Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 -PassThru
            $inv.Status | Should -Be 'Booked'
            $inv.BookedVerification | Should -Not -BeNullOrEmpty
        }

        It 'Should refuse to post twice' {
            Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            { Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*already posted*'
        }
    }
}

Describe 'Add-LedgerSupplierPayment' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-SupInvTestJournal -Root $TestDrive
            New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Date '2024-03-10' -Description 'Hyra' `
                -Rows @(@{ Account = '5010'; Amount = 8000; VatRate = 0.25; VatAccount = '2640' }) | Out-Null
            Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
        }

        It 'Should register a full payment and mark it Paid' {
            $inv = Add-LedgerSupplierPayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-05' -PassThru
            $inv.Status | Should -Be 'Paid'
            $inv.RemainingAmount | Should -Be 0
        }

        It 'Should support partial payments' {
            $inv = Add-LedgerSupplierPayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 4000 -Date '2024-04-05' -PassThru
            $inv.Status | Should -Be 'Partial'
            $inv.RemainingAmount | Should -Be 6000
        }

        It 'Should net the payable to zero after full payment' {
            Add-LedgerSupplierPayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-05'
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($b | Where-Object AccountNumber -eq '2440').Balance | Should -Be 0
        }

        It 'Should reject a payment exceeding the remaining amount' {
            { Add-LedgerSupplierPayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 99999 -Date '2024-04-05' } | Should -Throw '*exceeds*'
        }

        It 'Should reject payment of an unposted invoice' {
            New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Date '2024-03-10' -Description 'Draft' `
                -Rows @(@{ Account = '5010'; Amount = 500 }) | Out-Null
            { Add-LedgerSupplierPayment -JournalPath $JournalPath -InvoiceNumber 2 -Date '2024-04-05' } | Should -Throw '*not been posted*'
        }
    }
}
