<#
.SYNOPSIS
Builds the shares and participations (aktier och andelar) note for an
årsredovisning: the carrying amount and market value of a holding.

.DESCRIPTION
Reports the carrying amount (bokfört värde) of a range of securities accounts,
taken from the closing balance, together with the market value (marknadsvärde).
The market value is resolved in this order: -MarketValue; otherwise the total
market value of the holdings recorded with Set-LedgerHolding on accounts in the
range; otherwise the SecuritiesMarketValue recorded with Set-LedgerReportInput.
MarketValueSource tells which one was used ('Parameter', 'Holdings' or
'ReportInput').

When holdings are recorded, a warning is emitted for each account or holding
whose market value is below its book value (prompting an impairment assessment
under K2), and when SecuritiesMarketValue differs from the holdings total.

The account range defaults to the financial fixed asset securities accounts
(1300-1399) and can be changed with -FromAccount/-ToAccount, for example to
1800-1899 for short-term (kortfristiga) holdings.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-09_2025-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER FromAccount
The first account number of the securities range. Defaults to 1300.

.PARAMETER ToAccount
The last account number of the securities range. Defaults to 1399.

.PARAMETER MarketValue
The market value of the holding. Overrides the holdings total and the
SecuritiesMarketValue recorded with Set-LedgerReportInput.

.PARAMETER Label
A label for the note. Defaults to 'Aktier och andelar'.

.EXAMPLE
Get-LedgerShareholdingNote -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'

Returns the carrying amount of the financial fixed asset securities together with
the recorded market value.

.EXAMPLE
Get-LedgerShareholdingNote -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -FromAccount 1810 -ToAccount 1810 -MarketValue 150000 -Label 'Andelar i börsnoterade företag'

Reports a short-term holding's carrying amount with an explicit market value.
#>
function Get-LedgerShareholdingNote {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [ValidatePattern('^\d+$')]
        [string]$FromAccount = '1300',

        [Parameter()]
        [ValidatePattern('^\d+$')]
        [string]$ToAccount = '1399',

        [Parameter()]
        [decimal]$MarketValue,

        [Parameter()]
        [string]$Label = 'Aktier och andelar'
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $Balance = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)

        $BookValue = [decimal]0
        foreach ($Row in $Balance) {
            $Number = 0
            if ([int]::TryParse($Row.AccountNumber, [ref]$Number) -and $Number -ge $FromAccount -and $Number -le $ToAccount) {
                $BookValue += $Row.Balance
            }
        }

        $Valuation = Get-LedgerHoldingValuation -JournalPath $JournalPath -FiscalYear $FiscalYear -FromAccount $FromAccount -ToAccount $ToAccount
        $ReportInput = Get-LedgerReportInput -JournalPath $JournalPath -FiscalYear $FiscalYear
        $RecordedValue = if ($ReportInput.SecuritiesMarketValue) { [decimal]$ReportInput.SecuritiesMarketValue } else { $null }

        if ($PSBoundParameters.ContainsKey('MarketValue')) {
            $MarketValueResolved = $MarketValue
            $MarketValueSource = 'Parameter'
        }
        elseif ($Valuation.HasHoldings) {
            $MarketValueResolved = $Valuation.MarketValue
            $MarketValueSource = 'Holdings'
            if ($null -ne $RecordedValue -and $RecordedValue -ne $MarketValueResolved) {
                Write-Warning "SecuritiesMarketValue ($RecordedValue) differs from the holdings total ($MarketValueResolved) for $FiscalYear; the holdings total is used."
            }
        }
        else {
            $MarketValueResolved = $RecordedValue
            $MarketValueSource = if ($null -ne $RecordedValue) { 'ReportInput' } else { $null }
        }

        if ($Valuation.HasHoldings) {
            $findings = @(Get-LedgerHoldingValuationFinding -Valuation $Valuation)
            foreach ($finding in $findings) {
                Write-Warning "${FiscalYear}: $finding"
            }
            if ($findings.Count -eq 0 -and $MarketValueSource -eq 'Holdings' -and $MarketValueResolved -lt $BookValue) {
                Write-Warning "${FiscalYear}: total market value $MarketValueResolved of accounts $FromAccount-$ToAccount is below book value $BookValue."
            }
        }

        [PSCustomObject]@{
            Label             = $Label
            FiscalYear        = $FiscalYear
            BookValue         = [decimal]$BookValue
            MarketValue       = $MarketValueResolved
            MarketValueSource = $MarketValueSource
        }
    }
}
