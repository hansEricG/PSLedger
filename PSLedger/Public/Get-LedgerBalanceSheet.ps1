<#
.SYNOPSIS
Generates a balance sheet (balansräkning) for a fiscal year.

.DESCRIPTION
Builds a detailed balance sheet from the trial balance, grouping accounts into
the standard BAS sections. Assets (account class 1) are split into fixed assets,
inventory, accounts receivable, other receivables and cash/bank. Equity and
liabilities (account class 2) are split into equity, untaxed reserves and
provisions, long-term liabilities and short-term liabilities. The unclosed
result for the year (account classes 3-8) is reported on a separate 'Resultat'
line.

Amounts are reported with their natural sign: assets carry a debit balance
(positive) while equity and liabilities carry a credit balance (negative). Each
section ends with a summary row, and the two summary rows are equal in magnitude
with opposite signs when the books balance.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.EXAMPLE
Get-LedgerBalanceSheet -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Returns objects with Section, Group, Label, and Amount properties showing every
balance sheet line plus the section totals.

.EXAMPLE
Get-LedgerBalanceSheet -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' |
    Format-Table Label, @{N='Amount';E={'{0:N2}' -f $_.Amount};A='Right'}

Displays the balance sheet as a formatted table similar to a printed
balansräkning.
#>
function Get-LedgerBalanceSheet {
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

        $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
        if (-not $Balance) {
            return
        }

        function Get-RangeSum {
            param ([int]$From, [int]$To)
            $Sum = [decimal]0
            foreach ($Row in $Balance) {
                $Number = 0
                if ([int]::TryParse($Row.AccountNumber, [ref]$Number) -and $Number -ge $From -and $Number -le $To) {
                    $Sum += $Row.Balance
                }
            }
            $Sum
        }

        $FixedAssets = Get-RangeSum -From 1000 -To 1399
        $Inventory = Get-RangeSum -From 1400 -To 1499
        $Receivables = Get-RangeSum -From 1500 -To 1599
        $OtherReceivables = Get-RangeSum -From 1600 -To 1799
        $CashAndBank = Get-RangeSum -From 1800 -To 1999
        $TotalAssets = Get-RangeSum -From 1000 -To 1999

        $Equity = Get-RangeSum -From 2000 -To 2099
        $Result = Get-RangeSum -From 3000 -To 8999
        $UntaxedReserves = Get-RangeSum -From 2100 -To 2299
        $LongTermLiabilities = Get-RangeSum -From 2300 -To 2399
        $ShortTermLiabilities = Get-RangeSum -From 2400 -To 2999
        $TotalEquityAndLiabilities = Get-RangeSum -From 2000 -To 8999

        @(
            [PSCustomObject]@{ Section = 'Assets'; Group = 'FixedAssets'; Label = 'Anläggningstillgångar'; Amount = $FixedAssets }
            [PSCustomObject]@{ Section = 'Assets'; Group = 'Inventory'; Label = 'Lager och pågående arbeten'; Amount = $Inventory }
            [PSCustomObject]@{ Section = 'Assets'; Group = 'AccountsReceivable'; Label = 'Kundfordringar'; Amount = $Receivables }
            [PSCustomObject]@{ Section = 'Assets'; Group = 'OtherReceivables'; Label = 'Övriga kortfristiga fordringar'; Amount = $OtherReceivables }
            [PSCustomObject]@{ Section = 'Assets'; Group = 'CashAndBank'; Label = 'Likvida medel'; Amount = $CashAndBank }
            [PSCustomObject]@{ Section = 'Assets'; Group = 'TotalAssets'; Label = 'Summa tillgångar'; Amount = $TotalAssets }
            [PSCustomObject]@{ Section = 'EquityAndLiabilities'; Group = 'Equity'; Label = 'Eget kapital'; Amount = $Equity }
            [PSCustomObject]@{ Section = 'EquityAndLiabilities'; Group = 'Result'; Label = 'Resultat'; Amount = $Result }
            [PSCustomObject]@{ Section = 'EquityAndLiabilities'; Group = 'UntaxedReserves'; Label = 'Obeskattade reserver och avsättningar'; Amount = $UntaxedReserves }
            [PSCustomObject]@{ Section = 'EquityAndLiabilities'; Group = 'LongTermLiabilities'; Label = 'Långfristiga skulder'; Amount = $LongTermLiabilities }
            [PSCustomObject]@{ Section = 'EquityAndLiabilities'; Group = 'ShortTermLiabilities'; Label = 'Kortfristiga skulder'; Amount = $ShortTermLiabilities }
            [PSCustomObject]@{ Section = 'EquityAndLiabilities'; Group = 'TotalEquityAndLiabilities'; Label = 'Summa eget kapital och skulder'; Amount = $TotalEquityAndLiabilities }
        )
    }
}
