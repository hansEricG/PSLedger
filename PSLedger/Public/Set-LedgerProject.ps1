<#
.SYNOPSIS
Updates a project.

.DESCRIPTION
Changes the name, customer, hourly rate or status of a project. Only the
parameters you supply are changed. A closed project accepts no new time.

Changing the hourly rate affects new time entries only; entries already
reported keep the rate they were registered with (change them with
Set-LedgerTimeEntry -Rate if needed).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER ProjectNumber
The number of the project to update.

.PARAMETER Name
The new name.

.PARAMETER CustomerNumber
The new customer. Pass an empty string to make the project internal. Not
allowed while the project has time entries.

.PARAMETER HourlyRate
The new hourly rate. Pass 0 to clear it so the customer's rate applies.

.PARAMETER Status
'Active' or 'Closed'.

.PARAMETER PassThru
If specified, returns the created/updated project. By default the command
produces no output.

.EXAMPLE
Set-LedgerProject -ProjectNumber '1001' -HourlyRate 1200

Raises the project's hourly rate for new time.

.EXAMPLE
Set-LedgerProject -ProjectNumber '1001' -Status Closed

Closes the project when it is finished.
#>
function Set-LedgerProject {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$ProjectNumber,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$CustomerNumber,

        [Parameter()]
        [ValidateRange(0, 1000000)]
        [decimal]$HourlyRate,

        [Parameter()]
        [ValidateSet('Active', 'Closed')]
        [string]$Status,

        [Parameter()]
        [switch]$PassThru
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

        $projects = @(Read-LedgerProjects -JournalPath $JournalPath)
        $project = $projects | Where-Object ProjectNumber -eq $ProjectNumber | Select-Object -First 1
        if (-not $project) { throw "Project '$ProjectNumber' does not exist." }

        if ($PSBoundParameters.ContainsKey('Name')) { $project.Name = $Name }
        if ($PSBoundParameters.ContainsKey('CustomerNumber') -and $CustomerNumber -ne $project.CustomerNumber) {
            if ($CustomerNumber -and -not (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber $CustomerNumber)) {
                throw "Customer '$CustomerNumber' does not exist."
            }
            if (Read-LedgerTimeEntries -JournalPath $JournalPath | Where-Object ProjectNumber -eq $ProjectNumber) {
                throw "Project '$ProjectNumber' has time entries; its customer cannot be changed."
            }
            $project.CustomerNumber = $CustomerNumber
        }
        if ($PSBoundParameters.ContainsKey('HourlyRate')) { $project.HourlyRate = if ($HourlyRate -gt 0) { $HourlyRate } else { $null } }
        if ($PSBoundParameters.ContainsKey('Status')) { $project.Status = $Status }

        if ($PSCmdlet.ShouldProcess($ProjectNumber, 'Update project')) {
            Save-LedgerProjects -JournalPath $JournalPath -Projects $projects
            if ($PassThru) {
                Get-LedgerProject -JournalPath $JournalPath -ProjectNumber $ProjectNumber
            }
        }
    }
}
