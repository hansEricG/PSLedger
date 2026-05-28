<#
.SYNOPSIS
Closes a fiscal year, preventing further entries.

.DESCRIPTION
Sets the Status field in year.txt to 'Closed'. Once closed, Add-LedgerEntry
will refuse to create new verifications in that fiscal year. This is used
at year-end after all bookkeeping is complete.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.EXAMPLE
Close-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Closes the 2024 fiscal year so no more entries can be added.

.EXAMPLE
Get-LedgerFiscalYear -JournalPath .\MinFirma.ledger |
    Where-Object { $_.Status -eq 'Open' } |
    ForEach-Object { Close-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear $_.Name }

Closes all open fiscal years.
#>
function Close-LedgerFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        $YearFile = Join-Path $YearDir 'year.txt'
        if (-not (Test-Path $YearFile)) {
            throw "Invalid fiscal year - year.txt not found in: $FiscalYear"
        }

        $Lines = Get-Content $YearFile

        # Check current status
        foreach ($Line in $Lines) {
            if ($Line -match '^Status:\s*Closed') {
                throw "Fiscal year $FiscalYear is already closed."
            }
        }

        # Rewrite with updated status
        $NewLines = foreach ($Line in $Lines) {
            if ($Line -match '^Status:\s*') {
                'Status: Closed'
            }
            else {
                $Line
            }
        }

        $NewLines | Set-Content -Path $YearFile -Encoding UTF8
    }
}

