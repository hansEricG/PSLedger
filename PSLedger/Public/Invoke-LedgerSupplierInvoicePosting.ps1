<#
.SYNOPSIS
Posts a supplier invoice to the ledger, creating a bookkeeping verification.

.DESCRIPTION
Creates a verification for a Draft supplier invoice: each cost account is debited
with its net amount, each input-VAT account is debited with its VAT, and the
payable account (2440 Leverantörsskulder) is credited with the gross total. The
fiscal year is resolved from the invoice date unless one is supplied explicitly.

After posting, the invoice status becomes 'Booked' and the verification number
and fiscal year are recorded on the invoice so the payable can always be
reconciled against the ledger.

The operation refuses to run twice for the same invoice (an already-posted
invoice throws).

Before writing, the command saves an immutable posting plan under
supplierinvoices/posting/ with a reserved verification number and content
hashes. If interrupted, run the same command again: it reuses and, if needed,
seals the matching saved verification before completing the invoice status.
Changed inputs, a conflicting verification or integrity errors stop recovery.
A matching existing verification may be completed after its fiscal year has
closed; a new verification is never created in a closed year.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the supplier invoice to post.

.PARAMETER FiscalYear
Optional. The fiscal year to post the verification into. If omitted, the fiscal
year containing the invoice date is used.

.PARAMETER PassThru
If specified, returns the updated supplier invoice object. By default the command
produces no output.

.EXAMPLE
Invoke-LedgerSupplierInvoicePosting -JournalPath .\MinFirma.ledger -InvoiceNumber 1

Posts supplier invoice 1, creating a verification such as:
  5010 Lokalhyra          +8000
  2640 Ingående moms      +2000
  2440 Leverantörsskulder -10000

.EXAMPLE
Get-LedgerSupplierInvoice -Status Draft | ForEach-Object { Invoke-LedgerSupplierInvoicePosting -InvoiceNumber $_.InvoiceNumber }

Posts every draft supplier invoice in the current journal.
#>
function Invoke-LedgerSupplierInvoicePosting {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared invoice posting writer performs ShouldProcess; WhatIf and Confirm are forwarded.')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$InvoiceNumber,

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [switch]$PassThru
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $journalLock = $null
        try {
            $journalLock = Enter-LedgerJournalLock -JournalPath $JournalPath
            Assert-LedgerJournalSchema -Path $JournalPath -Write
            $shouldProcess = @{}
            foreach ($name in 'WhatIf', 'Confirm') {
                if ($PSBoundParameters.ContainsKey($name)) { $shouldProcess[$name] = $PSBoundParameters[$name] }
            }
            $posted = Invoke-LedgerInvoicePostingOperation -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber `
                -FiscalYear $FiscalYear @shouldProcess -Supplier
            if ($posted -and $PassThru) {
                Get-LedgerSupplierInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
            }
        }
        finally { Exit-LedgerJournalLock -Lock $journalLock }
    }
}
