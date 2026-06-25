<#
.SYNOPSIS
Generates an income statement (resultaträkning) for a fiscal year.

.DESCRIPTION
Builds a detailed income statement from the trial balance, grouping accounts
into the standard BAS sections. Operating revenue (account class 3) is split into
Nettoomsättning and Övriga rörelseintäkter. Operating expenses are split into
Material- och varukostnader (class 4), Övriga rörelsekostnader m.m. (classes 5-6
and account group 79), Personalkostnader (account groups 70-76) and Avskrivningar
(account groups 77-78). Financial items (account groups 80-87), other items
(account group 88) and tax (account group 89, excluding account 8999 Årets
resultat which is a result-appropriation transfer to equity) are reported
separately, with running subtotals for Rörelseresultat efter avskrivningar,
Resultat efter finansiella poster and Årets resultat.

Amounts use the income statement sign convention: revenue is positive, costs are
negative and a profit gives a positive Årets resultat.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.EXAMPLE
Get-LedgerIncomeStatement -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Returns objects with Section, Group, Label, and Amount properties showing every
income statement line plus the running subtotals.

.EXAMPLE
Get-LedgerIncomeStatement -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' |
    Format-Table Label, @{N='Amount';E={'{0:N2}' -f $_.Amount};A='Right'}

Displays the income statement as a formatted table similar to a printed
resultaträkning.
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

        # Income statement amounts use the opposite sign of the raw balance:
        # revenue (credit) becomes positive, costs (debit) become negative.
        function Get-Amount {
            param ([int]$From, [int]$To)
            $Sum = [decimal]0
            foreach ($Row in $Balance) {
                $Number = 0
                if ([int]::TryParse($Row.AccountNumber, [ref]$Number) -and $Number -ge $From -and $Number -le $To) {
                    $Sum += $Row.Balance
                }
            }
            -$Sum
        }

        $NetSales = Get-Amount -From 3000 -To 3799
        $OtherRevenue = Get-Amount -From 3800 -To 3999
        $MaterialCosts = Get-Amount -From 4000 -To 4999
        $OtherExpenses = (Get-Amount -From 5000 -To 6999) + (Get-Amount -From 7900 -To 7999)
        $PersonnelCosts = Get-Amount -From 7000 -To 7699
        $Depreciation = Get-Amount -From 7700 -To 7899
        $OperatingResult = Get-Amount -From 3000 -To 7999
        $FinancialItems = Get-Amount -From 8000 -To 8799
        $ResultAfterFinancial = Get-Amount -From 3000 -To 8799
        $OtherItems = Get-Amount -From 8800 -To 8899
        # Account 8999 (Årets resultat) holds the year-end result appropriation
        # (a transfer to equity), not a P&L item, so it is excluded here.
        $Tax = Get-Amount -From 8900 -To 8998
        $NetResult = Get-Amount -From 3000 -To 8998

        @(
            [PSCustomObject]@{ Section = 'Revenue'; Group = 'NetSales'; Label = 'Nettoomsättning'; Amount = $NetSales }
            [PSCustomObject]@{ Section = 'Revenue'; Group = 'OtherOperatingRevenue'; Label = 'Övriga rörelseintäkter'; Amount = $OtherRevenue }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'MaterialCosts'; Label = 'Material- och varukostnader'; Amount = $MaterialCosts }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'OtherOperatingExpenses'; Label = 'Övriga rörelsekostnader m.m'; Amount = $OtherExpenses }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'PersonnelCosts'; Label = 'Personalkostnader'; Amount = $PersonnelCosts }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'Depreciation'; Label = 'Avskrivningar'; Amount = $Depreciation }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'OperatingResult'; Label = 'Rörelseresultat efter avskrivningar'; Amount = $OperatingResult }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'FinancialItems'; Label = 'Finansiella intäkter och kostnader'; Amount = $FinancialItems }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'ResultAfterFinancialItems'; Label = 'Resultat efter finansiella poster'; Amount = $ResultAfterFinancial }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'OtherItems'; Label = 'Övriga poster'; Amount = $OtherItems }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'Tax'; Label = 'Skatt'; Amount = $Tax }
            [PSCustomObject]@{ Section = 'Expenses'; Group = 'NetResult'; Label = 'Årets resultat'; Amount = $NetResult }
        )
    }
}
