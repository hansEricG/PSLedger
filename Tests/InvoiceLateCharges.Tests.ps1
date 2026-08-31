BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    function New-ChargeTestJournal {
        param([string]$Root)
        return New-TestLedger -Root $Root -Customers @(@{ Number = '10'; Name = 'Volvo AB'; PaymentTermsDays = 30 })
    }

    function New-PostedInvoice {
        param([string]$JournalPath, [string]$Date = '2024-03-15', [decimal]$Net = 10000)
        return New-TestPostedInvoice -JournalPath $JournalPath -Date $Date -Net $Net -Description 'Konsult'
    }
}

Describe 'Add-LedgerInvoiceFee' {
    BeforeAll {
        $Command = Get-Command -Name 'Add-LedgerInvoiceFee'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }
        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
        It 'Should have mandatory InvoiceNumber and Amount parameters' {
            foreach ($p in 'InvoiceNumber', 'Amount') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-ChargeTestJournal -Root $TestDrive
            $n = New-PostedInvoice -JournalPath $JournalPath
        }

        It 'Should book the fee (debit receivable, credit 3590) and increase the receivable' {
            Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber $n -Amount 60 -Date '2024-05-01'
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($b | Where-Object AccountNumber -eq '1510').Balance | Should -Be 12560
            ($b | Where-Object AccountNumber -eq '3590').Balance | Should -Be (-60)
        }

        It 'Should add the fee to the invoice total and remaining amount' {
            $inv = Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber $n -Amount 60 -Date '2024-05-01' -PassThru
            $inv.ChargesTotal | Should -Be 60
            $inv.Total | Should -Be 12560
            $inv.RemainingAmount | Should -Be 12560
        }

        It 'Should record the charge with its verification' {
            $inv = Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber $n -Amount 60 -Date '2024-05-01' -PassThru
            @($inv.Charges).Count | Should -Be 1
            $inv.Charges[0].Type | Should -Be 'Fee'
            $inv.Charges[0].Amount | Should -Be 60
            $inv.Charges[0].VerificationNumber | Should -Not -BeNullOrEmpty
        }

        It 'Should keep the receivable reconciled with the ledger' {
            Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber $n -Amount 60 -Date '2024-05-01'
            $ar = (Get-LedgerInvoice -JournalPath $JournalPath -Unpaid | Measure-Object RemainingAmount -Sum).Sum
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            $ar | Should -Be ($b | Where-Object AccountNumber -eq '1510').Balance
        }

        It 'Should reject a non-positive amount' {
            { Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber $n -Amount 0 } | Should -Throw '*greater than zero*'
        }

        It 'Should reject a fee on a draft invoice' {
            $rows = @(@{ Account = '3010'; Amount = 500; VatRate = 0.25; VatAccount = '2610' })
            $draft = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Description 'Utkast' -Rows $rows -PassThru
            { Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber $draft.InvoiceNumber -Amount 60 } | Should -Throw '*not been posted*'
        }

        It 'Should reject a fee on a fully paid invoice' {
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber $n -Date '2024-04-10'
            { Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber $n -Amount 60 } | Should -Throw '*not an open receivable*'
        }
    }
}

Describe 'Add-LedgerInvoiceInterest' {
    BeforeAll {
        $Command = Get-Command -Name 'Add-LedgerInvoiceInterest'
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
            $JournalPath = New-ChargeTestJournal -Root $TestDrive
            $n = New-PostedInvoice -JournalPath $JournalPath   # due 2024-04-14, gross 12500
        }

        It 'Should calculate interest from the annual rate and days overdue' {
            # DueDate 2024-04-14, AsOf 2024-06-01 => 48 days; 12500 * 0.105 * 48/365 = 172.60
            $inv = Add-LedgerInvoiceInterest -JournalPath $JournalPath -InvoiceNumber $n -AnnualRate 0.105 -Date '2024-06-01' -PassThru
            $inv.Charges[0].Type | Should -Be 'Interest'
            $inv.Charges[0].Amount | Should -Be 172.60
        }

        It 'Should book the interest to 8310 and the receivable' {
            Add-LedgerInvoiceInterest -JournalPath $JournalPath -InvoiceNumber $n -Amount 200 -Date '2024-06-01'
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($b | Where-Object AccountNumber -eq '8310').Balance | Should -Be (-200)
            ($b | Where-Object AccountNumber -eq '1510').Balance | Should -Be 12700
        }

        It 'Should accept an explicit amount overriding the calculation' {
            $inv = Add-LedgerInvoiceInterest -JournalPath $JournalPath -InvoiceNumber $n -Amount 250 -Date '2024-06-01' -PassThru
            $inv.ChargesTotal | Should -Be 250
            $inv.RemainingAmount | Should -Be 12750
        }

        It 'Should throw when neither rate nor amount is given' {
            { Add-LedgerInvoiceInterest -JournalPath $JournalPath -InvoiceNumber $n -Date '2024-06-01' } | Should -Throw '*-AnnualRate*'
        }

        It 'Should throw when the invoice is not overdue' {
            { Add-LedgerInvoiceInterest -JournalPath $JournalPath -InvoiceNumber $n -AnnualRate 0.105 -Date '2024-04-01' } | Should -Throw '*not overdue*'
        }
    }
}

Describe 'Add-LedgerInvoiceReminder with -BookFee' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-ChargeTestJournal -Root $TestDrive
            $n = New-PostedInvoice -JournalPath $JournalPath
        }

        It 'Should book the fee and increase the receivable while recording the reminder' {
            $inv = Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber $n -Fee 60 -BookFee -Date '2024-05-01' -PassThru
            $inv.ReminderCount | Should -Be 1
            $inv.ChargesTotal | Should -Be 60
            $inv.RemainingAmount | Should -Be 12560
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($b | Where-Object AccountNumber -eq '3590').Balance | Should -Be (-60)
        }

        It 'Should not add the booked fee again on the document amount to pay' {
            $doc = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).txt"
            Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber $n -Fee 60 -BookFee -Date '2024-05-01' -Path $doc -Format Text
            $text = (Get-Content -Path $doc -Raw) -replace "\u00A0", ' '
            $text | Should -Match 'Varav påminnelseavgift'
            $text | Should -Match 'Att betala: 12 560,00 kr'
        }

        It 'Should throw when -BookFee is used without a fee' {
            { Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber $n -BookFee -Date '2024-05-01' } | Should -Throw '*requires -Fee*'
        }

        It 'Should not book anything when -BookFee is omitted' {
            Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber $n -Fee 60 -Date '2024-05-01'
            $inv = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $n
            $inv.ChargesTotal | Should -Be 0
            $inv.RemainingAmount | Should -Be 12500
        }
    }
}

Describe 'Invoice charge persistence' {
    Context 'Round-trip' {
        It 'Should reload booked charges from disk with the same totals' {
            $JournalPath = New-ChargeTestJournal -Root $TestDrive
            $n = New-PostedInvoice -JournalPath $JournalPath
            Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber $n -Amount 60 -Date '2024-05-01'
            Add-LedgerInvoiceInterest -JournalPath $JournalPath -InvoiceNumber $n -Amount 100 -Date '2024-06-01'
            $inv = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $n
            @($inv.Charges).Count | Should -Be 2
            $inv.ChargesTotal | Should -Be 160
            $inv.Total | Should -Be 12660
        }
    }
}
