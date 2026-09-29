<#
.SYNOPSIS
Adds a project that time can be reported on.

.DESCRIPTION
Projects are stored in the journal's time/projects.txt. A project normally
belongs to a customer; its time is invoiced to that customer. A project
without a customer is internal (e.g. administration or sales) and its time is
never billable.

The hourly rate of a project takes precedence over the customer's hourly rate
(see Add-LedgerCustomer -HourlyRate).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER ProjectNumber
A unique project number, e.g. '1001'.

.PARAMETER Name
The project name, shown on invoices and reports.

.PARAMETER CustomerNumber
Optional. The customer the project is invoiced to.

.PARAMETER HourlyRate
Optional hourly rate (net, excluding VAT) for the project.

.EXAMPLE
Add-LedgerProject -ProjectNumber '1001' -Name 'Nytt kundportal' -CustomerNumber '10'

Adds a project for Volvo AB, billed at the customer's hourly rate.

.EXAMPLE
Add-LedgerProject -ProjectNumber '1002' -Name 'Arkitekturstöd' -CustomerNumber '10' -HourlyRate 1350
Add-LedgerProject -ProjectNumber '9000' -Name 'Intern administration'

Adds a project with its own rate and an internal project for non-billable time.
#>
function Add-LedgerProject {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [ValidatePattern('^[^\t\r\n]+$')]
        [string]$ProjectNumber,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$CustomerNumber,

        [Parameter()]
        [ValidateRange(0, 1000000)]
        [decimal]$HourlyRate
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $projects = @(Read-LedgerProjects -JournalPath $JournalPath)
    if ($projects | Where-Object ProjectNumber -eq $ProjectNumber) {
        throw "Project '$ProjectNumber' already exists."
    }
    if ($CustomerNumber -and -not (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber $CustomerNumber)) {
        throw "Customer '$CustomerNumber' does not exist."
    }

    $projects += [PSCustomObject]@{
        ProjectNumber  = $ProjectNumber
        Name           = $Name
        CustomerNumber = $CustomerNumber
        HourlyRate     = if ($PSBoundParameters.ContainsKey('HourlyRate')) { $HourlyRate } else { $null }
        Status         = 'Active'
    }

    if ($PSCmdlet.ShouldProcess($ProjectNumber, 'Add project')) {
        Save-LedgerProjects -JournalPath $JournalPath -Projects $projects
    }
}
