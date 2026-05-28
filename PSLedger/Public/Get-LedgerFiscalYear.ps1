<#
.SYNOPSIS
Lists fiscal years in a journal.

.DESCRIPTION
Scans the journal directory for fiscal year subdirectories (matching the
pattern yyyy-MM_yyyy-MM) and returns their metadata from year.txt including
start date, end date, and status.

.PARAMETER JournalPath
The path to an existing journal directory.

.EXAMPLE
Get-LedgerFiscalYear -JournalPath .\MinFirma.ledger

Returns all fiscal years with Name, StartDate, EndDate, and Status.

.EXAMPLE
Get-LedgerFiscalYear -JournalPath .\MinFirma.ledger |
    Where-Object { $_.Status -eq 'Open' }

Returns only open (unlocked) fiscal years.
#>
function Get-LedgerFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $YearDirs = Get-ChildItem -Path $JournalPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}_\d{4}-\d{2}$' }

    if (-not $YearDirs) {
        return
    }

    $Years = foreach ($Dir in $YearDirs) {
        $YearFile = Join-Path $Dir.FullName 'year.txt'
        $StartDate = $null
        $EndDate = $null
        $Status = $null

        if (Test-Path $YearFile) {
            foreach ($Line in (Get-Content $YearFile)) {
                if ($Line -match '^StartDate:\s*(.+)$') {
                    $StartDate = $Matches[1]
                }
                elseif ($Line -match '^EndDate:\s*(.+)$') {
                    $EndDate = $Matches[1]
                }
                elseif ($Line -match '^Status:\s*(.+)$') {
                    $Status = $Matches[1]
                }
            }
        }

        [PSCustomObject]@{
            Name      = $Dir.Name
            StartDate = $StartDate
            EndDate   = $EndDate
            Status    = $Status
        }
    }

    $Years | Sort-Object StartDate
}
