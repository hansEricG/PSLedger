<#
.SYNOPSIS
Builds an annual report (årsredovisning) combining the income statement and balance
sheet with comparison figures from the previous year.

.DESCRIPTION
Combines Get-LedgerIncomeStatement and Get-LedgerBalanceSheet into a single sequence
of report lines for a fiscal year. Each line carries the current year's amount and,
unless -NoComparison is used, the corresponding amount from the immediately
preceding fiscal year (matched by its Group) so the report reads like a printed
årsredovisning with jämförelseår.

Every output object has a Statement property ('IncomeStatement' or 'BalanceSheet')
in addition to the Section, Group, Label, Amount, ComparisonAmount, FiscalYear and
ComparisonFiscalYear properties. ComparisonAmount and ComparisonFiscalYear are null
when there is no preceding year or -NoComparison is specified.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER NoComparison
Omits the previous year's comparison figures.

.EXAMPLE
Get-LedgerAnnualReport -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12'

Returns the combined income statement and balance sheet for 2024 with 2023 as the
comparison year (if it exists).

.EXAMPLE
Get-LedgerAnnualReport -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12' |
    Format-Table Label,
        @{N='2024';E={'{0:N2}' -f $_.Amount};A='Right'},
        @{N='2023';E={ if ($null -ne $_.ComparisonAmount) { '{0:N2}' -f $_.ComparisonAmount } };A='Right'}

Displays the annual report as a two-column table with the current and previous
year's figures side by side.
#>
function Get-LedgerAnnualReport {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [switch]$NoComparison
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        # Locate the immediately preceding fiscal year for comparison figures.
        $ComparisonYear = $null
        if (-not $NoComparison) {
            $Years = @(Get-LedgerFiscalYear -JournalPath $JournalPath)
            $Index = -1
            for ($i = 0; $i -lt $Years.Count; $i++) {
                if ($Years[$i].Name -eq $FiscalYear) {
                    $Index = $i
                    break
                }
            }
            if ($Index -gt 0) {
                $ComparisonYear = $Years[$Index - 1].Name
            }
        }

        $IncomeCurrent = @(Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $FiscalYear)
        $BalanceCurrent = @(Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear)

        # Index the previous year's lines by Group for quick lookup.
        $IncomePrevious = @{}
        $BalancePrevious = @{}
        if ($ComparisonYear) {
            foreach ($Row in @(Get-LedgerIncomeStatement -JournalPath $JournalPath -FiscalYear $ComparisonYear)) {
                $IncomePrevious[$Row.Group] = $Row.Amount
            }
            foreach ($Row in @(Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $ComparisonYear)) {
                $BalancePrevious[$Row.Group] = $Row.Amount
            }
        }

        foreach ($Row in $IncomeCurrent) {
            $Comparison = if ($ComparisonYear -and $IncomePrevious.ContainsKey($Row.Group)) {
                $IncomePrevious[$Row.Group]
            }
            else {
                $null
            }
            [PSCustomObject]@{
                Statement            = 'IncomeStatement'
                Section              = $Row.Section
                Group                = $Row.Group
                Label                = $Row.Label
                Amount               = $Row.Amount
                ComparisonAmount     = $Comparison
                FiscalYear           = $FiscalYear
                ComparisonFiscalYear = $ComparisonYear
            }
        }

        foreach ($Row in $BalanceCurrent) {
            $Comparison = if ($ComparisonYear -and $BalancePrevious.ContainsKey($Row.Group)) {
                $BalancePrevious[$Row.Group]
            }
            else {
                $null
            }
            [PSCustomObject]@{
                Statement            = 'BalanceSheet'
                Section              = $Row.Section
                Group                = $Row.Group
                Label                = $Row.Label
                Amount               = $Row.Amount
                ComparisonAmount     = $Comparison
                FiscalYear           = $FiscalYear
                ComparisonFiscalYear = $ComparisonYear
            }
        }
    }
}
