<#
.SYNOPSIS
Lists attachments for a verification.

.DESCRIPTION
Returns information about files attached to a verification. If no verification
number is specified, lists all attachments in the fiscal year.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year identifier. If omitted, uses the latest fiscal year.
Accepts pipeline input from fiscal year objects.

.PARAMETER VerificationNumber
Optional. If specified, lists only attachments for that verification.
Accepts pipeline input from entry objects (ValueFromPipelineByPropertyName).

.EXAMPLE
Get-LedgerAttachment -VerificationNumber 3

Lists all files attached to verification 3.

.EXAMPLE
Get-LedgerAttachment

Lists all attachments in the latest fiscal year.

.EXAMPLE
Get-LedgerEntry | Select-Object -Last 1 | Get-LedgerAttachment

Lists attachments for the most recent verification using pipeline.
#>
function Get-LedgerAttachment {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$FiscalYear,

        [Parameter(ValueFromPipelineByPropertyName)]
        [int]$VerificationNumber
    )

    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        if ($VerificationNumber) {
            # List attachments for a specific verification
            $attachDir = Join-Path $YearDir ('ver' + $VerificationNumber.ToString('0000'))
            if (-not (Test-Path $attachDir -PathType Container)) {
                return
            }

            Get-ChildItem -Path $attachDir -File | ForEach-Object {
                [PSCustomObject]@{
                    VerificationNumber = $VerificationNumber
                    FiscalYear         = $FiscalYear
                    FileName           = $_.Name
                    Path               = $_.FullName
                    Size               = $_.Length
                }
            }
        }
        else {
            # List all attachments in the fiscal year
            $attachDirs = Get-ChildItem -Path $YearDir -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^ver(\d+)$' }

            foreach ($dir in $attachDirs) {
                $verNum = [int]($dir.Name -replace '^ver', '')
                Get-ChildItem -Path $dir.FullName -File | ForEach-Object {
                    [PSCustomObject]@{
                        VerificationNumber = $verNum
                        FiscalYear         = $FiscalYear
                        FileName           = $_.Name
                        Path               = $_.FullName
                        Size               = $_.Length
                    }
                }
            }
        }
    }
}
