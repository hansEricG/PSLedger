<#
.SYNOPSIS
Lists objects (dimension instances) in the journal.

.DESCRIPTION
Reads objects.txt and returns PSCustomObjects with DimensionNumber, ObjectNumber
and Name. Can filter by dimension number and/or object number.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER DimensionNumber
Optional. Filter objects by dimension.

.PARAMETER ObjectNumber
Optional. Filter by a specific object ID within a dimension. Requires
DimensionNumber.

.EXAMPLE
Get-LedgerObject -JournalPath .\MinFirma.ledger

Returns all objects across all dimensions.

.EXAMPLE
Get-LedgerObject -JournalPath .\MinFirma.ledger -DimensionNumber 1

Returns all cost centres (dimension 1 objects).
#>
function Get-LedgerObject {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [int]$DimensionNumber,

        [string]$ObjectNumber
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $ObjFile = Join-Path $JournalPath 'objects.txt'
    if (-not (Test-Path $ObjFile)) { return }

    $objects = foreach ($Line in (Get-Content $ObjFile)) {
        if ($Line -match '^(\d+)\t([^\t]+)\t(.+)$') {
            [PSCustomObject]@{
                DimensionNumber = [int]$Matches[1]
                ObjectNumber    = $Matches[2]
                Name            = $Matches[3]
            }
        }
    }

    if ($PSBoundParameters.ContainsKey('DimensionNumber')) {
        $objects = $objects | Where-Object { $_.DimensionNumber -eq $DimensionNumber }
    }
    if ($ObjectNumber) {
        $objects = $objects | Where-Object { $_.ObjectNumber -eq $ObjectNumber }
    }

    $objects
}
