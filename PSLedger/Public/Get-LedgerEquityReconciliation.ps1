<#
.SYNOPSIS
Builds the change in equity (förändring av eget kapital) for a fiscal year, the
data behind the "Eget kapital" note in an årsredovisning.

.DESCRIPTION
Reports the opening balance, the change during the year and the closing balance
for each equity component of a limited company (aktiebolag): Aktiekapital
(accounts 2081-2084), Bundna reserver (2085-2089), Balanserat resultat
(2090-2098) and Årets resultat (2099 and the unclosed profit and loss result).

Amounts are presented as positive equity figures (a profit increases equity).
The previous year's result carried into the opening balance of account 2099 is
folded into the Balanserat resultat opening balance, and the current year's
result is reported on its own Årets resultat line, so the table reads like a
printed förändring av eget kapital. The rows reconcile to the equity and result
lines of Get-LedgerBalanceSheet.

Each output object has Component, Label, OpeningBalance, Change and ClosingBalance
properties, followed by a Total row.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-09_2025-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.EXAMPLE
Get-LedgerEquityReconciliation -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'

Returns the opening balance, change and closing balance for each equity component.

.EXAMPLE
Get-LedgerEquityReconciliation -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' |
    Format-Table Label, OpeningBalance, Change, ClosingBalance

Displays the change in equity as a table similar to a printed note.
#>
function Get-LedgerEquityReconciliation {
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

        # Sum a property (OpeningBalance or Balance) over an account range. Equity
        # carries a credit (negative) balance; negate so figures read as positive.
        function Get-EquitySum {
            param ([int]$From, [int]$To, [string]$Property)
            $Sum = [decimal]0
            foreach ($Row in $Balance) {
                $Number = 0
                if ([int]::TryParse($Row.AccountNumber, [ref]$Number) -and $Number -ge $From -and $Number -le $To) {
                    $Sum += $Row.$Property
                }
            }
            -$Sum
        }

        # Share capital and restricted reserves: opening and closing per range.
        $ShareOpen = Get-EquitySum -From 2081 -To 2084 -Property 'OpeningBalance'
        $ShareClose = Get-EquitySum -From 2081 -To 2084 -Property 'Balance'
        $ReservesOpen = Get-EquitySum -From 2085 -To 2089 -Property 'OpeningBalance'
        $ReservesClose = Get-EquitySum -From 2085 -To 2089 -Property 'Balance'

        # Retained earnings: opening includes the previous year's result carried
        # into account 2099's opening balance (it becomes disposable at year start).
        $RetainedOpenBase = Get-EquitySum -From 2090 -To 2098 -Property 'OpeningBalance'
        $PriorResultCarried = Get-EquitySum -From 2099 -To 2099 -Property 'OpeningBalance'
        $RetainedOpen = $RetainedOpenBase + $PriorResultCarried
        $RetainedCloseBase = Get-EquitySum -From 2090 -To 2098 -Property 'Balance'
        $RetainedClose = $RetainedCloseBase + $PriorResultCarried

        # Current year result: the change in account 2099 during the year plus any
        # unclosed profit and loss result (classes 3-8), so it is correct whether
        # or not the year has been closed.
        $Result2099Change = (Get-EquitySum -From 2099 -To 2099 -Property 'Balance') - $PriorResultCarried
        $UnclosedResult = Get-EquitySum -From 3000 -To 8999 -Property 'Balance'
        $YearResult = $Result2099Change + $UnclosedResult

        $components = @(
            [PSCustomObject]@{ Component = 'ShareCapital'; Label = 'Aktiekapital'; OpeningBalance = $ShareOpen; ClosingBalance = $ShareClose }
            [PSCustomObject]@{ Component = 'RestrictedReserves'; Label = 'Bundna reserver'; OpeningBalance = $ReservesOpen; ClosingBalance = $ReservesClose }
            [PSCustomObject]@{ Component = 'RetainedEarnings'; Label = 'Balanserat resultat'; OpeningBalance = $RetainedOpen; ClosingBalance = $RetainedClose }
            [PSCustomObject]@{ Component = 'YearResult'; Label = 'Årets resultat'; OpeningBalance = [decimal]0; ClosingBalance = $YearResult }
        )

        $totalOpen = [decimal]0
        $totalClose = [decimal]0
        foreach ($c in $components) {
            $change = $c.ClosingBalance - $c.OpeningBalance
            $totalOpen += $c.OpeningBalance
            $totalClose += $c.ClosingBalance
            [PSCustomObject]@{
                Component      = $c.Component
                Label          = $c.Label
                OpeningBalance = $c.OpeningBalance
                Change         = $change
                ClosingBalance = $c.ClosingBalance
            }
        }

        [PSCustomObject]@{
            Component      = 'Total'
            Label          = 'Summa eget kapital'
            OpeningBalance = $totalOpen
            Change         = $totalClose - $totalOpen
            ClosingBalance = $totalClose
        }
    }
}
