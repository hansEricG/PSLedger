<#
.SYNOPSIS
Copies the securities holdings of one fiscal year into another.

.DESCRIPTION
Rolls the holdings recorded with Set-LedgerHolding (holdings.txt) forward into a
new fiscal year, typically together with Copy-LedgerOpeningBalance at year end.
All fields are copied as-is, including Price, PriceDate and Source, so the new
year starts with last year's closing prices; update them with Set-LedgerHolding
when the new balance date is reached (Test-LedgerFiscalYear flags price dates that
do not match the fiscal year's end date).

The target fiscal year must be open. If it already has holdings, the command
throws unless -Force is given, in which case the target's holdings are replaced.
A warning is emitted for each holding whose account has no opening balance in the
target year.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FromFiscalYear
The source fiscal year to copy holdings from. If omitted, uses the current fiscal
year set via Set-LedgerCurrentFiscalYear.

.PARAMETER ToFiscalYear
The target fiscal year to copy holdings into.

.PARAMETER Force
Replace holdings already recorded in the target fiscal year.

.EXAMPLE
Copy-LedgerHolding -JournalPath .\HEG.ledger -FromFiscalYear '2025-09_2026-08' -ToFiscalYear '2026-09_2027-08'

Copies the holdings to the new fiscal year.

.EXAMPLE
Copy-LedgerOpeningBalance -JournalPath .\HEG.ledger -FromFiscalYear '2025-09_2026-08' -ToFiscalYear '2026-09_2027-08'
Copy-LedgerHolding -JournalPath .\HEG.ledger -FromFiscalYear '2025-09_2026-08' -ToFiscalYear '2026-09_2027-08'
Set-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear '2026-09_2027-08' -Account 1350 -Name 'Swedbank A' `
    -Price 301.50 -PriceDate '2027-08-31' -Source 'Nasdaq Stockholm, stängningskurs'

Year-end roll-forward: copy balances and holdings, then update the price at the
new balance date.
#>
function Copy-LedgerHolding {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FromFiscalYear,

        [Parameter(Mandatory)]
        [string]$ToFiscalYear,

        [Parameter()]
        [switch]$Force
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FromFiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FromFiscalYear -JournalPath $JournalPath

        $FromDir = Join-Path $JournalPath $FromFiscalYear
        if (-not (Test-Path $FromDir -PathType Container)) {
            throw "Source fiscal year not found: $FromFiscalYear"
        }
        $ToDir = Join-Path $JournalPath $ToFiscalYear
        if (-not (Test-Path $ToDir -PathType Container)) {
            throw "Target fiscal year not found: $ToFiscalYear"
        }
        if ($FromFiscalYear -eq $ToFiscalYear) {
            throw 'Source and target fiscal year must differ.'
        }
        Assert-LedgerFiscalYearOpen -YearDir $ToDir -FiscalYear $ToFiscalYear -Action 'copy holdings into it'

        $Holdings = Read-LedgerHoldings -YearDir $FromDir
        if ($Holdings.Count -eq 0) {
            throw "No holdings recorded in $FromFiscalYear."
        }

        $Existing = Read-LedgerHoldings -YearDir $ToDir
        if ($Existing.Count -gt 0 -and -not $Force) {
            throw "Target fiscal year $ToFiscalYear already has holdings. Use -Force to replace them."
        }

        $Opening = @{}
        foreach ($Row in (Read-LedgerOpeningBalance -YearDir $ToDir)) {
            $Opening[[string]$Row.Account] = [decimal]$Row.Amount
        }
        foreach ($Account in ($Holdings | ForEach-Object { $_.Account } | Select-Object -Unique)) {
            if (-not $Opening.ContainsKey($Account) -or $Opening[$Account] -eq 0) {
                Write-Warning "Account $Account has no opening balance in $ToFiscalYear. Copy the opening balance first (Copy-LedgerOpeningBalance) or check the holding."
            }
        }

        if (-not $PSCmdlet.ShouldProcess($ToFiscalYear, "Copy $($Holdings.Count) holding(s) from $FromFiscalYear")) {
            return
        }
        Write-LedgerHoldings -YearDir $ToDir -Rows $Holdings

        foreach ($h in $Holdings) {
            $Out = $h.PSObject.Copy()
            $Out | Add-Member -NotePropertyName FiscalYear -NotePropertyValue $ToFiscalYear -Force
            $Out
        }
    }
}
