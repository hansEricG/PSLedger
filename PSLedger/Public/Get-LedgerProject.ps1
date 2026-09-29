<#
.SYNOPSIS
Lists the projects that time can be reported on.

.DESCRIPTION
Returns one object per project in time/projects.txt with ProjectNumber, Name,
CustomerNumber, CustomerName, HourlyRate (the project's own rate),
EffectiveRate (the project's rate, otherwise the customer's) and Status.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER ProjectNumber
Optional. Returns only this project.

.PARAMETER CustomerNumber
Optional. Returns only the customer's projects.

.PARAMETER Status
Optional. 'Active' or 'Closed'.

.EXAMPLE
Get-LedgerProject -Status Active

Lists the active projects.

.EXAMPLE
Get-LedgerProject -CustomerNumber '10' | Format-Table ProjectNumber, Name, EffectiveRate

Lists Volvo AB's projects and the rate their time is billed at.
#>
function Get-LedgerProject {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$ProjectNumber,

        [Parameter()]
        [string]$CustomerNumber,

        [Parameter()]
        [ValidateSet('Active', 'Closed')]
        [string]$Status
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
    $customers = @(Get-LedgerCustomer -JournalPath $JournalPath)

    foreach ($p in @(Read-LedgerProjects -JournalPath $JournalPath)) {
        if ($ProjectNumber -and $p.ProjectNumber -ne $ProjectNumber) { continue }
        if ($CustomerNumber -and $p.CustomerNumber -ne $CustomerNumber) { continue }
        if ($Status -and $p.Status -ne $Status) { continue }
        $customer = if ($p.CustomerNumber) { $customers | Where-Object CustomerNumber -eq $p.CustomerNumber | Select-Object -First 1 }
        [PSCustomObject]@{
            ProjectNumber  = $p.ProjectNumber
            Name           = $p.Name
            CustomerNumber = $p.CustomerNumber
            CustomerName   = if ($customer) { $customer.Name } else { '' }
            HourlyRate     = $p.HourlyRate
            EffectiveRate  = Resolve-LedgerTimeRate -Project $p -Customer $customer
            Status         = $p.Status
        }
    }
}
