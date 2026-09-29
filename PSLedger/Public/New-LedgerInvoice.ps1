<#
.SYNOPSIS
Creates a new customer invoice (kundfaktura) in the journal.

.DESCRIPTION
Creates a sequentially numbered invoice file (inv0001.txt, inv0002.txt, etc.) in
the journal's 'invoices/' directory. An invoice records what is billed to a
customer but is not yet posted to the ledger — use Invoke-LedgerInvoicePosting to
create the bookkeeping verification, and Add-LedgerInvoicePayment to register
payments.

Invoices live at the journal level (not inside a fiscal year) because an invoice
may be paid in a later fiscal year than the one it was issued in.

Each row describes a revenue line with a net amount (excluding VAT), an optional
VAT rate and the account VAT is booked to. The gross invoice total is the sum of
all net amounts plus their VAT.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER CustomerNumber
The number of the customer being invoiced. Must exist in the customer register
(see Add-LedgerCustomer).

.PARAMETER Date
The invoice date. Defaults to today.

.PARAMETER DueDate
The date the invoice is due. If omitted, it is calculated from the invoice date
plus the customer's default payment terms.

.PARAMETER Description
A description of what is being invoiced.

.PARAMETER Rows
An array of hashtables describing the revenue rows. Each row must have:
- Account: the revenue account (e.g. '3010')
- Amount: the net amount excluding VAT (positive). May be omitted when
  Quantity and UnitPrice are given; it is then Quantity x UnitPrice rounded to
  öre. When all three are given they must agree.
and may optionally have:
- VatRate: the VAT rate as a decimal (e.g. 0.25 for 25%); defaults to 0
- VatAccount: the account output VAT is booked to (e.g. '2610'); required when
  VatRate is greater than 0
- Description: the text shown on the invoice (e.g. 'Systemutveckling mars')
- Quantity: the number of units (e.g. 32.5)
- Unit: the unit (e.g. 'h', 'st')
- UnitPrice: the net price per unit excluding VAT (à-pris)

Rows without a Description are shown with the account name on the exported
invoice.

.PARAMETER ReceivableAccount
The accounts-receivable account the invoice total is booked to when posted.
Defaults to '1510' (Kundfordringar).

.PARAMETER PassThru
If specified, returns the created invoice object. By default the command
produces no output.

