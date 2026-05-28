<#
.SYNOPSIS
Adds a dimension to the journal.

.DESCRIPTION
Adds a dimension entry (e.g. cost centre, project) to the journal's
dimensions.txt file. Dimensions are numbered (1 = Kostnadsställe,
2 = Projekt is the BAS convention) and named.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER DimensionNumber
The numeric ID for the dimension (e.g. 1, 2).

.PARAMETER Name
A descriptive name for the dimension.

.EXAMPLE
Add-LedgerDimension -JournalPath .\MinFirma.ledger -DimensionNumber 1 -Name 'Kostnadsställe'

Adds dimension 1 named 'Kostnadsställe'.

.EXAMPLE
Add-LedgerDimension -JournalPath .\MinFirma.ledger -DimensionNumber 2 -Name 'Projekt'

Adds dimension 2 named 'Projekt' for project-based tracking.
#>
function Add-LedgerDimension {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$DimensionNumber,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $DimFile = Join-Path $JournalPath 'dimensions.txt'

    if (Test-Path $DimFile) {
        foreach ($Line in (Get-Content $DimFile)) {
            if ($Line -match "^$DimensionNumber`t") {
                throw "Dimension $DimensionNumber already exists."
            }
        }
    }

    "$DimensionNumber`t$Name" | Add-Content -Path $DimFile -Encoding UTF8
}
