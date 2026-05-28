<#
.SYNOPSIS
Adds an object (instance) to a dimension.

.DESCRIPTION
Adds an object entry to objects.txt. Objects belong to a dimension
(e.g. 'Stockholm' in dimension 1 Kostnadsställe, or 'Projekt Alpha' in
dimension 2 Projekt). The dimension must already exist.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER DimensionNumber
The dimension this object belongs to (must exist in dimensions.txt).

.PARAMETER ObjectNumber
An identifier for this object (e.g. 'cs01', 'proj-a').

.PARAMETER Name
A descriptive name for the object.

.EXAMPLE
Add-LedgerObject -JournalPath .\MinFirma.ledger -DimensionNumber 1 -ObjectNumber 'sthlm' -Name 'Stockholm'

Adds object 'sthlm' (Stockholm) to dimension 1 (Kostnadsställe).

.EXAMPLE
Add-LedgerObject -JournalPath .\MinFirma.ledger -DimensionNumber 2 -ObjectNumber 'proj-a' -Name 'Projekt Alpha'

Adds project 'proj-a' to dimension 2 (Projekt).
#>
function Add-LedgerObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$DimensionNumber,

        [Parameter(Mandatory)]
        [string]$ObjectNumber,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    # Validate dimension exists
    $dim = Get-LedgerDimension -JournalPath $JournalPath -DimensionNumber $DimensionNumber
    if (-not $dim) {
        throw "Dimension $DimensionNumber does not exist. Add it with Add-LedgerDimension first."
    }

    $ObjFile = Join-Path $JournalPath 'objects.txt'

    if (Test-Path $ObjFile) {
        foreach ($Line in (Get-Content $ObjFile)) {
            if ($Line -match "^$DimensionNumber`t$([regex]::Escape($ObjectNumber))`t") {
                throw "Object '$ObjectNumber' already exists in dimension $DimensionNumber."
            }
        }
    }

    "$DimensionNumber`t$ObjectNumber`t$Name" | Add-Content -Path $ObjFile -Encoding UTF8
}
