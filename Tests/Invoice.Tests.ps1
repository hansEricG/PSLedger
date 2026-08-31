BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    function New-InvoiceTestJournal {
        param([string]$Root)
        return New-TestLedger -Root $Root -Customers @(@{ Number = '10'; Name = 'Volvo AB'; PaymentTermsDays = 30 })
    }
}

Describe 'New-LedgerInvoice' {
    BeforeAll {
        $CommandName = 'New-LedgerInvoice'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have mandatory CustomerNumber, Description and Rows parameters' {
            foreach ($p in 'CustomerNumber', 'Description', 'Rows') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-InvoiceTestJournal -Root $TestDrive
            $rows = @(@{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' })
        }

        It 'Should create inv0001.txt for the first invoice' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows
            Test-Path (Join-Path $JournalPath 'invoices\inv0001.txt') | Should -BeTrue
        }

        It 'Should compute Net, Vat and gross totals' {
            $inv = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows -PassThru
            $inv.NetTotal | Should -Be 10000
            $inv.VatTotal | Should -Be 2500
            $inv.Total | Should -Be 12500
            $inv.Status | Should -Be 'Draft'
        }

        It 'Should calculate DueDate from customer payment terms' {
            $inv = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows -PassThru
            $inv.DueDate.ToString('yyyy-MM-dd') | Should -Be '2024-04-14'
        }

        It 'Should honour an explicit DueDate' {
            $inv = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -DueDate '2024-05-01' -Description 'Konsult' -Rows $rows -PassThru
            $inv.DueDate.ToString('yyyy-MM-dd') | Should -Be '2024-05-01'
        }

        It 'Should auto-increment invoice numbers' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'A' -Rows $rows
            $second = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-16' -Description 'B' -Rows $rows -PassThru
            $second.InvoiceNumber | Should -Be 2
        }

        It 'Should throw when the customer does not exist' {
            { New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '99' -Description 'X' -Rows $rows } |
                Should -Throw '*does not exist*'
        }

        It 'Should throw when a VAT-liable row has no VatAccount' {
            $bad = @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25 })
            { New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Description 'X' -Rows $bad } |
                Should -Throw '*no VatAccount*'
        }

        It 'Should throw when a row amount is not positive' {
            $bad = @(@{ Account = '3010'; Amount = -1000 })
            { New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Description 'X' -Rows $bad } |
                Should -Throw '*greater than zero*'
        }
    }
}

Describe 'Get-LedgerInvoice' {
    BeforeAll {
        $CommandName = 'Get-LedgerInvoice'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-InvoiceTestJournal -Root $TestDrive
            $rows = @(@{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Ett' -Rows $rows
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-16' -Description 'Tva' -Rows $rows
        }

        It 'Should return all invoices' {
            @(Get-LedgerInvoice -JournalPath $JournalPath).Count | Should -Be 2
        }

        It 'Should resolve the customer name' {
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).CustomerName | Should -Be 'Volvo AB'
        }

        It 'Should filter by status' {
            @(Get-LedgerInvoice -JournalPath $JournalPath -Status Draft).Count | Should -Be 2
            @(Get-LedgerInvoice -JournalPath $JournalPath -Status Paid).Count | Should -Be 0
        }

        It 'Should exclude drafts from the Unpaid filter' {
            @(Get-LedgerInvoice -JournalPath $JournalPath -Unpaid).Count | Should -Be 0
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            @(Get-LedgerInvoice -JournalPath $JournalPath -Unpaid).Count | Should -Be 1
        }

        It 'Should return nothing when no invoices directory exists' {
            $j2 = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $j2 -Name 'Empty'
            Get-LedgerInvoice -JournalPath $j2 | Should -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-LedgerInvoicePosting' {
    BeforeAll {
        $CommandName = 'Invoke-LedgerInvoicePosting'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory InvoiceNumber parameter' {
            $Command.Parameters['InvoiceNumber'].Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-InvoiceTestJournal -Root $TestDrive
            $rows = @(@{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows
        }

        It 'Should mark the invoice Booked and record the verification' {
            $posted = Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 -PassThru
            $posted.Status | Should -Be 'Booked'
            $posted.BookedVerification | Should -Be 1
            $posted.BookedFiscalYear | Should -Be '2024-01_2024-12'
        }

        It 'Should create a balanced verification with receivable, revenue and VAT' {
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            $bal = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($bal | Where-Object AccountNumber -eq '1510').Balance | Should -Be 12500
            ($bal | Where-Object AccountNumber -eq '3010').Balance | Should -Be -10000
            ($bal | Where-Object AccountNumber -eq '2610').Balance | Should -Be -2500
        }

        It 'Should resolve the fiscal year from the invoice date' {
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12').Count | Should -Be 1
        }

        It 'Should throw when posting an already-posted invoice' {
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            { Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 } |
                Should -Throw '*already posted*'
        }

        It 'Should throw when the invoice does not exist' {
            { Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 99 } |
                Should -Throw '*does not exist*'
        }
    }
}

Describe 'Add-LedgerInvoicePayment' {
    BeforeAll {
        $CommandName = 'Add-LedgerInvoicePayment'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory InvoiceNumber parameter' {
            $Command.Parameters['InvoiceNumber'].Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-InvoiceTestJournal -Root $TestDrive
            $rows = @(@{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
        }

        It 'Should mark the invoice Paid on full payment' {
            $paid = Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10' -PassThru
            $paid.Status | Should -Be 'Paid'
            $paid.PaidAmount | Should -Be 12500
            $paid.RemainingAmount | Should -Be 0
        }

        It 'Should default the payment amount to the remaining amount' {
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10'
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).Status | Should -Be 'Paid'
        }

        It 'Should clear the receivable and debit the bank account' {
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10'
            $bal = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($bal | Where-Object AccountNumber -eq '1510').Balance | Should -Be 0
            ($bal | Where-Object AccountNumber -eq '1930').Balance | Should -Be 12500
        }

        It 'Should support partial payments' {
            $partial = Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' -PassThru
            $partial.Status | Should -Be 'Partial'
            $partial.RemainingAmount | Should -Be 7500
            $full = Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-20' -PassThru
            $full.Status | Should -Be 'Paid'
            @($full.Payments).Count | Should -Be 2
        }

        It 'Should throw when the payment exceeds the remaining amount' {
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 99999 -Date '2024-04-10' } |
                Should -Throw '*exceeds the remaining*'
        }

        It 'Should throw when paying a draft (unposted) invoice' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-20' -Description 'Draft' -Rows $rows
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 2 -Date '2024-04-10' } |
                Should -Throw '*has not been posted*'
        }

        It 'Should throw when paying an already fully paid invoice' {
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10'
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 100 -Date '2024-04-11' } |
                Should -Throw '*already fully paid*'
        }
    }
}
