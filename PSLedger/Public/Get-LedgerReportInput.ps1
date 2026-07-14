<#
.SYNOPSIS
Reads the year-specific annual report input (förvaltningsberättelse and note
data) stored in report.txt for a fiscal year.

.DESCRIPTION
Returns the values recorded with Set-LedgerReportInput as a PSCustomObject with
the SignificantEvents, ProposedDividend, AverageEmployees, SecuritiesMarketValue,
SigningPlace and SigningDate properties. Fields that have not been set are $null.
Numeric-looking fields (ProposedDividend, AverageEmployees, SecuritiesMarketValue)
are returned as their text value; convert with [decimal]/[int] as needed.

When the journal's on-disk schema is older than this module supports a one-time
warning is emitted (the report input is still returned).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.EXAMPLE
Get-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'

Returns the recorded significant events, proposed dividend and signing details for
the year.

.EXAMPLE
$input = Get-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'
"Utdelning: {0:N0} kr" -f [decimal]$input.ProposedDividend

Captures the report input and formats the proposed dividend.
#>
function Get-LedgerReportInput {
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

        $Path = Get-LedgerReportInputPath -JournalPath $JournalPath -FiscalYear $FiscalYear
        $fields = Read-LedgerReportInput -Path $Path

        [PSCustomObject]@{
            JournalPath           = $JournalPath
            FiscalYear            = $FiscalYear
            SignificantEvents     = if ($fields.Contains('SignificantEvents')) { $fields['SignificantEvents'] } else { $null }
            ProposedDividend      = if ($fields.Contains('ProposedDividend')) { $fields['ProposedDividend'] } else { $null }
            AverageEmployees      = if ($fields.Contains('AverageEmployees')) { $fields['AverageEmployees'] } else { $null }
            SecuritiesMarketValue = if ($fields.Contains('SecuritiesMarketValue')) { $fields['SecuritiesMarketValue'] } else { $null }
            SigningPlace          = if ($fields.Contains('SigningPlace')) { $fields['SigningPlace'] } else { $null }
            SigningDate           = if ($fields.Contains('SigningDate')) { $fields['SigningDate'] } else { $null }
        }
    }
}
