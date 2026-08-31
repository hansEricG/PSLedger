<#
.SYNOPSIS
Exports a customer invoice to a PDF, Word, Markdown or plain-text document.

.DESCRIPTION
Renders a single invoice as a printable document and writes it to a file. The
document contains the seller (from the journal), the customer (from the customer
register), the invoice metadata (number, dates, payment terms), a table of the
revenue rows with VAT, the totals and payment information.

Payment details (bankgiro, plusgiro, IBAN/BIC) are read from the journal metadata
when present — set them with Set-LedgerJournal -Metadata @{ Bankgiro = '...' }.

The PDF is produced by a dependency-free built-in writer (standard fonts, no
external module). Amounts use Swedish formatting.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the invoice to export.

.PARAMETER Path
Destination path for the document.

.PARAMETER Format
The output format: 'Pdf' (default), 'Word' (.docx), 'Markdown' or 'Text'.

.PARAMETER Force
Overwrite the destination file if it already exists.

.EXAMPLE
Export-LedgerInvoice -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Path .\faktura-1.pdf

Writes invoice 1 as a PDF document.

.EXAMPLE
Export-LedgerInvoice -InvoiceNumber 1 -Path .\faktura-1.docx -Format Word -Force

Writes invoice 1 as a Word document, overwriting any existing file.
#>
function Export-LedgerInvoice {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Pdf', 'Word', 'Markdown', 'Text')]
        [string]$Format = 'Pdf',

        [Parameter()]
        [switch]$Force
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if ((Test-Path $Path) -and -not $Force) {
        throw "Destination file already exists: $Path. Use -Force to overwrite."
    }

    $invoice = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
    if (-not $invoice) {
        throw "Invoice $InvoiceNumber does not exist."
    }

    $journal = Get-LedgerJournal -Path $JournalPath
    $customer = Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber $invoice.CustomerNumber

    $blocks = @(Build-LedgerInvoiceBlock -Invoice $invoice -Journal $journal -Customer $customer)

    switch ($Format) {
        'Word' { ConvertTo-LedgerReportDocx -Block $blocks -Path $Path }
        'Pdf' { ConvertTo-LedgerReportPdf -Block $blocks -Path $Path }
        'Markdown' { ConvertTo-LedgerReportMarkdown -Block $blocks | Set-Content -Path $Path -Encoding UTF8 }
        default { ConvertTo-LedgerReportText -Block $blocks | Set-Content -Path $Path -Encoding UTF8 }
    }
}

function Build-LedgerInvoiceBlock {
    <#
    .SYNOPSIS
    Builds the shared report block model for a single invoice document.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Invoice,

        [Parameter(Mandatory)]
        [psobject]$Journal,

        [Parameter()]
        [psobject]$Customer
    )

    $blocks = New-Object System.Collections.Generic.List[object]

    # --- Seller ---------------------------------------------------------------
    $blocks.Add(@{ Type = 'Title'; Text = $Journal.Name })
    $sellerBits = @()
    if ($Journal.OrgNumber) { $sellerBits += "Org.nr $($Journal.OrgNumber)" }
    if ($Journal.Metadata -and $Journal.Metadata.Contains('VatNumber') -and $Journal.Metadata['VatNumber']) {
        $sellerBits += "Momsreg.nr $($Journal.Metadata['VatNumber'])"
    }
    if ($sellerBits.Count -gt 0) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = ($sellerBits -join '   ') })
    }

    # --- Invoice heading + metadata ------------------------------------------
    $blocks.Add(@{ Type = 'Heading'; Level = 1; Text = "Faktura $($Invoice.InvoiceNumber)" })

    $terms = [int]([datetime]$Invoice.DueDate - [datetime]$Invoice.InvoiceDate).TotalDays
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Fakturadatum: $($Invoice.InvoiceDate.ToString('yyyy-MM-dd'))" })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Förfallodatum: $($Invoice.DueDate.ToString('yyyy-MM-dd'))" })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Betalningsvillkor: $terms dagar netto" })
    if ($Invoice.Description) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "Avser: $($Invoice.Description)" })
    }

    # --- Customer -------------------------------------------------------------
    $blocks.Add(@{ Type = 'Spacer' })
    $custName = if ($Invoice.PSObject.Properties['CustomerName'] -and $Invoice.CustomerName) { $Invoice.CustomerName } elseif ($Customer) { $Customer.Name } else { '' }
    $blocks.Add(@{ Type = 'Heading'; Level = 2; Text = 'Kund' })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "$($Invoice.CustomerNumber)  $custName" })
    if ($Customer) {
        if ($Customer.OrgNumber) { $blocks.Add(@{ Type = 'Paragraph'; Text = "Org.nr $($Customer.OrgNumber)" }) }
        if ($Customer.Email) { $blocks.Add(@{ Type = 'Paragraph'; Text = $Customer.Email }) }
    }

    # --- Rows table -----------------------------------------------------------
    $blocks.Add(@{ Type = 'Spacer' })
    $rows = foreach ($r in $Invoice.Rows) {
        $vatPct = (Format-LedgerAmount -Value ([decimal]$r.VatRate * 100) -Decimals 0) + ' %'
        $lineTotal = [decimal]$r.Amount + [decimal]$r.VatAmount
        , @(
            [string]$r.Account
            (Format-LedgerAmount -Value ([decimal]$r.Amount))
            $vatPct
            (Format-LedgerAmount -Value ([decimal]$r.VatAmount))
            (Format-LedgerAmount -Value $lineTotal)
        )
    }
    $blocks.Add(@{
            Type   = 'Table'
            Header = @('Konto', 'Netto', 'Moms %', 'Moms', 'Summa')
            Align  = @('left', 'right', 'right', 'right', 'right')
            Rows   = @($rows)
        })

    # --- Totals ---------------------------------------------------------------
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Netto: $(Format-LedgerAmount -Value $Invoice.NetTotal) kr" })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Moms: $(Format-LedgerAmount -Value $Invoice.VatTotal) kr" })
    $blocks.Add(@{ Type = 'Heading'; Level = 2; Text = "Att betala: $(Format-LedgerAmount -Value $Invoice.Total) kr" })

    if ($Invoice.Status -in @('Partial', 'Paid')) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "Betalt: $(Format-LedgerAmount -Value $Invoice.PaidAmount) kr" })
        $blocks.Add(@{ Type = 'Paragraph'; Text = "Kvar att betala: $(Format-LedgerAmount -Value $Invoice.RemainingAmount) kr" })
    }

    # --- Payment information --------------------------------------------------
    $payBits = @()
    if ($Journal.Metadata) {
        foreach ($pair in @(@('Bankgiro', 'Bankgiro'), @('Plusgiro', 'Plusgiro'), @('Iban', 'IBAN'), @('Bic', 'BIC'))) {
            $key = $pair[0]; $label = $pair[1]
            if ($Journal.Metadata.Contains($key) -and $Journal.Metadata[$key]) {
                $payBits += "$label $($Journal.Metadata[$key])"
            }
        }
    }
    $blocks.Add(@{ Type = 'Spacer' })
    if ($payBits.Count -gt 0) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "Betalning: $($payBits -join '   ')" })
    }
    if ($Invoice.PSObject.Properties['OcrReference'] -and $Invoice.OcrReference) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "OCR-referens: $($Invoice.OcrReference)" })
    }
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Vänligen ange fakturanummer $($Invoice.InvoiceNumber) vid betalning." })

    $blocks
}
