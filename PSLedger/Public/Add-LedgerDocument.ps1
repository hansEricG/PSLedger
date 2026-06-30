<#
.SYNOPSIS
Adds a general supporting document to a fiscal year.

.DESCRIPTION
Copies (or moves) a file into the fiscal year's shared document directory.
Unlike attachments, which belong to a single verification, documents are scoped
to the whole fiscal year and can serve as supporting material (underlag) for
several verifications — for example a bank statement (kontoutdrag) covering many
entries. The directory is created on demand as a subdirectory of the fiscal year
directory, named documents/.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year identifier. If omitted, uses the latest fiscal year.
Accepts pipeline input from fiscal year objects.

.PARAMETER Path
The path to the file to add.

.PARAMETER Move
If specified, moves the file instead of copying it.

.EXAMPLE
Add-LedgerDocument -Path .\kontoutdrag-jan.pdf

Copies kontoutdrag-jan.pdf to the document directory for the latest fiscal year.

.EXAMPLE
Add-LedgerDocument -FiscalYear '2024-01_2024-12' -Path .\kontoutdrag-feb.pdf -Move

Moves kontoutdrag-feb.pdf into the shared document directory for the 2024
fiscal year of Bokforing Nord AB.
#>
function Add-LedgerDocument {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [switch]$Move
    )

    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        # Verify source file exists
        if (-not (Test-Path $Path -PathType Leaf)) {
            throw "File not found: $Path"
        }

        # Create document directory on demand
        $docDir = Join-Path $YearDir 'documents'
        if (-not (Test-Path $docDir)) {
            New-Item -ItemType Directory -Path $docDir -Force | Out-Null
        }

        $sourceFile = Get-Item $Path
        $destPath = Join-Path $docDir $sourceFile.Name

        if ($Move) {
            Move-Item -Path $Path -Destination $destPath -Force
        }
        else {
            Copy-Item -Path $Path -Destination $destPath -Force
        }

        [PSCustomObject]@{
            FiscalYear      = $FiscalYear
            FileName        = $sourceFile.Name
            DestinationPath = $destPath
            Size            = $sourceFile.Length
        }
    }
}
