<#
.SYNOPSIS
Builds the employees (anställda och personalkostnader) note for an årsredovisning.

.DESCRIPTION
Reports the average number of employees (medelantal anställda) during the year.
The value defaults to the AverageEmployees recorded with Set-LedgerReportInput and
can be overridden with -AverageEmployees. When there are no employees the note's
Statement property carries the standard wording used in a small company's annual
report.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-09_2025-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER AverageEmployees
The average number of employees during the year. Overrides the AverageEmployees
recorded with Set-LedgerReportInput.

.EXAMPLE
Get-LedgerEmployeeNote -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'

Returns the recorded average number of employees for the year.

.EXAMPLE
Get-LedgerEmployeeNote -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' -AverageEmployees 3

Reports three average employees for the year regardless of the recorded value.
#>
function Get-LedgerEmployeeNote {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [int]$AverageEmployees
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        if ($PSBoundParameters.ContainsKey('AverageEmployees')) {
            $Average = $AverageEmployees
        }
        else {
            $ReportInput = Get-LedgerReportInput -JournalPath $JournalPath -FiscalYear $FiscalYear
            $Average = if ($ReportInput.AverageEmployees) { [int]$ReportInput.AverageEmployees } else { 0 }
        }

        $Statement = if ($Average -le 0) {
            'Bolaget har inte haft några anställda och några löner och ersättningar har inte utbetalats.'
        }
        else {
            "Medelantalet anställda under året har varit $Average."
        }

        [PSCustomObject]@{
            Label            = 'Anställda och personalkostnader'
            FiscalYear       = $FiscalYear
            AverageEmployees = $Average
            Statement        = $Statement
        }
    }
}
