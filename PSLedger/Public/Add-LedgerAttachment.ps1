<#
.SYNOPSIS
Attaches a file to a verification.

.DESCRIPTION
Copies (or moves) a file into the verification's attachment directory. The
directory is created on demand as a subdirectory of the fiscal year directory,
named after the verification (e.g. ver0001/).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year identifier. If omitted, uses the latest fiscal year.
Accepts pipeline input from fiscal year objects.

.PARAMETER VerificationNumber
The verification number to attach the file to.

.PARAMETER Path
The path to the file to attach.

.PARAMETER Move
If specified, moves the file instead of copying it.

.EXAMPLE
Add-LedgerAttachment -VerificationNumber 3 -Path .\faktura-101.pdf

Copies faktura-101.pdf to the attachment directory for verification 3.

.EXAMPLE
Add-LedgerAttachment -VerificationNumber 1 -Path .\kvitto.jpg -Move

Moves kvitto.jpg into the attachment directory for verification 1.
#>
function Add-LedgerAttachment {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [int]$VerificationNumber,

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

        # Verify the verification exists
        $verFileName = 'ver' + $VerificationNumber.ToString('0000') + '.txt'
        $verFilePath = Join-Path $YearDir $verFileName
        if (-not (Test-Path $verFilePath)) {
            throw "Verification $VerificationNumber not found in fiscal year $FiscalYear."
        }

        # Verify source file exists
        if (-not (Test-Path $Path -PathType Leaf)) {
            throw "File not found: $Path"
        }

        # Create attachment directory on demand
        $attachDir = Join-Path $YearDir ('ver' + $VerificationNumber.ToString('0000'))
        if (-not (Test-Path $attachDir)) {
            New-Item -ItemType Directory -Path $attachDir -Force | Out-Null
        }

        $sourceFile = Get-Item $Path
        $destPath = Join-Path $attachDir $sourceFile.Name

        if ($Move) {
            Move-Item -Path $Path -Destination $destPath -Force
        }
        else {
            Copy-Item -Path $Path -Destination $destPath -Force
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