.EXAMPLE
$rows = @(
    @{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' }
)
New-LedgerInvoice -JournalPath .\MinFirma.ledger -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsultarvode mars' -Rows $rows

Creates an invoice for 10 000 kr plus 25% VAT to customer 10.

.EXAMPLE
$rows = @(
    @{ Account = '3010'; Amount = 8000; VatRate = 0.25; VatAccount = '2610' }
    @{ Account = '3590'; Amount = 500;  VatRate = 0;     VatAccount = '' }
)
New-LedgerInvoice -JournalPath .\MinFirma.ledger -CustomerNumber 'K012' -Description 'Konsultarvode och utlägg' -DueDate '2024-05-01' -Rows $rows -PassThru

Creates an invoice with a VAT-liable service row and a VAT-free expense row, an
explicit due date, and returns the created invoice object.

.EXAMPLE
$rows = @(
    @{ Account = '3010'; Description = 'Systemutveckling mars'; Quantity = 32.5; Unit = 'h'; UnitPrice = 1100; VatRate = 0.25; VatAccount = '2610' }
    @{ Account = '3010'; Description = 'Projektledning mars'; Quantity = 6; Unit = 'h'; UnitPrice = 1250; VatRate = 0.25; VatAccount = '2610' }
)
New-LedgerInvoice -CustomerNumber '10' -Date '2024-03-31' -Description 'Konsulttjänster mars 2024' -Rows $rows

Invoices hours with text, quantity and unit price to Volvo AB. The net amounts
(35 750 kr and 7 500 kr) are computed from quantity x unit price.
#>
function New-LedgerInvoice {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$CustomerNumber,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [datetime]$DueDate,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [hashtable[]]$Rows,

        [Parameter()]
        [string]$ReceivableAccount = '1510',

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    # Validate the customer exists.
    $customer = Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber $CustomerNumber
    if (-not $customer) {
        throw "Customer '$CustomerNumber' does not exist. Add it with Add-LedgerCustomer first."
    }

    # Validate and normalise rows.
    if ($Rows.Count -eq 0) {
        throw "An invoice must have at least one row."
    }
    $normalizedRows = foreach ($row in $Rows) {
        if (-not $row.ContainsKey('Account') -or [string]::IsNullOrWhiteSpace([string]$row.Account)) {
            throw "Each invoice row must have an Account."
        }
        $quantity = if ($row.ContainsKey('Quantity') -and $null -ne $row.Quantity -and "$($row.Quantity)" -ne '') { [decimal]$row.Quantity } else { $null }
        $unitPrice = if ($row.ContainsKey('UnitPrice') -and $null -ne $row.UnitPrice -and "$($row.UnitPrice)" -ne '') { [decimal]$row.UnitPrice } else { $null }
        $computed = if ($null -ne $quantity -and $null -ne $unitPrice) {
            [decimal]::Parse(([Math]::Round($quantity * $unitPrice, 2)).ToString('0.##', [cultureinfo]::InvariantCulture), [cultureinfo]::InvariantCulture)
        } else { $null }
        if ($row.ContainsKey('Amount') -and $null -ne $row.Amount) {
            $amount = [decimal]$row.Amount
            if ($null -ne $computed -and $computed -ne $amount) {
                throw "Invoice row for account $($row.Account): Amount $amount does not equal Quantity $quantity x UnitPrice $unitPrice ($computed)."
            }
        }
        elseif ($null -ne $computed) {
            $amount = $computed
        }
        else {
            throw "Each invoice row must have an Amount, or a Quantity and a UnitPrice."
        }
        if ($amount -le 0) {
            throw "Invoice row amount for account $($row.Account) must be greater than zero."
        }
        $vatRate = if ($row.ContainsKey('VatRate') -and $row.VatRate) { [decimal]$row.VatRate } else { [decimal]0 }
        $vatAccount = if ($row.ContainsKey('VatAccount')) { [string]$row.VatAccount } else { '' }
        if ($vatRate -gt 0 -and [string]::IsNullOrWhiteSpace($vatAccount)) {
            throw "Row for account $($row.Account) has VatRate $vatRate but no VatAccount."
        }
        [PSCustomObject]@{
            Account     = [string]$row.Account
            Amount      = $amount
            VatRate     = $vatRate
            VatAccount  = $vatAccount
            VatAmount   = [Math]::Round($amount * $vatRate, 2)
            Description = if ($row.ContainsKey('Description')) { [string]$row.Description } else { '' }
            Quantity    = $quantity
            Unit        = if ($row.ContainsKey('Unit')) { [string]$row.Unit } else { '' }
            UnitPrice   = $unitPrice
        }
    }
    $normalizedRows = @($normalizedRows)

    # Calculate the due date from customer payment terms when not supplied.
    if (-not $PSBoundParameters.ContainsKey('DueDate')) {
        $DueDate = $Date.AddDays($customer.PaymentTermsDays)
    }

    $invoiceDir = Get-LedgerInvoiceDirectory -JournalPath $JournalPath -Create

    # Determine the next invoice number by scanning existing files.
    $existing = Get-ChildItem -Path $invoiceDir -Filter 'inv*.txt' -File -ErrorAction SilentlyContinue
    if ($existing) {
        $maxNum = $existing |
            ForEach-Object { if ($_.BaseName -match '^inv(\d+)$') { [int]$Matches[1] } } |
            Measure-Object -Maximum |
            Select-Object -ExpandProperty Maximum
        $nextNum = $maxNum + 1
    }
    else {
        $nextNum = 1
    }

    $filePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $nextNum)

    $invoice = [PSCustomObject]@{
        InvoiceNumber      = $nextNum
        CustomerNumber     = $CustomerNumber
        InvoiceDate        = $Date
        DueDate            = $DueDate
        Description        = $Description
        Status             = 'Draft'
        ReceivableAccount  = $ReceivableAccount
        BookedVerification = $null
        BookedFiscalYear   = ''
        Rows               = $normalizedRows
        Payments           = @()
        FilePath           = $filePath
    }

    if ($PSCmdlet.ShouldProcess("Customer $CustomerNumber", "Create invoice $nextNum")) {
        Save-LedgerInvoiceFile -Invoice $invoice

        if ($PassThru) {
            Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $nextNum
        }
    }
}
