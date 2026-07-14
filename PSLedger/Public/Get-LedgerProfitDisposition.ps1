<#
.SYNOPSIS
Builds the proposed appropriation of profit (förslag till vinstdisposition) for a
fiscal year.

.DESCRIPTION
Computes the free equity at the balance sheet date that the annual general meeting
has at its disposal - the balanserat resultat plus the årets resultat, taken from
Get-LedgerEquityReconciliation - and splits it into the board's proposed dividend
(utdelning) and the amount carried forward (balanseras i ny räkning). When the
number of shares is known the dividend per share is also calculated.

The proposed dividend defaults to the ProposedDividend recorded with
Set-LedgerReportInput and can be overridden with -Dividend. The number of shares
defaults to the NumberOfShares journal metadata field and can be overridden with
-NumberOfShares.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-09_2025-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER Dividend
The dividend proposed to be distributed to the owners. Overrides the
ProposedDividend recorded with Set-LedgerReportInput.

.PARAMETER NumberOfShares
The number of shares, used to compute the dividend per share. Overrides the
NumberOfShares journal metadata field.

.EXAMPLE
Get-LedgerProfitDisposition -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'

Returns the disposable earnings and, using the recorded proposed dividend, the
amount to carry forward.

.EXAMPLE
Get-LedgerProfitDisposition -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -Dividend 50000 -NumberOfShares 1000

Proposes a dividend of 50 000 kr and reports the dividend per share (50 kr).
#>
function Get-LedgerProfitDisposition {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [decimal]$Dividend,

        [Parameter()]
        [int]$NumberOfShares
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $Equity = @(Get-LedgerEquityReconciliation -JournalPath $JournalPath -FiscalYear $FiscalYear)
        $Retained = ($Equity | Where-Object { $_.Component -eq 'RetainedEarnings' }).ClosingBalance
        $YearResult = ($Equity | Where-Object { $_.Component -eq 'YearResult' }).ClosingBalance
        if ($null -eq $Retained) { $Retained = [decimal]0 }
        if ($null -eq $YearResult) { $YearResult = [decimal]0 }
        $TotalDisposable = [decimal]$Retained + [decimal]$YearResult

        # Proposed dividend: -Dividend wins, else the recorded ProposedDividend.
        if ($PSBoundParameters.ContainsKey('Dividend')) {
            $DividendValue = $Dividend
        }
        else {
            $ReportInput = Get-LedgerReportInput -JournalPath $JournalPath -FiscalYear $FiscalYear
            $DividendValue = if ($ReportInput.ProposedDividend) { [decimal]$ReportInput.ProposedDividend } else { [decimal]0 }
        }

        # Number of shares: -NumberOfShares wins, else the journal metadata field.
        if ($PSBoundParameters.ContainsKey('NumberOfShares')) {
            $Shares = $NumberOfShares
        }
        else {
            $Journal = Get-LedgerJournal -Path $JournalPath
            $Shares = if ($Journal.Metadata.Contains('NumberOfShares') -and $Journal.Metadata['NumberOfShares']) {
                [int]$Journal.Metadata['NumberOfShares']
            }
            else {
                0
            }
        }

        $CarriedForward = $TotalDisposable - $DividendValue
        $DividendPerShare = if ($Shares -gt 0) { [decimal]$DividendValue / $Shares } else { $null }

        [PSCustomObject]@{
            FiscalYear        = $FiscalYear
            RetainedEarnings  = [decimal]$Retained
            YearResult        = [decimal]$YearResult
            TotalDisposable   = $TotalDisposable
            ProposedDividend  = $DividendValue
            CarriedForward    = $CarriedForward
            NumberOfShares    = if ($Shares -gt 0) { $Shares } else { $null }
            DividendPerShare  = $DividendPerShare
        }
    }
}
