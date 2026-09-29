<#
.SYNOPSIS
Lists reported time.

.DESCRIPTION
Returns one object per time entry with EntryId, Date, Resource, ResourceName,
Project, ProjectName, CustomerNumber, CustomerName, Hours, Billable, Rate,
Amount (hours x rate for billable time), Text, Status and InvoiceNumber.

Status is 'Invoiced' while the entry is on an invoice that has not been
credited, otherwise 'Open'.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER EntryId
Optional. Returns only these entries.

.PARAMETER From
Optional. Only entries on or after this date.

.PARAMETER To
Optional. Only entries on or before this date.

.PARAMETER Project
Optional. Only entries on this project.

.PARAMETER CustomerNumber
Optional. Only entries for this customer.

.PARAMETER Resource
Optional. Only entries for this resource.

.PARAMETER Status
Optional. 'Open' or 'Invoiced'.

.PARAMETER Billable
Only billable entries.

.EXAMPLE
Get-LedgerTimeEntry -From 2024-03-01 -To 2024-03-31 | Format-Table Date, Resource, Project, Hours, Text

Lists the time reported in March.

.EXAMPLE
Get-LedgerTimeEntry -CustomerNumber 10 -Status Open -Billable | Measure-Object -Property Amount -Sum

Shows the value of Volvo AB's time that has not been invoiced yet.
#>
function Get-LedgerTimeEntry {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [int[]]$EntryId,

        [Parameter()]
        [datetime]$From,

        [Parameter()]
        [datetime]$To,

        [Parameter()]
        [string]$Project,

        [Parameter()]
        [string]$CustomerNumber,

        [Parameter()]
        [string]$Resource,

        [Parameter()]
        [ValidateSet('Open', 'Invoiced')]
        [string]$Status,

        [Parameter()]
        [switch]$Billable
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $entries = @(Read-LedgerTimeEntries -JournalPath $JournalPath)
    if (-not $entries) { return }
    $context = Get-LedgerTimeContext -JournalPath $JournalPath
    $invoiceStatus = Get-LedgerTimeInvoiceStatusMap -JournalPath $JournalPath

    foreach ($e in $entries) {
        if ($EntryId -and $e.EntryId -notin $EntryId) { continue }
        if ($PSBoundParameters.ContainsKey('From') -and $e.Date -lt $From.Date) { continue }
        if ($PSBoundParameters.ContainsKey('To') -and $e.Date -gt $To.Date) { continue }
        if ($Project -and $e.ProjectNumber -ne $Project) { continue }
        if ($CustomerNumber -and $e.CustomerNumber -ne $CustomerNumber) { continue }
        if ($Resource -and $e.ResourceId -ne $Resource) { continue }
        if ($Billable -and -not $e.Billable) { continue }
        $out = ConvertTo-LedgerTimeEntryOutput -Entry $e -Context $context -InvoiceStatus $invoiceStatus
        if ($Status -and $out.Status -ne $Status) { continue }
        $out
    }
}
