<#
.SYNOPSIS
Records a payment reminder (betalningspåminnelse) for an overdue invoice and
optionally writes a reminder document.

.DESCRIPTION
Registers that a reminder has been issued for a posted, unpaid invoice: the
invoice's reminder count is increased by one and the reminder date is recorded on
the invoice. When -Path is given, a reminder document is written in the requested
format (PDF, Word, Markdown or plain text) showing the outstanding amount, how
many days the invoice is overdue, an optional reminder fee and the OCR payment
reference.

The reminder fee is shown on the document as an amount to add to the payment but
is not booked to the ledger, so the accounts receivable continues to reconcile
against the invoice's remaining amount.

Only a posted, unpaid invoice (status Booked or Partial) can be reminded.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the overdue invoice.

.PARAMETER Date
The reminder date, used to calculate the days overdue. Defaults to today.

.PARAMETER Fee
An optional reminder fee (påminnelseavgift). By default it is only shown on the
document and added to the amount to pay, not booked to the ledger. Combine with
-BookFee to book it as an actual charge on the invoice. Defaults to 0.

.PARAMETER BookFee
Book the reminder fee as an actual charge on the invoice (debit the receivable,
credit -FeeAccount) so it increases the open receivable. Requires -Fee greater
than zero. Equivalent to calling Add-LedgerInvoiceFee.

.PARAMETER FeeAccount
The income account a booked fee is credited to. Defaults to '3590' (Övriga
sidointäkter). Only used together with -BookFee.

.PARAMETER Path
Optional destination path for the reminder document. If omitted, the reminder is
only recorded on the invoice and no document is written.

.PARAMETER Format
The document format when -Path is given: 'Pdf' (default), 'Word', 'Markdown' or
'Text'.

.PARAMETER Force
Overwrite the destination file if it already exists.

.PARAMETER PassThru
If specified, returns the updated invoice object.

.EXAMPLE
Add-LedgerInvoiceReminder -JournalPath .\MinFirma.ledger -InvoiceNumber 1 -Path .\paminnelse-1.pdf

Records a reminder for invoice 1 and writes a PDF reminder.

.EXAMPLE
Add-LedgerInvoiceReminder -InvoiceNumber 1 -Fee 60 -Date '2024-05-15' -Path .\paminnelse-1.docx -Format Word

Records a second reminder with a 60 kr reminder fee and writes a Word document.
.EXAMPLE
Add-LedgerInvoiceReminder -InvoiceNumber 1 -Fee 60 -BookFee -Path .\paminnelse-1.pdf

