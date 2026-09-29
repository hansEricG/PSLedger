<#
.SYNOPSIS
Adds a time resource (a person who reports time) to the journal.

.DESCRIPTION
A time resource is anyone whose hours are reported and invoiced: you, an
employee or a subcontractor (underkonsult). Resources are stored in the
journal's time/resources.txt.

A resource may be linked to an employee (see Add-LedgerEmployee) or to a
supplier (see Add-LedgerSupplier) and may have a cost per hour, which
Get-LedgerTimeReport uses to compute the margin. The first resource added
becomes the default resource used by Add-LedgerTimeEntry when -Resource is
omitted.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER ResourceId
A short unique id for the resource, e.g. initials ('AA').

.PARAMETER Name
The name shown on invoices and reports.

.PARAMETER EmployeeNumber
Optional. Links the resource to an employee in the employee register.

.PARAMETER SupplierNumber
Optional. Links the resource to a supplier, e.g. a subcontractor's company.

.PARAMETER CostRate
Optional cost per hour (e.g. the subcontractor's hourly price, or salary plus
employer contributions per hour) used for margin in Get-LedgerTimeReport.

.PARAMETER Default
Makes this the default resource for new time entries.

.EXAMPLE
Add-LedgerTimeResource -ResourceId 'AA' -Name 'Anna Andersson'

Adds yourself as the (default) resource.

.EXAMPLE
Add-LedgerTimeResource -ResourceId 'BK' -Name 'Bengt Karlsson' -SupplierNumber '200' -CostRate 850

Adds a subcontractor whose company is supplier 200 and who costs 850 kr per
hour.
#>
function Add-LedgerTimeResource {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [ValidatePattern('^[^\t\r\n]+$')]
        [string]$ResourceId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$EmployeeNumber,

        [Parameter()]
        [string]$SupplierNumber,

        [Parameter()]
        [ValidateRange(0, 1000000)]
        [decimal]$CostRate,

        [Parameter()]
        [switch]$Default
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $resources = @(Read-LedgerTimeResources -JournalPath $JournalPath)
    if ($resources | Where-Object ResourceId -eq $ResourceId) {
        throw "Time resource '$ResourceId' already exists."
    }
    if ($EmployeeNumber -and -not (Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber $EmployeeNumber)) {
        throw "Employee '$EmployeeNumber' does not exist."
    }
    if ($SupplierNumber -and -not (Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber $SupplierNumber)) {
        throw "Supplier '$SupplierNumber' does not exist."
    }

    $isDefault = $Default -or -not $resources
    if ($isDefault) { foreach ($r in $resources) { $r.IsDefault = $false } }
    $resources += [PSCustomObject]@{
        ResourceId     = $ResourceId
        Name           = $Name
        EmployeeNumber = $EmployeeNumber
        SupplierNumber = $SupplierNumber
        CostRate       = if ($PSBoundParameters.ContainsKey('CostRate')) { $CostRate } else { $null }
        IsDefault      = [bool]$isDefault
    }

    if ($PSCmdlet.ShouldProcess($ResourceId, 'Add time resource')) {
        Save-LedgerTimeResources -JournalPath $JournalPath -Resources $resources
    }
}
