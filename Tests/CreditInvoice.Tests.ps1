BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    function New-CreditTestJournal {
        param([string]$Root)
        return New-TestLedger -Root $Root -Customers @(@{ Number = '10'; Name = 'Volvo AB'; PaymentTermsDays = 30 })
    }

    function New-BookedInvoice {
        param([string]$JournalPath)
        return New-TestPostedInvoice -JournalPath $JournalPath
    }
}

Describe 'Add-LedgerCreditInvoice' {
    BeforeAll {
        $CommandName = 'Add-LedgerCreditInvoice'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory InvoiceNumber parameter typed as int' {
            $Command.Parameters['InvoiceNumber'].Attributes.Mandatory | Should -Contain $true
            $Command.Parameters['InvoiceNumber'].ParameterType | Should -Be ([int])
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-CreditTestJournal -Root $TestDrive
        }

        It 'Should create a credit note with a new number and negated total' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            $credit = Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30' -PassThru
            $credit.InvoiceNumber | Should -Be 2
            $credit.Total | Should -Be (-12500)
            $credit.Status | Should -Be 'Credited'
        }

        It 'Should mark both the original and the credit note as Credited' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30'
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).Status | Should -Be 'Credited'
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 2).Status | Should -Be 'Credited'
        }

        It 'Should post a balanced reversing verification' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30'
            $balances = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            foreach ($acct in '1510', '3010', '2610') {
                ($balances | Where-Object AccountNumber -eq $acct).Balance | Should -Be 0
            }
        }

        It 'Should remove the invoice from accounts receivable' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30'
            $ar = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-05-01')
            $ar.Count | Should -Be 0
        }

        It 'Should throw when the invoice does not exist' {
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 99 } | Should -Throw '*does not exist*'
        }

        It 'Should throw for a Draft invoice (not posted)' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Draft' -Rows @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25; VatAccount = '2610' }) | Out-Null
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*not posted*'
        }

        It 'Should throw for an invoice with payments' {
            $n = New-BookedInvoice -JournalPath $JournalPath
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber $n -Amount 5000 -Date '2024-04-10'
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber $n } | Should -Throw '*payments*'
        }

        It 'Should throw when crediting an already-credited invoice' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30'
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*already been credited*'
        }
    }
}
