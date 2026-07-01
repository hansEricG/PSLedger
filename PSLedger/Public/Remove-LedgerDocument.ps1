<#
.SYNOPSIS
Removes a general supporting document from a fiscal year.

.DESCRIPTION
Deletes the specified file from a fiscal year's shared document directory.
If the directory becomes empty after removal, it is also deleted.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year identifier. If omitted, uses the latest fiscal year.
Accepts pipeline input from fiscal year objects.

.PARAMETER FileName
The name of the file to remove.

.EXAMPLE
Remove-LedgerDocument -FileName 'kontoutdrag-jan.pdf'

Removes kontoutdrag-jan.pdf from the latest fiscal year's documents.

.EXAMPLE
Get-LedgerDocument | Where-Object FileName -like '*.tmp' |
    ForEach-Object { Remove-LedgerDocument -FiscalYear $_.FiscalYear -FileName $_.FileName }

Removes all temporary documents from the latest fiscal year.
#>
function Remove-LedgerDocument {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$FiscalYear,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$FileName
    )

    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        $docDir = Join-Path $YearDir 'documents'
        if (-not (Test-Path $docDir -PathType Container)) {
            throw "No documents found for fiscal year $FiscalYear."
        }

        $filePath = Join-Path $docDir $FileName
        if (-not (Test-Path $filePath -PathType Leaf)) {
            throw "Document not found: $FileName"
        }

        if ($PSCmdlet.ShouldProcess($filePath, 'Remove document')) {
            Remove-Item -Path $filePath -Force

            # Remove directory if empty
            $remaining = Get-ChildItem -Path $docDir -File
            if (-not $remaining) {
                Remove-Item -Path $docDir -Force
            }
        }
    }
}
