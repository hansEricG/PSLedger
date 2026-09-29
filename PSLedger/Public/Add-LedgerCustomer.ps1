<#
.SYNOPSIS
Adds a customer to the journal's customer register.

.DESCRIPTION
Adds a customer entry to the journal's customers.txt file. Customers are the
recipients of invoices created with New-LedgerInvoice. Each customer has a
unique customer number and a name, plus optional organisation number, email and
default payment terms (in days) used to calculate invoice due dates.

The customers.txt file is tab-separated with the columns:
CustomerNumber, Name, OrgNumber, Email, PaymentTermsDays and the optional
HourlyRate.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER CustomerNumber
A unique identifier for the customer (e.g. '10', 'K001').

.PARAMETER Name
The customer's name.

.PARAMETER OrgNumber
Optional organisation number (e.g. '556677-8899').

.PARAMETER Email
Optional email address for the customer.

.PARAMETER PaymentTermsDays
Default number of days from invoice date until the invoice is due. Defaults to
30 days.

.PARAMETER HourlyRate
Optional default hourly rate (net, excluding VAT) for time reported against the
customer. A project's own hourly rate takes precedence (see Add-LedgerProject).

.EXAMPLE
Add-LedgerCustomer -JournalPath .\MinFirma.ledger -CustomerNumber '10' -Name 'Volvo AB'

Adds a customer with the default 30-day payment terms.

.EXAMPLE
Add-LedgerCustomer -JournalPath .\MinFirma.ledger -CustomerNumber 'K012' -Name 'Ericsson AB' -OrgNumber '556016-0680' -Email 'faktura@ericsson.se' -PaymentTermsDays 20

Adds a customer with full contact details and 20-day payment terms.

.EXAMPLE
Add-LedgerCustomer -CustomerNumber '20' -Name 'Scania CV AB' -HourlyRate 1150

Adds a customer whose reported hours are billed at 1 150 kr per hour.
#>
function Add-LedgerCustomer {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$CustomerNumber,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$OrgNumber,

        [Parameter()]
        [string]$Email,

        [Parameter()]
        [ValidateRange(0, 3650)]
        [int]$PaymentTermsDays = 30,

        [Parameter()]
        [ValidateRange(0, 1000000)]
        [decimal]$HourlyRate
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    if ($CustomerNumber -match "`t") {
        throw "CustomerNumber must not contain a tab character."
    }

    $CustomerFile = Join-Path $JournalPath 'customers.txt'

    if (Test-Path $CustomerFile) {
        foreach ($Line in (Get-Content $CustomerFile -Encoding UTF8)) {
            if ($Line -match "^$([regex]::Escape($CustomerNumber))`t") {
                throw "Customer '$CustomerNumber' already exists."
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($CustomerNumber, 'Add customer')) {
        $rateField = if ($PSBoundParameters.ContainsKey('HourlyRate')) { "`t$(Format-LedgerInvoiceAmount -Value $HourlyRate)" } else { '' }
        "$CustomerNumber`t$Name`t$OrgNumber`t$Email`t$PaymentTermsDays$rateField" |
            Add-Content -Path $CustomerFile -Encoding UTF8
    }
}
