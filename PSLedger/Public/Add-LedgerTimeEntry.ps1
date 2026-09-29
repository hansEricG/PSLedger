<#
.SYNOPSIS
Reports time (tidrapportering) on a project or customer.

.DESCRIPTION
Adds a time entry to the journal's time/yyyy-MM.txt file for the month of the
date. The customer follows the project. The hourly rate is resolved when the
entry is registered and stored on it: -Rate, otherwise the project's rate,
otherwise the customer's rate. Later rate changes therefore do not change time
already reported.

Time on an internal project (without a customer) is never billable. Billable
time is invoiced with New-LedgerTimeInvoice.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Hours
The number of hours, as a decimal (7.5 or '7,5') or a duration ('7:30').
Must be greater than 0 and at most 24.

.PARAMETER Project
The project number. Either -Project or -CustomerNumber is required.

.PARAMETER CustomerNumber
The customer, for time that is not reported on a project.

.PARAMETER Date
The date the work was done. Defaults to today.

.PARAMETER Resource
The resource (person) who did the work. Defaults to the default resource (see
Add-LedgerTimeResource).

.PARAMETER Text
Optional description of the work.

.PARAMETER NonBillable
Registers the time as not billable (e.g. warranty work or internal meetings
on a customer project).

.PARAMETER Rate
Overrides the hourly rate for this entry.

.PARAMETER PassThru
Returns the created entry.

.EXAMPLE
Add-LedgerTimeEntry 7.5 -Project 1001

Reports 7.5 hours today on project 1001 for the default resource.

.EXAMPLE
Add-LedgerTimeEntry '3:45' -Project 1001 -Date 2024-03-12 -Resource BK -Text 'Workshop kravställning'
Add-LedgerTimeEntry 1 -Project 1001 -Date 2024-03-12 -NonBillable -Text 'Felrättning under garanti'

Reports a subcontractor's workshop and an hour of non-billable warranty work.
#>
function Add-LedgerTimeEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, Position = 0)]
        [string]$Hours,

        [Parameter()]
        [string]$Project,

        [Parameter()]
        [string]$CustomerNumber,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [string]$Resource,

        [Parameter()]
        [string]$Text,

        [Parameter()]
        [switch]$NonBillable,

        [Parameter()]
        [ValidateRange(0, 1000000)]
        [decimal]$Rate,

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $h = ConvertFrom-LedgerHours -Text $Hours
    Test-LedgerHours -Hours $h

    $context = Get-LedgerTimeContext -JournalPath $JournalPath
    $rateArg = if ($PSBoundParameters.ContainsKey('Rate')) { $Rate } else { $null }
    $target = Resolve-LedgerTimeEntryTarget -Context $context -ResourceId $Resource -ProjectNumber $Project `
        -CustomerNumber $CustomerNumber -Billable (-not $NonBillable) -Rate $rateArg

    $entries = @(Read-LedgerTimeEntries -JournalPath $JournalPath)
    $nextId = if ($entries) { ($entries | Measure-Object -Property EntryId -Maximum).Maximum + 1 } else { 1 }
    $entry = [PSCustomObject]@{
        EntryId        = [int]$nextId
        Date           = $Date.Date
        ResourceId     = $target.ResourceId
        ProjectNumber  = $target.ProjectNumber
        CustomerNumber = $target.CustomerNumber
        Hours          = $h
        Billable       = $target.Billable
        Rate           = $target.Rate
        Text           = ConvertTo-LedgerTimeField $Text
        InvoiceNumber  = $null
    }

    $what = if ($target.ProjectNumber) { "project $($target.ProjectNumber)" } else { "customer $($target.CustomerNumber)" }
    if ($PSCmdlet.ShouldProcess("$($Date.ToString('yyyy-MM-dd')) $($target.ResourceId)", "Report $h h on $what")) {
        Save-LedgerTimeEntries -JournalPath $JournalPath -Entries ($entries + $entry) -Months $Date.ToString('yyyy-MM')
        if ($PassThru) {
            ConvertTo-LedgerTimeEntryOutput -Entry $entry -Context $context -InvoiceStatus @{}
        }
    }
}
