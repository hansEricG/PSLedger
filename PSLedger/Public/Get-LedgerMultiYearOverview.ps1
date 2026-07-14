<#
.SYNOPSIS
Builds a multi-year overview (flerårsöversikt) for the förvaltningsberättelse.

.DESCRIPTION
Produces one row per fiscal year for the requested number of years, ending with
the specified fiscal year and reaching back over the immediately preceding years.
Each row reports the key figures shown in a printed flerårsöversikt:
Nettoomsättning, Resultat efter finansiella poster and Årets resultat, plus the
Balansomslutning (total assets). Figures are taken from Get-LedgerIncomeStatement
and Get-LedgerBalanceSheet, so signs follow the same conventions.

Rows are returned newest year first, matching how a flerårsöversikt is printed
(current year in the leftmost column).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The most recent fiscal year to include (e.g. '2024-09_2025-08'). If omitted, uses
the current fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER Years
The number of years to include, counting back from -FiscalYear. Defaults to 3.
Fewer rows are returned when the journal has fewer years of history.

.EXAMPLE
Get-LedgerMultiYearOverview -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'

Returns up to three rows (2024/2025, 2023/2024, 2022/2023) with net sales, result
after financial items, net result and total assets.

.EXAMPLE
Get-LedgerMultiYearOverview -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' -Years 5 |
    Format-Table YearLabel, NetSales, ResultAfterFinancialItems, NetResult

Displays a five-year overview as a table similar to a printed flerårsöversikt.
#>
function Get-LedgerMultiYearOverview {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$Years = 3
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $AllYears = @(Get-LedgerFiscalYear -JournalPath $JournalPath)
        $Index = -1
        for ($i = 0; $i -lt $AllYears.Count; $i++) {
            if ($AllYears[$i].Name -eq $FiscalYear) {
                $Index = $i
                break
            }
        }
        if ($Index -lt 0) {
            throw "Fiscal year not found: $FiscalYear"
        }

        # Take up to $Years years ending at the requested year, newest first.
        $First = [Math]::Max(0, $Index - $Years + 1)
        for ($i = $Index; $i -ge $First; $i--) {
            $Name = $AllYears[$i].Name

            $Income = @(Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $Name)
            $Balance = @(Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $Name)

            $netSales = ($Income | Where-Object { $_.Group -eq 'NetSales' }).Amount
            $resultAfterFinancial = ($Income | Where-Object { $_.Group -eq 'ResultAfterFinancialItems' }).Amount
            $netResult = ($Income | Where-Object { $_.Group -eq 'NetResult' }).Amount
            $totalAssets = ($Balance | Where-Object { $_.Group -eq 'TotalAssets' }).Amount

            [PSCustomObject]@{
                FiscalYear                = $Name
                YearLabel                 = Format-LedgerYearLabel -FiscalYear $Name
                NetSales                  = if ($null -ne $netSales) { [decimal]$netSales } else { [decimal]0 }
                ResultAfterFinancialItems = if ($null -ne $resultAfterFinancial) { [decimal]$resultAfterFinancial } else { [decimal]0 }
                NetResult                 = if ($null -ne $netResult) { [decimal]$netResult } else { [decimal]0 }
                TotalAssets               = if ($null -ne $totalAssets) { [decimal]$totalAssets } else { [decimal]0 }
            }
        }
    }
}
