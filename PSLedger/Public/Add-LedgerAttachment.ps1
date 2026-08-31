<#
.SYNOPSIS
Attaches one or more files to a verification.

.DESCRIPTION
Copies (or moves) one or more files into the verification's attachment
directory. The directory is created on demand as a subdirectory of the fiscal
year directory, named after the verification (e.g. ver0001/). One result object
is returned per attached file.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year identifier. If omitted, uses the latest fiscal year.
Accepts pipeline input from fiscal year objects.

.PARAMETER VerificationNumber
The verification number to attach the file to.

.PARAMETER Path
One or more paths to the files to attach.

.PARAMETER Move
If specified, moves the files instead of copying them.

.EXAMPLE
Add-LedgerAttachment -VerificationNumber 3 -Path .\faktura-101.pdf

Copies faktura-101.pdf to the attachment directory for verification 3.

.EXAMPLE
Add-LedgerAttachment -VerificationNumber 1 -Path .\kvitto.jpg -Move

Moves kvitto.jpg into the attachment directory for verification 1.

.EXAMPLE
Add-LedgerAttachment -VerificationNumber 5 -Path .\faktura.pdf, .\kvitto.jpg, .\avtal.pdf

Attaches three files to verification 5 in a single call.
#>
function Add-LedgerAttachment {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [int]$VerificationNumber,

        [Parameter(Mandatory)]
        [string[]]$Path,

        [Parameter()]
        [switch]$Move
    )

    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        # Verify the verification exists
        $verFileName = 'ver' + $VerificationNumber.ToString('0000') + '.txt'
        $verFilePath = Join-Path $YearDir $verFileName
        if (-not (Test-Path $verFilePath)) {
            throw "Verification $VerificationNumber not found in fiscal year $FiscalYear."
        }

        # Verify all source files exist before copying any
        foreach ($sourcePath in $Path) {
            if (-not (Test-Path $sourcePath -PathType Leaf)) {
                throw "File not found: $sourcePath"
            }
        }

        # Create attachment directory on demand
        $attachDir = Join-Path $YearDir ('ver' + $VerificationNumber.ToString('0000'))

        foreach ($sourcePath in $Path) {
            $sourceFile = Get-Item $sourcePath
            $destPath = Join-Path $attachDir $sourceFile.Name

            $verb = if ($Move) { 'Move' } else { 'Copy' }
            if (-not $PSCmdlet.ShouldProcess($destPath, "$verb attachment")) {
                continue
            }

            if (-not (Test-Path $attachDir)) {
                New-Item -ItemType Directory -Path $attachDir -Force | Out-Null
            }

            if ($Move) {
                Move-Item -Path $sourcePath -Destination $destPath -Force
            }
            else {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
            }

            [PSCustomObject]@{
                VerificationNumber = $VerificationNumber
                FiscalYear         = $FiscalYear
                FileName           = $sourceFile.Name
                DestinationPath    = $destPath
                Size               = $sourceFile.Length
            }
        }
    }
}
