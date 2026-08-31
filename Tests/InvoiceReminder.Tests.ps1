BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    function New-ReminderTestJournal {
        param([string]$Root)
        return New-TestLedger -Root $Root -Metadata @{ Bankgiro = '123-4567' } `
            -Customers @(@{ Number = '10'; Name = 'Volvo AB'; PaymentTermsDays = 30 })
    }

    function New-BookedInvoice {
        param([string]$JournalPath)
        New-TestPostedInvoice -JournalPath $JournalPath -Description 'Konsult' | Out-Null
    }
}

Describe 'Add-LedgerInvoiceReminder' {
    BeforeAll {
        $CommandName = 'Add-LedgerInvoiceReminder'
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
            $JournalPath = New-ReminderTestJournal -Root $TestDrive
            New-BookedInvoice -JournalPath $JournalPath
        }

        It 'Should increment the reminder count and record the date' {
            $inv = Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-05-15' -PassThru
            $inv.ReminderCount | Should -Be 1
            $inv.LastReminderDate.ToString('yyyy-MM-dd') | Should -Be '2024-05-15'
        }

        It 'Should accumulate reminder counts across calls' {
            Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-05-15'
            $inv = Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-06-15' -PassThru
            $inv.ReminderCount | Should -Be 2
        }

        It 'Should not book anything to the ledger' {
            $before = (Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' | Where-Object AccountNumber -eq '1510').Balance
            Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-05-15' -Fee 60
            $after = (Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' | Where-Object AccountNumber -eq '1510').Balance
            $after | Should -Be $before
        }

        It 'Should write a reminder document with the overdue amount and fee' {
            $out = Join-Path $TestDrive 'pam.txt'
            Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-05-15' -Fee 60 -Path $out -Format Text
            $content = (Get-Content $out -Raw) -replace "\u00A0", ' '
            $content | Should -Match 'Betalningspåminnelse'
            $content | Should -Match 'Påminnelse nr 1'
            $content | Should -Match '12 500,00'
            $content | Should -Match 'Påminnelseavgift: 60,00'
            $content | Should -Match 'Att betala: 12 560,00'
        }

        It 'Should include the OCR reference in the document' {
            $out = Join-Path $TestDrive 'pam-ocr.txt'
            Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-05-15' -Path $out -Format Text
            (Get-Content $out -Raw) | Should -Match 'OCR-referens:'
        }

        It 'Should write a valid PDF reminder' {
            $out = Join-Path $TestDrive 'pam.pdf'
            Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-05-15' -Path $out -Format Pdf
            $bytes = [System.IO.File]::ReadAllBytes($out)
            [System.Text.Encoding]::ASCII.GetString($bytes[0..4]) | Should -Be '%PDF-'
        }

        It 'Should record the reminder even when no document is written' {
            $inv = Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-05-15' -PassThru
            $inv.ReminderCount | Should -Be 1
        }

        It 'Should throw when the invoice does not exist' {
            { Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 99 } | Should -Throw '*does not exist*'
        }

        It 'Should throw for a draft (unposted) invoice' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' `
                -Description 'Draft' -Rows @(@{ Account = '3010'; Amount = 500; VatRate = 0.25; VatAccount = '2610' }) | Out-Null
            { Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 2 } | Should -Throw '*open receivable*'
        }

        It 'Should throw for a fully paid invoice' {
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10'
            { Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*open receivable*'
        }

        It 'Should refuse to overwrite an existing document without -Force' {
            $out = Join-Path $TestDrive 'pam-existing.txt'
            Set-Content -Path $out -Value 'existing'
            { Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Path $out -Format Text } |
                Should -Throw '*already exists*'
        }
    }
}
