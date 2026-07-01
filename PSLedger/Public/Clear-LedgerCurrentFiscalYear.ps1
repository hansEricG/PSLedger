<#
.SYNOPSIS
Clears the current PSLedger fiscal year from the session.

.DESCRIPTION
Removes the session-level default fiscal year set via Set-LedgerCurrentFiscalYear.
Commands will fall back to the latest fiscal year (or require -FiscalYear) again.

.EXAMPLE
Clear-LedgerCurrentFiscalYear

Clears the current fiscal year.

.EXAMPLE
Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12'
# ... work in 2024 ...
Clear-LedgerCurrentFiscalYear
Set-LedgerCurrentFiscalYear -FiscalYear '2025-01_2025-12'

Switch the session default from one fiscal year to another.
#>
function Clear-LedgerCurrentFiscalYear {
    [CmdletBinding()]
    param ()

    $script:CurrentFiscalYear = $null
}
