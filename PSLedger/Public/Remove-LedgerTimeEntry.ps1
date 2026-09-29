<#
.SYNOPSIS
Removes reported time.

.DESCRIPTION
Deletes open time entries. Invoiced entries are locked; credit the invoice
with Add-LedgerCreditInvoice first to remove them.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER EntryId
The id of the entry to remove. Accepts pipeline input from Get-LedgerTimeEntry.

.EXAMPLE
Remove-LedgerTimeEntry -EntryId 42

Removes entry 42.

.EXAMPLE
Get-LedgerTimeEntry -From 2024-03-12 -To 2024-03-12 -Resource BK -Status Open | Remove-LedgerTimeEntry -WhatIf

Shows which of the subcontractor's entries on 12 March would be removed.
#>
function Remove-LedgerTimeEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$EntryId
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

        $entries = @(Read-LedgerTimeEntries -JournalPath $JournalPath)
        $entry = $entries | Where-Object EntryId -eq $EntryId | Select-Object -First 1
        if (-not $entry) { throw "Time entry $EntryId does not exist." }
        if (Test-LedgerTimeEntryInvoiced -Entry $entry -InvoiceStatus (Get-LedgerTimeInvoiceStatusMap -JournalPath $JournalPath)) {
            throw "Time entry $EntryId is on invoice $($entry.InvoiceNumber). Credit the invoice first to remove it."
        }

        if ($PSCmdlet.ShouldProcess("Time entry $EntryId ($($entry.Date.ToString('yyyy-MM-dd')), $($entry.Hours) h)", 'Remove time entry')) {
            $remaining = @($entries | Where-Object EntryId -ne $EntryId)
            Save-LedgerTimeEntries -JournalPath $JournalPath -Entries $remaining -Months $entry.Date.ToString('yyyy-MM')
        }
    }
}
