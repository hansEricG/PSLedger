<#
.SYNOPSIS
Exports an annual report (årsredovisning) to a formatted text or Markdown file.

.DESCRIPTION
Renders the combined income statement and balance sheet produced by
Get-LedgerAnnualReport to a human-readable document and writes it to a file. The
document has a header with the company name, organisation number and the fiscal
year date range, followed by a Resultaträkning section and a Balansräkning section.

When a preceding fiscal year exists (and -NoComparison is not used) each amount is
shown next to the previous year's figure, one column per year, mirroring a printed
årsredovisning with jämförelseår. Amounts use Swedish formatting (space thousands
separator, comma decimal). The file is written as UTF-8.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER Path
Destination path for the report file.

.PARAMETER Format
The output format: 'Text' (fixed-width columns, default) or 'Markdown' (tables).

.PARAMETER NoComparison
Omits the previous year's comparison column.

.PARAMETER Force
Overwrite the destination file if it already exists.

.EXAMPLE
Export-LedgerAnnualReport -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12' -Path .\arsredovisning-2024.txt

Writes a plain-text annual report for 2024 with 2023 as the comparison year.

.EXAMPLE
Export-LedgerAnnualReport -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12' `
    -Path .\arsredovisning-2024.md -Format Markdown -Force

Writes the annual report as a Markdown document, overwriting any existing file.
#>
function Export-LedgerAnnualReport {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Text', 'Markdown')]
        [string]$Format = 'Text',

        [Parameter()]
        [switch]$NoComparison,

        [Parameter()]
        [switch]$Force
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        if ((Test-Path $Path) -and -not $Force) {
            throw "Destination file already exists: $Path. Use -Force to overwrite."
        }

        $Journal = Get-LedgerJournal -Path $JournalPath
        $Year = Get-LedgerFiscalYear -JournalPath $JournalPath | Where-Object { $_.Name -eq $FiscalYear }

        $Report = @(Get-LedgerAnnualReport -JournalPath $JournalPath -FiscalYear $FiscalYear -NoComparison:$NoComparison)
        $ComparisonYear = if ($Report) { $Report[0].ComparisonFiscalYear } else { $null }

        # Column labels use the fiscal year's end year (e.g. '2024-01_2024-12' -> 2024).
        function Get-YearLabel {
            param ([string]$Name)
            if ($Name -and $Name -match '_(\d{4})-\d{2}$') { $Matches[1] } else { $Name }
        }
        $CurrentLabel = Get-YearLabel -Name $FiscalYear
        $ComparisonLabel = if ($ComparisonYear) { Get-YearLabel -Name $ComparisonYear } else { $null }

        $Culture = [System.Globalization.CultureInfo]::GetCultureInfo('sv-SE')
        function Format-Amount {
            param ($Value)
            if ($null -eq $Value) { return '' }
            ([decimal]$Value).ToString('N2', $Culture)
        }

        $IncomeRows = $Report | Where-Object { $_.Statement -eq 'IncomeStatement' }
        $BalanceRows = $Report | Where-Object { $_.Statement -eq 'BalanceSheet' }

        $DateRange = if ($Year) {
            "$(([datetime]$Year.StartDate).ToString('yyyy-MM-dd')) - $(([datetime]$Year.EndDate).ToString('yyyy-MM-dd'))"
        }
        else {
            $FiscalYear
        }
        $Heading = $Journal.Name
        if ($Journal.OrgNumber) {
            $Heading = "$Heading ($($Journal.OrgNumber))"
        }

        $nl = "`r`n"
        $sb = New-Object System.Text.StringBuilder
        $append = { param($line) [void]$sb.Append($line); [void]$sb.Append($nl) }

        if ($Format -eq 'Markdown') {
            & $append "# Årsredovisning"
            & $append ''
            & $append "**$Heading**"
            & $append ''
            & $append "Räkenskapsår: $DateRange"
            & $append ''

            $header = if ($ComparisonLabel) { "| Post | $CurrentLabel | $ComparisonLabel |" } else { "| Post | $CurrentLabel |" }
            $divider = if ($ComparisonLabel) { '| --- | ---: | ---: |' } else { '| --- | ---: |' }

            $writeSection = {
                param($Title, $Rows)
                & $append "## $Title"
                & $append ''
                & $append $header
                & $append $divider
                foreach ($r in $Rows) {
                    $cur = Format-Amount $r.Amount
                    if ($ComparisonLabel) {
                        $cmp = Format-Amount $r.ComparisonAmount
                        & $append "| $($r.Label) | $cur | $cmp |"
                    }
                    else {
                        & $append "| $($r.Label) | $cur |"
                    }
                }
                & $append ''
            }

            & $writeSection 'Resultaträkning' $IncomeRows
            & $writeSection 'Balansräkning' $BalanceRows
        }
        else {
            $labelWidth = 44
            $amountWidth = 16

            $columnHeader = (' ' * $labelWidth) + $CurrentLabel.PadLeft($amountWidth)
            if ($ComparisonLabel) { $columnHeader += $ComparisonLabel.PadLeft($amountWidth) }

            & $append 'Årsredovisning'
            & $append $Heading
            & $append "Räkenskapsår: $DateRange"
            & $append ''

            $writeSection = {
                param($Title, $Rows)
                & $append $Title
                & $append $columnHeader
                foreach ($r in $Rows) {
                    $label = if ($r.Label.Length -gt $labelWidth) { $r.Label.Substring(0, $labelWidth) } else { $r.Label.PadRight($labelWidth) }
                    $line = $label + (Format-Amount $r.Amount).PadLeft($amountWidth)
                    if ($ComparisonLabel) {
                        $line += (Format-Amount $r.ComparisonAmount).PadLeft($amountWidth)
                    }
                    & $append $line
                }
                & $append ''
            }

            & $writeSection 'Resultaträkning' $IncomeRows
            & $writeSection 'Balansräkning' $BalanceRows
        }

        $sb.ToString() | Set-Content -Path $Path -Encoding UTF8
    }
}
