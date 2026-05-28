<#
.SYNOPSIS
Lists all loaded PSLedger extensions.

.DESCRIPTION
Returns information about custom extension scripts that were loaded into the
PSLedger module from the configured extension paths. Each entry includes the
extension name, file path, source location, and the functions it provides.

.PARAMETER Source
Optional filter to show only extensions from a specific source.
Valid values: 'Env', 'User', 'Journal'.

.EXAMPLE
Get-LedgerExtension

Lists all loaded extensions from all sources.

.EXAMPLE
Get-LedgerExtension -Source Journal

Lists only extensions loaded from the current journal's Extensions folder.
#>
function Get-LedgerExtension {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateSet('Env', 'User', 'Journal')]
        [string]$Source
    )

    if ($Source) {
        $script:LoadedExtensions | Where-Object { $_.Source -eq $Source }
    }
    else {
        $script:LoadedExtensions
    }
}
