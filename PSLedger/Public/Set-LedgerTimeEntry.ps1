<#
.SYNOPSIS
Changes reported time.

.DESCRIPTION
Changes the hours, date, project, resource, text, billable flag or rate of an
open time entry. Invoiced entries are locked; credit the invoice with
Add-LedgerCreditInvoice first to change them.

When the project or customer changes and -Rate is not given, the rate is
resolved again from the new project/customer.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER EntryId
The id of the entry to change. Accepts pipeline input from Get-LedgerTimeEntry.

.PARAMETER Hours
The new number of hours (decimal or 'h:mm').

.PARAMETER Date
The new date.

.PARAMETER ProjectNumber
The new project.

.PARAMETER CustomerNumber
The new customer, for time not reported on a project.

.PARAMETER ResourceId
The new resource.

.PARAMETER Text
The new description.

.PARAMETER Billable
$true or $false.

.PARAMETER Rate
The new hourly rate.

.PARAMETER PassThru
If specified, returns the created/updated time entry. By default the command
produces no output.

.EXAMPLE
Set-LedgerTimeEntry -EntryId 42 -Hours 6 -Text 'Workshop, förkortad'

Corrects the hours and text of entry 42.

.EXAMPLE
Get-LedgerTimeEntry -ProjectNumber 1001 -Status Open | Set-LedgerTimeEntry -Rate 1200

Reprices all open time on project 1001 after a rate change.
#>
function Set-LedgerTimeEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$EntryId,

        [Parameter()]
        [string]$Hours,

        [Parameter()]
        [datetime]$Date,

        [Parameter()]
        [string]$ProjectNumber,

        [Parameter()]
        [string]$CustomerNumber,

        [Parameter()]
        [string]$ResourceId,

        [Parameter()]
        [string]$Text,

        [Parameter()]
        [bool]$Billable,

        [Parameter()]
        [ValidateRange(0, 1000000)]
        [decimal]$Rate,

        [Parameter()]
        [switch]$PassThru
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

        $entries = @(Read-LedgerTimeEntries -JournalPath $JournalPath)
        $entry = $entries | Where-Object EntryId -eq $EntryId | Select-Object -First 1
        if (-not $entry) { throw "Time entry $EntryId does not exist." }
        $invoiceStatus = Get-LedgerTimeInvoiceStatusMap -JournalPath $JournalPath
        if (Test-LedgerTimeEntryInvoiced -Entry $entry -InvoiceStatus $invoiceStatus) {
            throw "Time entry $EntryId is on invoice $($entry.InvoiceNumber). Credit the invoice first to change it."
        }
        $oldMonth = $entry.Date.ToString('yyyy-MM')

        if ($PSBoundParameters.ContainsKey('Hours')) {
            $h = ConvertFrom-LedgerHours -Text $Hours
            Test-LedgerHours -Hours $h
            $entry.Hours = $h
        }
        if ($PSBoundParameters.ContainsKey('Date')) { $entry.Date = $Date.Date }
        if ($PSBoundParameters.ContainsKey('Text')) { $entry.Text = ConvertTo-LedgerTimeField $Text }

        $retarget = $PSBoundParameters.ContainsKey('ProjectNumber') -or $PSBoundParameters.ContainsKey('CustomerNumber') -or
            $PSBoundParameters.ContainsKey('ResourceId') -or $PSBoundParameters.ContainsKey('Billable') -or $PSBoundParameters.ContainsKey('Rate')
        if ($retarget) {
            $newProject = if ($PSBoundParameters.ContainsKey('ProjectNumber')) { $ProjectNumber } else { $entry.ProjectNumber }
            $newCustomer = if ($PSBoundParameters.ContainsKey('CustomerNumber')) { $CustomerNumber }
                           elseif ($PSBoundParameters.ContainsKey('ProjectNumber')) { '' }
                           else { $entry.CustomerNumber }
            $keepRate = -not ($PSBoundParameters.ContainsKey('ProjectNumber') -or $PSBoundParameters.ContainsKey('CustomerNumber'))
            $newRate = if ($PSBoundParameters.ContainsKey('Rate')) { $Rate } elseif ($keepRate) { $entry.Rate } else { $null }
            $newBillable = if ($PSBoundParameters.ContainsKey('Billable')) { $Billable } else { $entry.Billable }
            $newResource = if ($PSBoundParameters.ContainsKey('ResourceId')) { $ResourceId } else { $entry.ResourceId }

            $target = Resolve-LedgerTimeEntryTarget -Context (Get-LedgerTimeContext -JournalPath $JournalPath) `
                -ResourceId $newResource -ProjectNumber $newProject -CustomerNumber $newCustomer -Billable $newBillable -Rate $newRate
            $entry.ResourceId = $target.ResourceId
            $entry.ProjectNumber = $target.ProjectNumber
            $entry.CustomerNumber = $target.CustomerNumber
            $entry.Billable = $target.Billable
            $entry.Rate = $target.Rate
        }
        $entry.InvoiceNumber = $null

        if ($PSCmdlet.ShouldProcess("Time entry $EntryId", 'Update time entry')) {
            Save-LedgerTimeEntries -JournalPath $JournalPath -Entries $entries -Months @($oldMonth, $entry.Date.ToString('yyyy-MM'))
            if ($PassThru) {
                Get-LedgerTimeEntry -JournalPath $JournalPath -EntryId $EntryId
            }
        }
    }
}
