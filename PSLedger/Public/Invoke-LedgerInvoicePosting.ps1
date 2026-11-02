<#
.SYNOPSIS
Posts a customer invoice to the ledger, creating a bookkeeping verification.

.DESCRIPTION
Creates a verification for a Draft invoice: the accounts-receivable account is
debited with the gross total, each revenue account is credited with its net
amount and each VAT account is credited with its VAT. The fiscal year is resolved
from the invoice date unless one is supplied explicitly.

After posting, the invoice status becomes 'Booked' and the verification number
and fiscal year are recorded on the invoice so the receivable can always be
reconciled against the ledger.

Before writing, the command saves an immutable posting plan under
invoices/posting/ with a reserved verification number and content hashes.
If interrupted, run the same command again: it reuses and, if needed, seals
the matching saved verification before completing the invoice status. Changed
inputs, a conflicting verification or integrity errors stop recovery.

A matching existing verification may be completed even after its fiscal year
has closed; a new verification is never created in a closed year. Already-posted
invoices still throw, so repeating a completed operation cannot post it twice.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER InvoiceNumber
The number of the invoice to post.

.PARAMETER FiscalYear
Optional. The fiscal year to post the verification into. If omitted, the fiscal
year containing the invoice date is used.

.PARAMETER PassThru
If specified, returns the updated invoice object. By default the command
produces no output.

.EXAMPLE
Invoke-LedgerInvoicePosting -JournalPath .\MinFirma.ledger -InvoiceNumber 1

Posts invoice 1, creating a verification such as:
  1510 Kundfordringar  +12500
  3010 Försäljning      -10000
  2610 Utgående moms     -2500

.EXAMPLE
Get-LedgerInvoice -Status Draft | ForEach-Object { Invoke-LedgerInvoicePosting -InvoiceNumber $_.InvoiceNumber }

Posts every draft invoice in the current journal.
#>
function Invoke-LedgerInvoicePosting {
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
                -FiscalYear $FiscalYear @shouldProcess
            if ($posted -and $PassThru) {
                Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber
            }
        }
        finally { Exit-LedgerJournalLock -Lock $journalLock }
    }
}
