<#
.SYNOPSIS
Returns the current session fiscal year.

.DESCRIPTION
Returns the fiscal year name set via Set-LedgerCurrentFiscalYear, without needing
to specify it explicitly. Throws if no current fiscal year has been set.

.EXAMPLE
Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12'
Get-LedgerCurrentFiscalYear

Returns '2024-01_2024-12'.

.EXAMPLE
$year = Get-LedgerCurrentFiscalYear
Write-Output "Working in fiscal year $year"

Captures the current fiscal year into a variable.
#>
function Get-LedgerCurrentFiscalYear {
    [CmdletBinding()]
    param ()

    if (-not $script:CurrentFiscalYear) {
        throw "No current fiscal year set. Use Set-LedgerCurrentFiscalYear first."
    }

    $script:CurrentFiscalYear
}
