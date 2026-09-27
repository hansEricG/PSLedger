<#
.SYNOPSIS
Returns the securities holdings (innehav) recorded for a fiscal year.

.DESCRIPTION
Reads the holdings stored in the fiscal year's holdings.txt (recorded with
Set-LedgerHolding) and returns one object per holding with the Account, Name,
Isin, Quantity, Price, Currency, FxRate, PriceDate, Source, BookValue and Cost
fields, plus the computed MarketValue in SEK (Quantity * Price * FxRate).

When the holding has a BookValue, Difference (MarketValue - BookValue) and
BelowBookValue are also set, so the output can be used directly as a supporting
schedule (underlag) for the shares and participations note and for the
impairment assessment. When it has both BookValue and Cost, Reversible is the
amount of an earlier write-down that may be reversed (återföring): the lower of
MarketValue and Cost, less BookValue (never negative). Rule is 'FixedAsset' for
13xx accounts, 'Current' for 18xx accounts and 'Other' otherwise.

Returns nothing when no holdings are recorded.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-09_2025-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER Account
Only return holdings on this account.

.PARAMETER Name
Only return holdings whose name matches this value. Wildcards are supported.

.EXAMPLE
Get-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'

Lists all holdings for the year with their market values.

.EXAMPLE
Get-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' -Account 1350 |
    Select-Object Name, Isin, Quantity, Price, Currency, MarketValue, BookValue, Difference |
    Export-Csv .\underlag-aktier-2025.csv -NoTypeInformation -Encoding utf8

Exports a per-holding schedule for account 1350 as supporting documentation.
#>
function Get-LedgerHolding {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$FiscalYear,

        [Parameter()]
        [ValidatePattern('^\d+$')]
        [string]$Account,

        [Parameter()]
        [string]$Name
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        $valuation = Get-LedgerHoldingValuation -JournalPath $JournalPath -FiscalYear $FiscalYear
        foreach ($h in $valuation.Holdings) {
            if ($Account -and $h.Account -ne $Account) { continue }
            if ($Name -and $h.Name -notlike $Name) { continue }
            [PSCustomObject]@{
                FiscalYear     = $FiscalYear
                Account        = $h.Account
                Name           = $h.Name
                Isin           = $h.Isin
                Quantity       = $h.Quantity
                Price          = $h.Price
                Currency       = $h.Currency
                FxRate         = $h.FxRate
                PriceDate      = $h.PriceDate
                Source         = $h.Source
                MarketValue    = $h.MarketValue
                BookValue      = $h.BookValue
                Cost           = $h.Cost
                Difference     = $h.Difference
                BelowBookValue = $h.BelowBookValue
                Reversible     = $h.Reversible
                Rule           = $h.Rule
            }
        }
    }
}
