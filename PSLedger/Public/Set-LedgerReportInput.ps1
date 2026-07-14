<#
.SYNOPSIS
Sets the year-specific annual report input (förvaltningsberättelse and note data)
for a fiscal year, stored in report.txt.

.DESCRIPTION
Records the parts of an årsredovisning that cannot be derived from the
bookkeeping itself: the significant events during the year, the board's proposed
dividend, the average number of employees, the market value of listed securities
and the place and date the report is signed. The values are written to a
report.txt file in the fiscal year directory (alongside the verifications and
ib.txt), UTF-8 encoded.

Only the fields you supply are changed; existing values are preserved. Passing an
empty string removes a field. Get the stored values back with
Get-LedgerReportInput and use them when producing the annual report.

Supports -WhatIf and -Confirm.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER SignificantEvents
Free-text description of significant events during the year, shown under
"Väsentliga händelser" in the förvaltningsberättelse. May span several lines.

.PARAMETER ProposedDividend
The dividend the board proposes to distribute to the owners, used in the
"Förslag till vinstdisposition" section.

.PARAMETER AverageEmployees
The average number of employees during the year, used in the personnel note.

.PARAMETER SecuritiesMarketValue
The market value (marknadsvärde) of listed securities held as assets, used in the
"Aktier och andelar" note.

.PARAMETER SigningPlace
The place (ort) where the annual report is signed, e.g. 'Gävle'.

.PARAMETER SigningDate
The date the annual report is signed, e.g. '2025-10-01'.

.EXAMPLE
Set-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -SignificantEvents 'Inga väsentliga händelser.' -SigningPlace 'Gävle'

Records the significant events text and signing place for the year.

.EXAMPLE
Set-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -ProposedDividend 0 -AverageEmployees 0 -SecuritiesMarketValue 277579 -SigningDate '2025-10-01'

Records the vinstdisposition, personnel and securities figures used by the notes
together with the signing date.
#>
function Set-LedgerReportInput {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [string]$SignificantEvents,

        [Parameter()]
        [string]$ProposedDividend,

        [Parameter()]
        [string]$AverageEmployees,

        [Parameter()]
        [string]$SecuritiesMarketValue,

        [Parameter()]
        [string]$SigningPlace,

        [Parameter()]
        [string]$SigningDate
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        # Only the fields the caller actually supplied are changed. An empty
        # string removes the field; SignificantEvents keeps its newlines.
        $order = @(
            'ProposedDividend', 'AverageEmployees', 'SecuritiesMarketValue',
            'SigningPlace', 'SigningDate', 'SignificantEvents'
        )
        $supplied = @{
            ProposedDividend      = $PSBoundParameters.ContainsKey('ProposedDividend')
            AverageEmployees      = $PSBoundParameters.ContainsKey('AverageEmployees')
            SecuritiesMarketValue = $PSBoundParameters.ContainsKey('SecuritiesMarketValue')
            SigningPlace          = $PSBoundParameters.ContainsKey('SigningPlace')
            SigningDate           = $PSBoundParameters.ContainsKey('SigningDate')
            SignificantEvents     = $PSBoundParameters.ContainsKey('SignificantEvents')
        }
        $values = @{
            ProposedDividend      = $ProposedDividend
            AverageEmployees      = $AverageEmployees
            SecuritiesMarketValue = $SecuritiesMarketValue
            SigningPlace          = $SigningPlace
            SigningDate           = $SigningDate
            SignificantEvents     = $SignificantEvents
        }

        if (-not ($supplied.Values -contains $true)) {
            throw "Nothing to update. Specify at least one field, for example -SignificantEvents or -ProposedDividend."
        }

        $Path = Get-LedgerReportInputPath -JournalPath $JournalPath -FiscalYear $FiscalYear
        $existing = Read-LedgerReportInput -Path $Path

        # Rebuild an ordered dictionary honouring the canonical field order so the
        # written file is stable regardless of update order.
        $result = [ordered]@{}
        foreach ($key in $order) {
            if ($supplied[$key]) {
                if (-not [string]::IsNullOrEmpty($values[$key])) {
                    $result[$key] = $values[$key]
                }
            }
            elseif ($existing.Contains($key)) {
                $result[$key] = $existing[$key]
            }
        }

        if ($PSCmdlet.ShouldProcess($Path, "Update annual report input")) {
            Write-LedgerReportInput -Path $Path -Fields $result
        }
    }
}
