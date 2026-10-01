<#
.SYNOPSIS
Lists reported time.

.DESCRIPTION
Returns one object per time entry with EntryId, Date, ResourceId, ResourceName,
ProjectNumber, ProjectName, CustomerNumber, CustomerName, Hours, Billable, Rate,
Amount (hours x rate for billable time), Text, Status and InvoiceNumber.

Status is 'Invoiced' while the entry is on an invoice that has not been
credited, otherwise 'Open'.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER EntryId
Optional. Returns only these entries.

.PARAMETER FromDate
Optional. Only entries on or after this date.

.PARAMETER ToDate
Optional. Only entries on or before this date.

.PARAMETER ProjectNumber
Optional. Only entries on this project.

.PARAMETER CustomerNumber
Optional. Only entries for this customer.

.PARAMETER ResourceId
Optional. Only entries for this resource.

.PARAMETER Status
Optional. 'Open' or 'Invoiced'.

.PARAMETER Billable
Optional. $true for billable entries only, $false for non-billable entries only.

.EXAMPLE
Get-LedgerTimeEntry -FromDate 2024-03-01 -ToDate 2024-03-31 | Format-Table Date, ResourceId, ProjectNumber, Hours, Text

Lists the time reported in March.

.EXAMPLE
Get-LedgerTimeEntry -CustomerNumber 10 -Status Open -Billable $true | Measure-Object -Property Amount -Sum

Shows the value of Volvo AB's time that has not been invoiced yet.
#>
function Get-LedgerTimeEntry {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [int[]]$EntryId,

        [Parameter()]
        [datetime]$FromDate,

        [Parameter()]
        [datetime]$ToDate,

        [Parameter()]
        [string]$ProjectNumber,

        [Parameter()]
        [string]$CustomerNumber,

        [Parameter()]
        [string]$ResourceId,

        [Parameter()]
        [ValidateSet('Open', 'Invoiced')]
        [string]$Status,

        [Parameter()]
        [Nullable[bool]]$Billable
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $entries = @(Read-LedgerTimeEntries -JournalPath $JournalPath)
    if (-not $entries) { return }
    $context = Get-LedgerTimeContext -JournalPath $JournalPath
    $invoiceStatus = Get-LedgerTimeInvoiceStatusMap -JournalPath $JournalPath

    foreach ($e in $entries) {
        if ($EntryId -and $e.EntryId -notin $EntryId) { continue }
        if ($PSBoundParameters.ContainsKey('FromDate') -and $e.Date -lt $FromDate.Date) { continue }
        if ($PSBoundParameters.ContainsKey('ToDate') -and $e.Date -gt $ToDate.Date) { continue }
        if ($ProjectNumber -and $e.ProjectNumber -ne $ProjectNumber) { continue }
        if ($CustomerNumber -and $e.CustomerNumber -ne $CustomerNumber) { continue }
        if ($ResourceId -and $e.ResourceId -ne $ResourceId) { continue }
        if ($null -ne $Billable -and [bool]$e.Billable -ne $Billable) { continue }
        $out = ConvertTo-LedgerTimeEntryOutput -Entry $e -Context $context -InvoiceStatus $invoiceStatus
        if ($Status -and $out.Status -ne $Status) { continue }
        $out
    }
}
