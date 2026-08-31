BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force

    function New-OcrTestJournal {
        param([string]$Root)
        $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $path -Name 'Faktura AB' -CompanyType AB | Out-Null
        Import-LedgerChart -JournalPath $path -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $path -StartDate '2024-01-01' -EndDate '2024-12-31'
        Add-LedgerCustomer -JournalPath $path -CustomerNumber '10' -Name 'Volvo AB' -PaymentTermsDays 30
        return $path
    }

    # Standard Luhn validation: rightmost digit is the check digit and is NOT
    # doubled; every second digit from the right is doubled. A valid number sums
    # to a multiple of ten.
    function Test-Luhn {
        param([string]$Number)
        $sum = 0
        $double = $false
        for ($i = $Number.Length - 1; $i -ge 0; $i--) {
            $d = [int][string]$Number[$i]
            if ($double) { $d *= 2; if ($d -gt 9) { $d -= 9 } }
            $sum += $d
            $double = -not $double
        }
        return ($sum % 10) -eq 0
    }

    function New-InvoiceWithNumber {
        param([string]$JournalPath, [int]$Count)
        for ($n = 1; $n -le $Count; $n++) {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' `
                -Description "Rad $n" -Rows @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25; VatAccount = '2610' }) | Out-Null
        }
    }
}

Describe 'OCR reference generation' {
    Context 'Behavior via invoice OcrReference' {
        BeforeEach {
            $JournalPath = New-OcrTestJournal -Root $TestDrive
        }

        It 'Should expose an OcrReference on invoices' {
            New-InvoiceWithNumber -JournalPath $JournalPath -Count 1
            $inv = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1
            $inv.OcrReference | Should -Not -BeNullOrEmpty
        }

        It 'Should produce the known reference 133 for invoice 1' {
            New-InvoiceWithNumber -JournalPath $JournalPath -Count 1
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).OcrReference | Should -Be '133'
        }

        It 'Should produce OCR references that pass the Luhn check' {
            New-InvoiceWithNumber -JournalPath $JournalPath -Count 5
            foreach ($n in 1..5) {
                $ref = (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $n).OcrReference
                Test-Luhn -Number $ref | Should -BeTrue -Because "OCR '$ref' for invoice $n should be a valid Luhn number"
            }
        }

        It 'Should embed a valid length-control digit' {
            New-InvoiceWithNumber -JournalPath $JournalPath -Count 3
            foreach ($n in 1..3) {
                $ref = (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $n).OcrReference
                # The length digit is the second-to-last character and equals the
                # total reference length modulo ten.
                $lengthDigit = [int][string]$ref[$ref.Length - 2]
                $lengthDigit | Should -Be ($ref.Length % 10)
            }
        }

        It 'Should contain only digits' {
            New-InvoiceWithNumber -JournalPath $JournalPath -Count 1
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).OcrReference | Should -Match '^\d+$'
        }
    }
}
