<#
.SYNOPSIS
Exports a complete annual report (årsredovisning) to a text, Markdown or Word (.docx)
file.

.DESCRIPTION
Renders a full K2 årsredovisning for a fiscal year and writes it to a file. The
document contains the sections of a printed annual report for a small Swedish limited
company: a heading with company name, organisation number and the fiscal year date
range, förvaltningsberättelse (verksamheten, väsentliga händelser, flerårsöversikt and
förslag till vinstdisposition), resultaträkning and balansräkning with a Not column and
a comparison year, noter (redovisningsprinciper, medelantal anställda, and the
auto-detected notes for anläggningstillgångar, aktier och andelar and eget kapital) and
finally underskrifter with a fastställelseintyg.

Stable company information (säte, verksamhetsföremål, antal aktier, styrelseledamöter)
is read from the journal metadata via Get-LedgerCompanyProfile. Year-specific narrative
and decision data (väsentliga händelser, föreslagen utdelning, medelantal anställda,
marknadsvärde och ort/datum för underskrift) is read from the fiscal year's report.txt
via Get-LedgerReportInput.

Fixed-asset and shareholding notes are auto-detected from the standard BAS account
ranges; a note is only included when the relevant accounts carry a balance. Amounts use
Swedish formatting (space thousands separator) and are shown in whole kronor. All text
formats are written as UTF-8.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal set via
Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-09_2025-08'). If omitted, uses the current fiscal
year set via Set-LedgerCurrentFiscalYear.

.PARAMETER Path
Destination path for the report file.

.PARAMETER Format
The output format: 'Text' (fixed-width columns, default), 'Markdown' (tables) or 'Word'
(a .docx document).

.PARAMETER NoComparison
Omits the previous year's comparison column.

.PARAMETER Force
Overwrite the destination file if it already exists.

.EXAMPLE
Export-LedgerAnnualReport -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' -Path .\arsredovisning.txt

Writes a full plain-text annual report for 2024/2025 with the previous year as the
comparison column.

.EXAMPLE
Export-LedgerAnnualReport -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -Path .\arsredovisning.docx -Format Word -Force

Writes the complete annual report as a Word document, overwriting any existing file.
#>
function Export-LedgerAnnualReport {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Text', 'Markdown', 'Word')]
        [string]$Format = 'Text',

        [Parameter()]
        [switch]$NoComparison,

        [Parameter()]
        [switch]$Force
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        if ((Test-Path $Path) -and -not $Force) {
            throw "Destination file already exists: $Path. Use -Force to overwrite."
        }

        $blocks = @(Build-LedgerAnnualReportBlocks -JournalPath $JournalPath -FiscalYear $FiscalYear -NoComparison:$NoComparison)

        switch ($Format) {
            'Word' {
                ConvertTo-LedgerReportDocx -Block $blocks -Path $Path
            }
            'Markdown' {
                ConvertTo-LedgerReportMarkdown -Block $blocks | Set-Content -Path $Path -Encoding UTF8
            }
            default {
                ConvertTo-LedgerReportText -Block $blocks | Set-Content -Path $Path -Encoding UTF8
            }
        }
    }
}
