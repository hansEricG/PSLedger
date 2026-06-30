<#
.SYNOPSIS
Lists general supporting documents for a fiscal year.

.DESCRIPTION
Returns information about the shared documents stored for a fiscal year. These
documents live in the fiscal year's documents/ directory and are independent of
any single verification, so they can act as supporting material (underlag) for
several entries.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year identifier. If omitted, only the latest fiscal year is searched
(not all years). Documents stored in earlier fiscal years are therefore not
returned unless you pass their identifier explicitly, so an empty result may
simply mean the latest fiscal year has no documents yet.
Accepts pipeline input from fiscal year objects.

.PARAMETER FileName
Optional. If specified, lists only documents whose file name matches this
wildcard pattern.

.EXAMPLE
Get-LedgerDocument

Lists all shared documents in the latest fiscal year. Returns nothing if the
latest fiscal year has no documents, even when earlier years do.

.EXAMPLE
Get-LedgerDocument -FiscalYear '2024-01_2024-12' -FileName 'kontoutdrag-*'

Lists all bank statement documents in the 2024 fiscal year of Bokforing Nord AB.

.EXAMPLE
Get-ChildItem .\underlag -File -Recurse | Add-LedgerDocument
Get-LedgerDocument

First adds every file from the underlag folder and all its subdirectories to the
latest fiscal year (Add-LedgerDocument stores them flat in the documents/
directory), then lists the result so you can verify what was imported. Add -Force
to Add-LedgerDocument to overwrite documents whose name already exists.
#>
function Get-LedgerDocument {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$FiscalYear,

        [Parameter()]
        [string]$FileName
    )

    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        $docDir = Join-Path $YearDir 'documents'
        if (-not (Test-Path $docDir -PathType Container)) {
            Write-Verbose "Fiscal year '$FiscalYear' has no documents directory; no documents to list."
            return
        }

        $items = Get-ChildItem -Path $docDir -File
        if ($FileName) {
            $items = $items | Where-Object { $_.Name -like $FileName }
        }

        if (-not $items) {
            Write-Verbose "No documents found in fiscal year '$FiscalYear'. If you did not specify -FiscalYear, only the latest fiscal year is searched."
            return
        }

        $items | ForEach-Object {
            [PSCustomObject]@{
                FiscalYear = $FiscalYear
                FileName   = $_.Name
                Path       = $_.FullName
                Size       = $_.Length
            }
        }
    }
}
