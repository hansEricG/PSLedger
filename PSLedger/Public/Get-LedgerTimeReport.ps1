<#
.SYNOPSIS
Summarises reported time per customer, project, resource, month or week.

.DESCRIPTION
Returns one object per group with:
- Hours, BillableHours and NonBillableHours
- BillableAmount: billable hours x rate
- InvoicedHours and InvoicedAmount: billable time on a (non-credited) invoice
- OpenHours and OpenAmount: billable time not yet invoiced (upparbetad men ej
  fakturerad intäkt)
- Cost: hours x the resource's cost per hour (resources without a cost rate
  count as 0)
- Margin: BillableAmount - Cost

The OpenAmount at the end of a fiscal year is the basis for booking work in
progress (upparbetad ej fakturerad intäkt, account 1620) with
Add-LedgerAccrual.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER From
Optional. Only time on or after this date.

.PARAMETER To
Optional. Only time on or before this date.

.PARAMETER GroupBy
One or more of 'Customer', 'Project', 'Resource', 'Month' and 'Week'.
Defaults to 'Project'.

.PARAMETER CustomerNumber
Optional. Only this customer's time.

.PARAMETER Project
Optional. Only time on this project.

.PARAMETER Resource
Optional. Only this resource's time.

.EXAMPLE
Get-LedgerTimeReport -From 2024-03-01 -To 2024-03-31 -GroupBy Resource | Format-Table

Shows each person's hours, billable share and margin for March.

.EXAMPLE
Get-LedgerTimeReport -To 2024-12-31 -GroupBy Customer | Where-Object OpenAmount -gt 0 | Format-Table CustomerName, OpenHours, OpenAmount

Lists the work in progress per customer at year end, as a basis for booking
upparbetad ej fakturerad intäkt.
#>
function Get-LedgerTimeReport {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [datetime]$From,

        [Parameter()]
        [datetime]$To,

        [Parameter()]
        [ValidateSet('Customer', 'Project', 'Resource', 'Month', 'Week')]
        [string[]]$GroupBy = @('Project'),

        [Parameter()]
        [string]$CustomerNumber,

        [Parameter()]
        [string]$Project,

        [Parameter()]
        [string]$Resource
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $params = @{ JournalPath = $JournalPath }
    foreach ($name in 'From', 'To', 'CustomerNumber', 'Project', 'Resource') {
        if ($PSBoundParameters.ContainsKey($name)) { $params[$name] = $PSBoundParameters[$name] }
    }
    $entries = @(Get-LedgerTimeEntry @params)
    if (-not $entries) { return }

    $costRates = @{}
    foreach ($r in @(Read-LedgerTimeResources -JournalPath $JournalPath)) {
        $costRates[$r.ResourceId] = if ($null -ne $r.CostRate) { [decimal]$r.CostRate } else { [decimal]0 }
    }

    $keyOf = {
        param($e)
        foreach ($g in $GroupBy) {
            switch ($g) {
                'Customer' { $e.CustomerNumber }
                'Project' { $e.Project }
                'Resource' { $e.Resource }
                'Month' { $e.Date.ToString('yyyy-MM') }
                'Week' { '{0}-W{1:00}' -f [System.Globalization.ISOWeek]::GetYear($e.Date), [System.Globalization.ISOWeek]::GetWeekOfYear($e.Date) }
            }
        }
    }

    $groups = $entries | Group-Object { (& $keyOf $_) -join "`t" } | Sort-Object Name
    foreach ($group in $groups) {
        $first = $group.Group[0]
        $result = [ordered]@{}
        foreach ($g in $GroupBy) {
            switch ($g) {
                'Customer' { $result.CustomerNumber = $first.CustomerNumber; $result.CustomerName = $first.CustomerName }
                'Project' { $result.Project = $first.Project; $result.ProjectName = $first.ProjectName }
                'Resource' { $result.Resource = $first.Resource; $result.ResourceName = $first.ResourceName }
                'Month' { $result.Month = $first.Date.ToString('yyyy-MM') }
                'Week' { $result.Week = '{0}-W{1:00}' -f [System.Globalization.ISOWeek]::GetYear($first.Date), [System.Globalization.ISOWeek]::GetWeekOfYear($first.Date) }
            }
        }

        $sum = @{ Hours = [decimal]0; Billable = [decimal]0; BillableAmount = [decimal]0; InvoicedHours = [decimal]0
            InvoicedAmount = [decimal]0; OpenHours = [decimal]0; OpenAmount = [decimal]0; Cost = [decimal]0 }
        foreach ($e in $group.Group) {
            $sum.Hours += $e.Hours
            $sum.Cost += [decimal]$e.Hours * $(if ($costRates.ContainsKey($e.Resource)) { $costRates[$e.Resource] } else { [decimal]0 })
            if (-not $e.Billable) { continue }
            $sum.Billable += $e.Hours
            $sum.BillableAmount += $e.Amount
            if ($e.Status -eq 'Invoiced') { $sum.InvoicedHours += $e.Hours; $sum.InvoicedAmount += $e.Amount }
            else { $sum.OpenHours += $e.Hours; $sum.OpenAmount += $e.Amount }
        }
        $result.Hours = $sum.Hours
        $result.BillableHours = $sum.Billable
        $result.NonBillableHours = $sum.Hours - $sum.Billable
        $result.BillableAmount = [Math]::Round($sum.BillableAmount, 2)
        $result.InvoicedHours = $sum.InvoicedHours
        $result.InvoicedAmount = [Math]::Round($sum.InvoicedAmount, 2)
        $result.OpenHours = $sum.OpenHours
        $result.OpenAmount = [Math]::Round($sum.OpenAmount, 2)
        $result.Cost = [Math]::Round($sum.Cost, 2)
        $result.Margin = [Math]::Round($sum.BillableAmount - $sum.Cost, 2)
        [PSCustomObject]$result
    }
}
