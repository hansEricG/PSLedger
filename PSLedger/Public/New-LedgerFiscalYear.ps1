<#
.SYNOPSIS
Creates a new fiscal year in the journal.

.DESCRIPTION
Creates a subdirectory for the fiscal year (named using the pattern yyyy-MM_yyyy-MM)
with a year.txt file containing start date, end date, and status (Open).
Supports both calendar years and broken fiscal years.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER StartDate
The first day of the fiscal year.

.PARAMETER EndDate
The last day of the fiscal year. Must be after StartDate.

.EXAMPLE
New-LedgerFiscalYear -JournalPath .\MinFirma.ledger -StartDate '2024-01-01' -EndDate '2024-12-31'

Creates a standard calendar-year fiscal year (directory: 2024-01_2024-12).

.EXAMPLE
New-LedgerFiscalYear -JournalPath .\MinFirma.ledger -StartDate '2024-07-01' -EndDate '2025-06-30'

Creates a broken fiscal year (directory: 2024-07_2025-06).
#>
function New-LedgerFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [Parameter(Mandatory)]
        [datetime]$EndDate
    )

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    if ($EndDate -le $StartDate) {
        throw "EndDate must be after StartDate."
    }

    $DirName = '{0:yyyy-MM}_{1:yyyy-MM}' -f $StartDate, $EndDate
    $YearDir = Join-Path $JournalPath $DirName

    if (Test-Path $YearDir) {
        throw "Fiscal year already exists: $DirName"
    }

    New-Item -ItemType Directory -Path $YearDir -Force | Out-Null

    $Lines = @(
        "StartDate: $($StartDate.ToString('yyyy-MM-dd'))"
        "EndDate: $($EndDate.ToString('yyyy-MM-dd'))"
        "Status: Open"
    )

    $YearFile = Join-Path $YearDir 'year.txt'
    $Lines | Set-Content -Path $YearFile -Encoding UTF8
}
