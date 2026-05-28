<#
.SYNOPSIS
Returns the fiscal year that follows the specified one.

.DESCRIPTION
Given a fiscal year (by name or pipeline object), returns the next fiscal year
in chronological order. Returns nothing if the input is already the last one.

.PARAMETER Name
The fiscal year identifier (e.g. '2024-01_2024-12'). Accepts pipeline input
from fiscal year objects (ValueFromPipelineByPropertyName).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.EXAMPLE
Get-LedgerFirstFiscalYear | Get-LedgerNextFiscalYear

Returns the second fiscal year by piping the first one.

.EXAMPLE
Get-LedgerNextFiscalYear -Name '2024-01_2024-12'

Returns the fiscal year that follows 2024.
#>
function Get-LedgerNextFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$JournalPath
    )

    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

        $years = Get-LedgerFiscalYear -JournalPath $JournalPath
        if (-not $years) { return }

        $idx = -1
        for ($i = 0; $i -lt $years.Count; $i++) {
            if ($years[$i].Name -eq $Name) {
                $idx = $i
                break
            }
        }

        if ($idx -ge 0 -and ($idx + 1) -lt $years.Count) {
            $years[$idx + 1]
        }
    }
}
