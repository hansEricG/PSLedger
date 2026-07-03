<#
.SYNOPSIS
Closes a fiscal year, booking the net result and preventing further entries.

.DESCRIPTION
Performs the year-end closing of a fiscal year. Unless -SkipResultEntry is used,
the net result for the year (the sum of the profit and loss accounts, classes
3-8) is booked as a normal verification transferring it to equity: debit the
result account (8999 Årets resultat by default) and credit the equity account for
a profit, and the reverse for a loss. The equity account defaults to the one that
matches the journal's CompanyType (2099 for AB, 2019 for EF) and can be overridden
with -EquityAccount.

Booking the result as a real verification means it appears in the ledger and in
SIE exports, and it consumes a verification number. When there is no result to
book (the profit and loss accounts net to zero) no verification is created and the
year is simply flagged as closed.

After any result entry has been written the Status field in year.txt is set to
'Closed'. Once closed, Add-LedgerEntry refuses to create new verifications in that
fiscal year.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER EquityAccount
The equity account the net result is transferred to. When omitted it is derived
from the journal's CompanyType (AB -> 2099, EF -> 2019). Required for other
company forms (HB, KB) or journals without a CompanyType when there is a result to
book.

.PARAMETER ResultAccount
The profit and loss closing account debited/credited against equity. Defaults to
'8999' (Årets resultat).

.PARAMETER SkipResultEntry
Closes the year by only setting its status, without booking the net result. Use
this to keep the legacy behaviour where the result is carried forward
synthetically by Copy-LedgerOpeningBalance instead of being booked.

.EXAMPLE
Close-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Books the 2024 net result to equity (using the journal's CompanyType to pick the
account) and closes the year so no more entries can be added.

.EXAMPLE
Close-LedgerFiscalYear -JournalPath .\Enskild.ledger -FiscalYear '2024-01_2024-12' -EquityAccount '2019'

Closes an enskild firma year, transferring the result to account 2019 (Årets
resultat, eget kapital).

.EXAMPLE
Get-LedgerFiscalYear -JournalPath .\MinFirma.ledger |
    Where-Object { $_.Status -eq 'Open' } |
    ForEach-Object { Close-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear $_.Name -SkipResultEntry }

Closes all open fiscal years without booking a result verification.
#>
function Close-LedgerFiscalYear {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [string]$EquityAccount,

        [Parameter()]
        [string]$ResultAccount = '8999',

        [Parameter()]
        [switch]$SkipResultEntry
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        $YearFile = Join-Path $YearDir 'year.txt'
        if (-not (Test-Path $YearFile)) {
            throw "Invalid fiscal year - year.txt not found in: $FiscalYear"
        }

        $Lines = Get-Content $YearFile

        # Check current status and capture the year's end date for the result entry.
        $EndDate = $null
        foreach ($Line in $Lines) {
            if ($Line -match '^Status:\s*Closed') {
                throw "Fiscal year $FiscalYear is already closed."
            }
            elseif ($Line -match '^EndDate:\s*(.+)$') {
                $EndDate = [datetime]$Matches[1]
            }
        }

        if (-not $PSCmdlet.ShouldProcess($FiscalYear, 'Close fiscal year and book net result')) {
            return
        }

        # Book the net result to equity unless explicitly skipped. When the profit
        # and loss accounts net to zero there is nothing to book, so the year is
        # simply flagged as closed (this also keeps legacy no-result years working).
        if (-not $SkipResultEntry) {
            $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear
            $ResultRows = @($Balance | Where-Object { $_.AccountNumber -match '^[3-8]' })
            $RawResult = if ($ResultRows) {
                ($ResultRows | Measure-Object -Property Balance -Sum).Sum
            }
            else {
                [decimal]0
            }
            $RawResult = [Math]::Round([decimal]$RawResult, 2)

            if ($RawResult -ne 0) {
                $Equity = if ($EquityAccount) {
                    $EquityAccount
                }
                else {
                    Resolve-LedgerEquityAccount -JournalPath $JournalPath
                }

                if (-not $EndDate) {
                    throw "Cannot determine the result date - EndDate missing from year.txt in $FiscalYear."
                }

                # Debit the result account and credit equity for a profit; the raw
                # balance of the P&L accounts is negative for a profit, so negating
                # it gives the debit amount on the result account.
                $Rows = @(
                    @{ Account = $ResultAccount; Amount = -$RawResult }
                    @{ Account = $Equity; Amount = $RawResult }
                )

                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                    -Date $EndDate -Description 'Årets resultat (bokslut)' -Rows $Rows
            }
        }

        # Rewrite year.txt with updated status.
        $NewLines = foreach ($Line in $Lines) {
            if ($Line -match '^Status:\s*') {
                'Status: Closed'
            }
            else {
                $Line
            }
        }

        $NewLines | Set-Content -Path $YearFile -Encoding UTF8
    }
}
