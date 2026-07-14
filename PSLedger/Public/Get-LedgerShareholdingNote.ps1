<#
.SYNOPSIS
Builds the shares and participations (aktier och andelar) note for an
årsredovisning: the carrying amount and market value of a holding.

.DESCRIPTION
Reports the carrying amount (bokfört värde) of a range of securities accounts,
taken from the closing balance, together with the market value (marknadsvärde).
The market value defaults to the SecuritiesMarketValue recorded with
Set-LedgerReportInput and can be overridden with -MarketValue.

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
The market value of the holding. Overrides the SecuritiesMarketValue recorded with
Set-LedgerReportInput.

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
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [int]$FromAccount = 1300,

        [Parameter()]
        [int]$ToAccount = 1399,

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

        if ($PSBoundParameters.ContainsKey('MarketValue')) {
            $MarketValueResolved = $MarketValue
        }
        else {
            $ReportInput = Get-LedgerReportInput -JournalPath $JournalPath -FiscalYear $FiscalYear
            $MarketValueResolved = if ($ReportInput.SecuritiesMarketValue) { [decimal]$ReportInput.SecuritiesMarketValue } else { $null }
        }

        [PSCustomObject]@{
            Label       = $Label
            FiscalYear  = $FiscalYear
            BookValue   = [decimal]$BookValue
            MarketValue = $MarketValueResolved
        }
    }
}
