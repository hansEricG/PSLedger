<#
.SYNOPSIS
Generates an income statement (resultaträkning) for a fiscal year.

.DESCRIPTION
Summarises revenue (account group 3xxx) and expenses (account groups 4xxx-7xxx)
from the trial balance and returns grouped totals. Also includes financial items
(8xxx) and the overall net result.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.EXAMPLE
Get-LedgerIncomeStatement -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Returns objects with Group, Label, and Amount properties showing revenue, expenses,
and net result.

.EXAMPLE
Get-LedgerIncomeStatement -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' |
    Format-Table Group, Label, @{N='Amount';E={'{0:N2}' -f $_.Amount};A='Right'}

Displays the income statement as a formatted table.
#>
function Get-LedgerIncomeStatement {
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

        $Revenue = $Balance | Where-Object { $_.AccountNumber -like '3*' }
        $CostOfGoods = $Balance | Where-Object { $_.AccountNumber -like '4*' }
        $OperatingExpenses = $Balance | Where-Object { $_.AccountNumber -match '^[567]' }
        $Financial = $Balance | Where-Object { $_.AccountNumber -like '8*' }

        # Revenue is stored as negative balance (credit), so negate for display
        $RevenueTotal = if ($Revenue) { -($Revenue | Measure-Object -Property Balance -Sum).Sum } else { [decimal]0 }
        $CostOfGoodsTotal = if ($CostOfGoods) { ($CostOfGoods | Measure-Object -Property Balance -Sum).Sum } else { [decimal]0 }
        $OperatingExpensesTotal = if ($OperatingExpenses) { ($OperatingExpenses | Measure-Object -Property Balance -Sum).Sum } else { [decimal]0 }
        $FinancialTotal = if ($Financial) { -($Financial | Measure-Object -Property Balance -Sum).Sum } else { [decimal]0 }

        $GrossProfit = $RevenueTotal - $CostOfGoodsTotal
        $OperatingResult = $GrossProfit - $OperatingExpensesTotal
        $NetResult = $OperatingResult + $FinancialTotal

        @(
            [PSCustomObject]@{ Group = 'Revenue'; Label = 'Nettoomsättning'; Amount = $RevenueTotal }
            [PSCustomObject]@{ Group = 'CostOfGoods'; Label = 'Kostnad sålda varor'; Amount = -$CostOfGoodsTotal }
            [PSCustomObject]@{ Group = 'GrossProfit'; Label = 'Bruttovinst'; Amount = $GrossProfit }
            [PSCustomObject]@{ Group = 'OperatingExpenses'; Label = 'Rörelsekostnader'; Amount = -$OperatingExpensesTotal }
            [PSCustomObject]@{ Group = 'OperatingResult'; Label = 'Rörelseresultat'; Amount = $OperatingResult }
            [PSCustomObject]@{ Group = 'Financial'; Label = 'Finansiella poster'; Amount = $FinancialTotal }
            [PSCustomObject]@{ Group = 'NetResult'; Label = 'Årets resultat'; Amount = $NetResult }
        )
    }
}

