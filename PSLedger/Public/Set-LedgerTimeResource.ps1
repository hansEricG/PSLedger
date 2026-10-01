<#
.SYNOPSIS
Updates a time resource.

.DESCRIPTION
Changes the name, employee/supplier link or cost per hour of a resource, or
makes it the default resource for new time entries. Only the parameters you
supply are changed.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER ResourceId
The id of the resource to update.

.PARAMETER Name
The new name.

.PARAMETER EmployeeNumber
The employee the resource is linked to. Pass an empty string to clear it.

.PARAMETER SupplierNumber
The supplier the resource is linked to. Pass an empty string to clear it.

.PARAMETER CostRate
The new cost per hour. Pass 0 to clear it.

.PARAMETER Default
Makes this the default resource for new time entries.

.PARAMETER PassThru
If specified, returns the created/updated time resource. By default the command
produces no output.

.EXAMPLE
Set-LedgerTimeResource -ResourceId 'BK' -CostRate 900

Raises the subcontractor's cost per hour to 900 kr.

.EXAMPLE
Set-LedgerTimeResource -ResourceId 'AA' -Default

Makes Anna Andersson the default resource.
#>
function Set-LedgerTimeResource {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$ResourceId,

        [Parameter()]
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
        [switch]$Default,

        [Parameter()]
        [switch]$PassThru
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

        $resources = @(Read-LedgerTimeResources -JournalPath $JournalPath)
        $resource = $resources | Where-Object ResourceId -eq $ResourceId | Select-Object -First 1
        if (-not $resource) { throw "Time resource '$ResourceId' does not exist." }

        if ($PSBoundParameters.ContainsKey('Name')) { $resource.Name = $Name }
        if ($PSBoundParameters.ContainsKey('EmployeeNumber')) {
            if ($EmployeeNumber -and -not (Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber $EmployeeNumber)) {
                throw "Employee '$EmployeeNumber' does not exist."
            }
            $resource.EmployeeNumber = $EmployeeNumber
        }
        if ($PSBoundParameters.ContainsKey('SupplierNumber')) {
            if ($SupplierNumber -and -not (Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber $SupplierNumber)) {
                throw "Supplier '$SupplierNumber' does not exist."
            }
            $resource.SupplierNumber = $SupplierNumber
        }
        if ($PSBoundParameters.ContainsKey('CostRate')) { $resource.CostRate = if ($CostRate -gt 0) { $CostRate } else { $null } }
        if ($Default) {
            foreach ($r in $resources) { $r.IsDefault = ($r.ResourceId -eq $ResourceId) }
        }

        if ($PSCmdlet.ShouldProcess($ResourceId, 'Update time resource')) {
            Save-LedgerTimeResources -JournalPath $JournalPath -Resources $resources
            if ($PassThru) {
                Get-LedgerTimeResource -JournalPath $JournalPath -ResourceId $ResourceId
            }
        }
    }
}
