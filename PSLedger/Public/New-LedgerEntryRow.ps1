<#
.SYNOPSIS
Builds a single verification row for use with Add-LedgerEntry.

.DESCRIPTION
Creates a row hashtable in the format expected by Add-LedgerEntry's -Rows
parameter, without requiring you to remember the debit/credit sign convention.

Instead of a signed amount (positive for debit, negative for credit), you state
the intent explicitly with -Debit or -Credit and always supply a positive
amount. The command translates this into the signed Amount used on disk, so the
verification file format is unchanged.

Rows can be collected into an array and passed to Add-LedgerEntry -Rows, or
piped directly into Add-LedgerEntry.

.PARAMETER Debit
The account number to debit (positive side). The supplied amount is stored as a
positive value.

.PARAMETER Credit
The account number to credit (negative side). The supplied amount is stored as a
negative value.

.PARAMETER Amount
The transaction amount as a positive number. The sign is derived from whether
-Debit or -Credit was used.

.PARAMETER Objects
Optional hashtable of dimension-to-object references for this row
(e.g. @{ 1 = 'sthlm'; 2 = 'proj-a' }), matching the Objects key used by
Add-LedgerEntry.

.EXAMPLE
New-LedgerEntryRow -Debit '1910' 5000

Builds a row that debits account 1910 (Kassa) with 5000.

.EXAMPLE
$rows = @(
    New-LedgerEntryRow -Debit  '5010' 8000 -Objects @{ 1 = 'sthlm' }
    New-LedgerEntryRow -Credit '2440' 6400
    New-LedgerEntryRow -Credit '2640' 1600
)
Add-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Date '2024-03-20' -Description 'Hyra kontor' -Rows $rows

Records an office rent invoice with VAT split across accounts, tagging the cost
row with a cost-centre object, without juggling minus signs.

.EXAMPLE
New-LedgerEntryRow -Debit '1910' 5000
New-LedgerEntryRow -Credit '3010' 5000 |
    Add-LedgerEntry -FiscalYear '2024-01_2024-12' -Date '2024-03-15' -Description 'Kontantförsäljning'

Pipes rows straight into Add-LedgerEntry to record a cash sale.
#>
function New-LedgerEntryRow {
    [CmdletBinding(DefaultParameterSetName = 'Debit')]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Debit')]
        [string]$Debit,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Credit')]
        [string]$Credit,

        [Parameter(Mandatory, Position = 1)]
        [decimal]$Amount,

        [Parameter()]
        [hashtable]$Objects
    )

    if ($Amount -le 0) {
        throw "Amount must be a positive number (got $Amount). Use -Debit or -Credit to set the side."
    }

    if ($PSCmdlet.ParameterSetName -eq 'Debit') {
        $Account = $Debit
        $Signed = $Amount
    }
    else {
        $Account = $Credit
        $Signed = -$Amount
    }

    $Row = @{
        Account = $Account
        Amount  = $Signed
    }

    if ($Objects -and $Objects.Count -gt 0) {
        $Row.Objects = $Objects
    }

    $Row
}