Records a reminder, books a 60 kr reminder fee on the invoice (debit 1510, credit
3590) and writes a PDF where the fee is part of the outstanding amount.
#>
function Add-LedgerInvoiceReminder {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [decimal]$Fee = 0,

        [Parameter()]
        [switch]$BookFee,

        [Parameter()]
        [string]$FeeAccount = '3590',

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Pdf', 'Word', 'Markdown', 'Text')]
        [string]$Format = 'Pdf',

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $invoiceDir = Get-LedgerInvoiceDirectory -JournalPath $JournalPath
    $filePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
    if (-not (Test-Path $filePath)) {
        throw "Invoice $InvoiceNumber does not exist."
    }

    if ($PSBoundParameters.ContainsKey('Path') -and (Test-Path $Path) -and -not $Force) {
        throw "Destination file already exists: $Path. Use -Force to overwrite."
    }

    $invoice = Read-LedgerInvoiceFile -Path $filePath

    if ($invoice.Status -notin @('Booked', 'Partial')) {
        throw "Invoice $InvoiceNumber is not an open receivable (status '$($invoice.Status)'). Only posted, unpaid invoices can be reminded."
    }

    if ($BookFee -and $Fee -le 0) {
        throw "-BookFee requires -Fee to be greater than zero."
    }

    $invoice.ReminderCount = [int]$invoice.ReminderCount + 1
    $invoice.LastReminderDate = $Date
    Save-LedgerInvoiceFile -Invoice $invoice

    if ($BookFee) {
        Add-LedgerInvoiceChargeInternal -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber `
            -Type 'Fee' -Amount $Fee -Account $FeeAccount -Date $Date
    }

    if ($PSBoundParameters.ContainsKey('Path')) {
        $journal = Get-LedgerJournal -Path $JournalPath
        $customer = Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber $invoice.CustomerNumber
        $reloaded = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
        $blocks = @(Build-LedgerReminderBlock -Invoice $reloaded -Journal $journal -Customer $customer -AsOf $Date -Fee $Fee -FeeBooked:$BookFee)

        switch ($Format) {
            'Word' { ConvertTo-LedgerReportDocx -Block $blocks -Path $Path }
            'Pdf' { ConvertTo-LedgerReportPdf -Block $blocks -Path $Path }
            'Markdown' { ConvertTo-LedgerReportMarkdown -Block $blocks | Set-Content -Path $Path -Encoding UTF8 }
            default { ConvertTo-LedgerReportText -Block $blocks | Set-Content -Path $Path -Encoding UTF8 }
        }
    }

    if ($PassThru) {
        Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
    }
}

function Build-LedgerReminderBlock {
    <#
    .SYNOPSIS
    Builds the shared report block model for a payment reminder document.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Invoice,

        [Parameter(Mandatory)]
        [psobject]$Journal,

        [Parameter()]
        [psobject]$Customer,

        [Parameter(Mandatory)]
        [datetime]$AsOf,

        [Parameter()]
        [decimal]$Fee = 0,

        [Parameter()]
        [switch]$FeeBooked
    )

    $blocks = New-Object System.Collections.Generic.List[object]

    $blocks.Add(@{ Type = 'Title'; Text = $Journal.Name })
    if ($Journal.OrgNumber) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "Org.nr $($Journal.OrgNumber)" })
    }

    $reminderNo = [int]$Invoice.ReminderCount
    $blocks.Add(@{ Type = 'Heading'; Level = 1; Text = "Betalningspåminnelse" })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Påminnelse nr $reminderNo" })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Påminnelsedatum: $($AsOf.ToString('yyyy-MM-dd'))" })

    # Customer
    $blocks.Add(@{ Type = 'Spacer' })
    $custName = if ($Invoice.PSObject.Properties['CustomerName'] -and $Invoice.CustomerName) { $Invoice.CustomerName } elseif ($Customer) { $Customer.Name } else { '' }
    $blocks.Add(@{ Type = 'Heading'; Level = 2; Text = 'Kund' })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "$($Invoice.CustomerNumber)  $custName" })

    # Overdue invoice details
    $daysOverdue = [int]([datetime]$AsOf - [datetime]$Invoice.DueDate).TotalDays
    if ($daysOverdue -lt 0) { $daysOverdue = 0 }
    $blocks.Add(@{ Type = 'Spacer' })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Detta gäller faktura $($Invoice.InvoiceNumber) daterad $($Invoice.InvoiceDate.ToString('yyyy-MM-dd'))." })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Förfallodatum: $($Invoice.DueDate.ToString('yyyy-MM-dd')) (förfallen med $daysOverdue dagar)" })

    # Amounts
    $blocks.Add(@{ Type = 'Spacer' })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Kvarstående belopp: $(Format-LedgerAmount -Value $Invoice.RemainingAmount) kr" })
    $amountToPay = [decimal]$Invoice.RemainingAmount
    if ($Fee -gt 0) {
        if ($FeeBooked) {
            # The fee has been booked as a charge and is already included in the
            # remaining amount, so it is shown for information only.
            $blocks.Add(@{ Type = 'Paragraph'; Text = "Varav påminnelseavgift: $(Format-LedgerAmount -Value $Fee) kr" })
        }
        else {
            $blocks.Add(@{ Type = 'Paragraph'; Text = "Påminnelseavgift: $(Format-LedgerAmount -Value $Fee) kr" })
            $amountToPay = [Math]::Round($amountToPay + $Fee, 2)
        }
    }
    $blocks.Add(@{ Type = 'Heading'; Level = 2; Text = "Att betala: $(Format-LedgerAmount -Value $amountToPay) kr" })

    # Payment information
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
    if ($Invoice.OcrReference) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "OCR-referens: $($Invoice.OcrReference)" })
    }
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Har betalning redan skett ber vi dig bortse från denna påminnelse." })

    $blocks
}
