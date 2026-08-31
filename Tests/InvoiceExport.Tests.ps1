BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force

    function New-ExportTestJournal {
        param([string]$Root)
        $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $path -Name 'Faktura AB' -CompanyType AB | Out-Null
        Import-LedgerChart -JournalPath $path -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $path -StartDate '2024-01-01' -EndDate '2024-12-31'
        Set-LedgerJournal -JournalPath $path -Metadata @{ Bankgiro = '123-4567'; VatNumber = 'SE556000000001' } | Out-Null
        Add-LedgerCustomer -JournalPath $path -CustomerNumber '10' -Name 'Volvo AB' -PaymentTermsDays 30 -OrgNumber '556012-5790'
        $rows = @(
            @{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' }
            @{ Account = '3590'; Amount = 500; VatRate = 0; VatAccount = '' }
        )
        New-LedgerInvoice -JournalPath $path -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsultarvode mars' -Rows $rows | Out-Null
        Invoke-LedgerInvoicePosting -JournalPath $path -InvoiceNumber 1
        return $path
    }
}

Describe 'Export-LedgerInvoice' {
    BeforeAll {
        $CommandName = 'Export-LedgerInvoice'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have mandatory InvoiceNumber and Path parameters' {
            foreach ($p in 'InvoiceNumber', 'Path') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'Should type InvoiceNumber as int' {
            $Command.Parameters['InvoiceNumber'].ParameterType | Should -Be ([int])
        }

        It 'Should default Format to Pdf' {
            $Command.Parameters['Format'].Attributes.ValidValues | Should -Contain 'Pdf'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-ExportTestJournal -Root $TestDrive
        }

        It 'Should write a valid PDF (starts with %PDF and ends with %%EOF)' {
            $out = Join-Path $TestDrive 'faktura-valid.pdf'
            Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Path $out -Format Pdf
            Test-Path $out | Should -BeTrue
            $bytes = [System.IO.File]::ReadAllBytes($out)
            [System.Text.Encoding]::ASCII.GetString($bytes[0..4]) | Should -Be '%PDF-'
            [System.Text.Encoding]::ASCII.GetString($bytes[-6..-1]).Trim() | Should -Be '%%EOF'
        }

        It 'Should produce a PDF with byte-accurate xref offsets' {
            $out = Join-Path $TestDrive 'faktura-xref.pdf'
            Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Path $out -Format Pdf
            $bytes = [System.IO.File]::ReadAllBytes($out)
            $text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
            $startxref = [int]([regex]::Match($text, 'startxref\s+(\d+)').Groups[1].Value)
            [System.Text.Encoding]::ASCII.GetString($bytes[$startxref..($startxref + 3)]) | Should -Be 'xref'
        }

        It 'Should default to PDF when no format is specified' {
            $out = Join-Path $TestDrive 'faktura-default.pdf'
            Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Path $out
            $bytes = [System.IO.File]::ReadAllBytes($out)
            [System.Text.Encoding]::ASCII.GetString($bytes[0..4]) | Should -Be '%PDF-'
        }

        It 'Should write a Word document (.docx zip signature PK)' {
            $out = Join-Path $TestDrive 'faktura-word.docx'
            Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Path $out -Format Word
            $bytes = [System.IO.File]::ReadAllBytes($out)
            $bytes[0] | Should -Be ([byte]0x50)
            $bytes[1] | Should -Be ([byte]0x4B)
        }

        It 'Should write a Markdown document containing the invoice number and total' {
            $out = Join-Path $TestDrive 'faktura-md.md'
            Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Path $out -Format Markdown
            $content = (Get-Content $out -Raw) -replace "\u00A0", ' '
            $content | Should -Match 'Faktura 1'
            $content | Should -Match '13 000,00'
        }

        It 'Should write a text document containing seller, customer and total' {
            $out = Join-Path $TestDrive 'faktura-text.txt'
            Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Path $out -Format Text
            $content = (Get-Content $out -Raw) -replace "\u00A0", ' '
            $content | Should -Match 'Faktura AB'
            $content | Should -Match 'Volvo AB'
            $content | Should -Match 'Att betala: 13 000,00'
        }

        It 'Should include payment information from journal metadata' {
            $out = Join-Path $TestDrive 'faktura-pay.txt'
            Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Path $out -Format Text
            ((Get-Content $out -Raw) -replace "\u00A0", ' ') | Should -Match 'Bankgiro 123-4567'
        }

        It 'Should throw when the invoice does not exist' {
            { Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 99 -Path (Join-Path $TestDrive 'x.pdf') } |
                Should -Throw
        }

        It 'Should refuse to overwrite an existing file without -Force' {
            $out = Join-Path $TestDrive 'faktura-ovw.txt'
            Set-Content -Path $out -Value 'existing'
            { Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Path $out -Format Text } |
                Should -Throw '*already exists*'
        }

        It 'Should overwrite an existing file with -Force' {
            $out = Join-Path $TestDrive 'faktura-force.txt'
            Set-Content -Path $out -Value 'existing'
            Export-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Path $out -Format Text -Force
            (Get-Content $out -Raw) | Should -Match 'Faktura AB'
        }
    }
}
