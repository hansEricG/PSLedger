<#
.SYNOPSIS
Lists dimensions defined in the journal.

.DESCRIPTION
Reads dimensions.txt and returns PSCustomObjects with DimensionNumber and Name.
Optionally filter by dimension number.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER DimensionNumber
Optional. If specified, returns only the dimension with this number.

.EXAMPLE
Get-LedgerDimension -JournalPath .\MinFirma.ledger

Returns all dimensions.

.EXAMPLE
Get-LedgerDimension -JournalPath .\MinFirma.ledger -DimensionNumber 1

Returns only dimension 1 (e.g. Kostnadsställe).
#>
function Get-LedgerDimension {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [int]$DimensionNumber
    )

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $DimFile = Join-Path $JournalPath 'dimensions.txt'
    if (-not (Test-Path $DimFile)) { return }

    $dims = foreach ($Line in (Get-Content $DimFile)) {
        if ($Line -match '^(\d+)\t(.+)$') {
            [PSCustomObject]@{
                DimensionNumber = [int]$Matches[1]
                Name            = $Matches[2]
            }
        }
    }

    if ($PSBoundParameters.ContainsKey('DimensionNumber')) {
        $dims | Where-Object { $_.DimensionNumber -eq $DimensionNumber }
    }
    else {
        $dims
    }
}
