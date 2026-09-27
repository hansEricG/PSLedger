<#
.SYNOPSIS
Removes a securities holding (innehav) from a fiscal year.

.DESCRIPTION
Deletes the holding identified by Account and Name from the fiscal year's
holdings.txt. When the last holding is removed the file is deleted, so the
annual report falls back to the SecuritiesMarketValue recorded with
Set-LedgerReportInput.

Holdings cannot be changed in a closed fiscal year.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-09_2025-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER Account
The account the holding is booked on.

.PARAMETER Name
The name of the holding.

.EXAMPLE
Remove-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' -Account 1350 -Name 'Investor B'

Removes the Investor B holding.

.EXAMPLE
Get-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' -Account 1810 |
    Remove-LedgerHolding -JournalPath .\HEG.ledger -WhatIf

Previews removing every short-term holding on account 1810.
#>
function Remove-LedgerHolding {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$FiscalYear,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^\d+$')]
        [string]$Account,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    process {
        $ResolvedJournal = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $ResolvedYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $ResolvedJournal

        $YearDir = Join-Path $ResolvedJournal $ResolvedYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $ResolvedYear"
        }
        Assert-LedgerFiscalYearOpen -YearDir $YearDir -FiscalYear $ResolvedYear -Action 'change holdings'

        $existing = Read-LedgerHoldings -YearDir $YearDir
        $remaining = @($existing | Where-Object { -not ($_.Account -eq $Account -and $_.Name -eq $Name) })
        if ($remaining.Count -eq $existing.Count) {
            throw "Holding '$Name' on account $Account not found in $ResolvedYear."
        }

        $Path = Get-LedgerHoldingsPath -YearDir $YearDir
        if ($PSCmdlet.ShouldProcess($Path, "Remove holding '$Name' on account $Account")) {
            Write-LedgerHoldings -YearDir $YearDir -Rows $remaining
        }
    }
}
