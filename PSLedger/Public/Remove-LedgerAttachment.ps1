<#
.SYNOPSIS
Removes an attachment from a verification.

.DESCRIPTION
Deletes the specified file from a verification's attachment directory.
If the directory becomes empty after removal, it is also deleted.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year identifier. If omitted, uses the latest fiscal year.
Accepts pipeline input from fiscal year objects.

.PARAMETER VerificationNumber
The verification number to remove the attachment from.

.PARAMETER FileName
The name of the file to remove.

.EXAMPLE
Remove-LedgerAttachment -VerificationNumber 3 -FileName 'faktura-101.pdf'

Removes faktura-101.pdf from verification 3.

.EXAMPLE
Get-LedgerAttachment -VerificationNumber 1 | Where-Object FileName -like '*.tmp' |
    ForEach-Object { Remove-LedgerAttachment -VerificationNumber $_.VerificationNumber -FileName $_.FileName }

Removes all .tmp attachments from verification 1.
#>
function Remove-LedgerAttachment {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [int]$VerificationNumber,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        $attachDir = Join-Path $YearDir ('ver' + $VerificationNumber.ToString('0000'))
        if (-not (Test-Path $attachDir -PathType Container)) {
            throw "No attachments found for verification $VerificationNumber."
        }

        $filePath = Join-Path $attachDir $FileName
        if (-not (Test-Path $filePath -PathType Leaf)) {
            throw "Attachment not found: $FileName"
        }

        if ($PSCmdlet.ShouldProcess($filePath, 'Remove attachment')) {
            Remove-Item -Path $filePath -Force

            # Remove directory if empty
            $remaining = Get-ChildItem -Path $attachDir -File
            if (-not $remaining) {
                Remove-Item -Path $attachDir -Force
            }
        }
    }
}
