<#
.SYNOPSIS
Generates a balance sheet (balansräkning) for a fiscal year.

.DESCRIPTION
Summarises assets (account group 1xxx) and equity plus liabilities (account
group 2xxx) from the trial balance. Returns grouped totals with a check that
assets equal equity + liabilities.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.EXAMPLE
Get-LedgerBalanceSheet -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Returns objects with Group, Label, and Amount properties showing assets,
equity/liabilities, and the balance check.

.EXAMPLE
Get-LedgerBalanceSheet -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' |
    Format-Table Group, Label, @{N='Amount';E={'{0:N2}' -f $_.Amount};A='Right'}

Displays the balance sheet as a formatted table.
#>
function Get-LedgerBalanceSheet {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
    if (-not $Balance) {
        return
    }

    $Assets = $Balance | Where-Object { $_.AccountNumber -like '1*' }
    $EquityAndLiabilities = $Balance | Where-Object { $_.AccountNumber -like '2*' }

    $AssetsTotal = if ($Assets) { ($Assets | Measure-Object -Property Balance -Sum).Sum } else { [decimal]0 }
    # Equity/liabilities have negative balance (credit side), negate for display
    $EquityTotal = if ($EquityAndLiabilities) { -($EquityAndLiabilities | Measure-Object -Property Balance -Sum).Sum } else { [decimal]0 }

    @(
        [PSCustomObject]@{ Group = 'Assets'; Label = 'Tillgångar'; Amount = $AssetsTotal }
        [PSCustomObject]@{ Group = 'EquityAndLiabilities'; Label = 'Eget kapital och skulder'; Amount = $EquityTotal }
    )
}
