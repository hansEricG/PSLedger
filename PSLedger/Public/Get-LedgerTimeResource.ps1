<#
.SYNOPSIS
Lists the time resources (people who report time).

.DESCRIPTION
Returns one object per resource in time/resources.txt with ResourceId, Name,
EmployeeNumber, SupplierNumber, CostRate and IsDefault.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER ResourceId
Optional. Returns only this resource.

.EXAMPLE
Get-LedgerTimeResource

Lists all resources.

.EXAMPLE
Get-LedgerTimeResource | Where-Object SupplierNumber | Format-Table ResourceId, Name, CostRate

Lists the subcontractors and their cost per hour.
#>
function Get-LedgerTimeResource {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$ResourceId
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
    Read-LedgerTimeResources -JournalPath $JournalPath | Where-Object { -not $ResourceId -or $_.ResourceId -eq $ResourceId }
}
