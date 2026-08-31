<#
.SYNOPSIS
Reports the open accounts receivable (kundreskontra) with an aging breakdown.

.DESCRIPTION
Returns the outstanding customer invoices — those that have been posted but are
not fully paid (status Booked or Partial) — with the number of days each is
overdue relative to a reference date and an aging bucket (Current, 1-30, 31-60,
61-90 or 90+ days past due).

By default one object is returned per open invoice. With -Summary, one object is
returned per aging bucket with the invoice count and the total outstanding amount,
which is useful for a quick overview of how much is overdue.

The sum of the outstanding amounts reconciles against the balance of the
receivable account (1510) in the general ledger.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER AsOf
The reference date used to calculate how many days each invoice is overdue.
Defaults to today.

.PARAMETER CustomerNumber
Optional. If specified, only invoices for this customer are included.

.PARAMETER Summary
Return one row per aging bucket (with Count and Total) instead of one row per
invoice.

.EXAMPLE
Get-LedgerAccountsReceivable -JournalPath .\MinFirma.ledger

Lists every open invoice with its remaining amount, days overdue and aging bucket.

.EXAMPLE
Get-LedgerAccountsReceivable -AsOf '2024-05-01' -Summary

Shows the outstanding total per aging bucket as of 1 May 2024.
#>
function Get-LedgerAccountsReceivable {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [datetime]$AsOf = (Get-Date).Date,

        [Parameter()]
        [string]$CustomerNumber,

        [Parameter()]
        [switch]$Summary
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $bucketOrder = @('Current', '1-30', '31-60', '61-90', '90+')

    $open = @(Get-LedgerInvoice -JournalPath $JournalPath -Unpaid)
    if ($PSBoundParameters.ContainsKey('CustomerNumber')) {
        $open = @($open | Where-Object { $_.CustomerNumber -eq $CustomerNumber })
    }

    $rows = foreach ($inv in $open) {
        $daysOverdue = [int]([datetime]$AsOf - [datetime]$inv.DueDate).TotalDays
        if ($daysOverdue -lt 0) { $daysOverdue = 0 }
        $bucket =
            if ($daysOverdue -le 0) { 'Current' }
            elseif ($daysOverdue -le 30) { '1-30' }
            elseif ($daysOverdue -le 60) { '31-60' }
            elseif ($daysOverdue -le 90) { '61-90' }
            else { '90+' }

        [PSCustomObject]@{
            InvoiceNumber   = $inv.InvoiceNumber
            CustomerNumber  = $inv.CustomerNumber
            CustomerName    = $inv.CustomerName
            InvoiceDate     = $inv.InvoiceDate
            DueDate         = $inv.DueDate
            Total           = $inv.Total
            RemainingAmount = $inv.RemainingAmount
            DaysOverdue     = $daysOverdue
            AgingBucket     = $bucket
            Status          = $inv.Status
        }
    }
    $rows = @($rows)

    if (-not $Summary) {
        return ($rows | Sort-Object DueDate, InvoiceNumber)
    }

    foreach ($bucket in $bucketOrder) {
        $inBucket = @($rows | Where-Object { $_.AgingBucket -eq $bucket })
        $total = ($inBucket | Measure-Object -Property RemainingAmount -Sum).Sum
        if (-not $total) { $total = [decimal]0 }
        [PSCustomObject]@{
            AgingBucket = $bucket
            Count       = $inBucket.Count
            Total       = [Math]::Round([decimal]$total, 2)
        }
    }
}
