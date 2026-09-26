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

.PARAMETER AnnualMeetingDate
The date of the årsstämma that adopts the report, e.g. '2025-10-01'. Shown in
the fastställelseintyg on the cover page; when omitted a blank line is printed.

.PARAMETER CertificatePlace
The place (ort) printed on the fastställelseintyg. Defaults to the company's
registered office (RegisteredOffice in the journal metadata).

.PARAMETER CertificateSigner
The board member who signs the fastställelseintyg. Defaults to the first board
member in the journal metadata.

.PARAMETER ComparativeFiguresNote
An explanation shown under "Jämförelsetal" in the notes, for example when the
comparison figures differ from the previously adopted annual report because an
error has been corrected.

.PARAMETER Framework
The regelverk the annual report is prepared under: 'K2' (BFNAR 2016:10, the
default) or 'K3' (BFNAR 2012:1). Selects the accounting principles, the line
items and the notes. The first K3 year (the previous year was not K3) gets a
note on the transition to K3.

.PARAMETER TransitionNote
Additional text for the K3 transition note, for example how assets have been
reclassified or which transition reliefs in K3 chapter 35 have been applied.

.PARAMETER DeferredTaxStatement
Text on deferred tax (uppskjuten skatt) added to the K3 accounting principles,
for example why no deferred tax asset is recognised on underskottsavdrag.

.PARAMETER PledgedAssets
Ställda säkerheter shown in the notes. Under K3 'Inga' is shown when omitted.

.PARAMETER ContingentLiabilities
Eventualförpliktelser shown in the notes. Under K3 'Inga' is shown when omitted.

.PARAMETER EventsAfterBalanceDate
Väsentliga händelser efter räkenskapsårets slut, shown in the
förvaltningsberättelse and as a note when set.

.PARAMETER Ownership
Ägarförhållanden shown in the förvaltningsberättelse, for example owners
holding more than ten per cent of the shares (K3 punkt 3.7).

.EXAMPLE
Set-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -SignificantEvents 'Inga väsentliga händelser.' -SigningPlace 'Gävle'

Records the significant events text and signing place for the year.

.EXAMPLE
Set-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -ProposedDividend 0 -AverageEmployees 0 -SecuritiesMarketValue 277579 -SigningDate '2025-10-01'

Records the vinstdisposition, personnel and securities figures used by the notes
together with the signing date.

.EXAMPLE
Set-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -AnnualMeetingDate '2025-10-01' -CertificateSigner 'Anna Andersson'

Records the årsstämma date and who signs the fastställelseintyg on the cover page.

.EXAMPLE
Set-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2026-09_2027-08' -Framework K3 `
    -Ownership 'Anna Andersson äger samtliga aktier.' `
    -DeferredTaxStatement 'Uppskjuten skattefordran på underskottsavdrag redovisas inte eftersom det är osäkert när de kan utnyttjas.'

Prepares the 2026/27 annual report under K3 with ägarförhållanden and a statement
on deferred tax.
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
        [string]$SigningDate,

        [Parameter()]
        [string]$AnnualMeetingDate,

        [Parameter()]
        [string]$CertificatePlace,

        [Parameter()]
        [string]$CertificateSigner,

        [Parameter()]
        [string]$ComparativeFiguresNote,

        [Parameter()]
        [ValidateSet('K2', 'K3', '')]
        [string]$Framework,

        [Parameter()]
        [string]$TransitionNote,

        [Parameter()]
        [string]$DeferredTaxStatement,

        [Parameter()]
        [string]$PledgedAssets,

        [Parameter()]
        [string]$ContingentLiabilities,

        [Parameter()]
        [string]$EventsAfterBalanceDate,

        [Parameter()]
        [string]$Ownership
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
            'SigningPlace', 'SigningDate', 'AnnualMeetingDate', 'CertificatePlace',
            'CertificateSigner', 'Framework', 'PledgedAssets', 'ContingentLiabilities',
            'ComparativeFiguresNote', 'TransitionNote', 'DeferredTaxStatement',
            'Ownership', 'EventsAfterBalanceDate', 'SignificantEvents'
        )
        $supplied = @{}
        $values = @{}
        foreach ($key in $order) {
            $supplied[$key] = $PSBoundParameters.ContainsKey($key)
            $values[$key] = $PSBoundParameters[$key]
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
