<#
.SYNOPSIS
Generates a trial balance (saldobalans) for a fiscal year.

.DESCRIPTION
Reads all verifications in the specified fiscal year and aggregates amounts
per account. The opening balance is read from the fiscal year's opening balance
metadata (ib.txt) and reported as OpeningBalance, while all verifications are
summed into Debit and Credit. The closing balance (Balance) is
OpeningBalance + Debit - Credit. Account names are resolved from the journal's
chart of accounts.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.EXAMPLE
Get-LedgerBalance -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Returns the trial balance with OpeningBalance, Debit, Credit, and Balance per account.

.EXAMPLE
Get-LedgerBalance -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' |
    Format-Table AccountNumber, AccountName, OpeningBalance, Debit, Credit, Balance

Displays the trial balance as a formatted table showing the opening balance
(ingående saldo), period debit/credit totals, and the closing balance
(utgående saldo).
#>
function Get-LedgerBalance {
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

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        # Load chart of accounts for name lookup
        $AccountNames = @{}
        $KontoplanFile = Join-Path $JournalPath 'accounts.txt'
        if (Test-Path $KontoplanFile) {
            foreach ($Line in (Get-Content $KontoplanFile)) {
                if ($Line -match '^(\d+)\t(.+)$') {
                    $AccountNames[$Matches[1]] = $Matches[2]
                }
            }
        }

        # Read all verification files
        $Files = Get-ChildItem -Path $YearDir -Filter 'ver*.txt' -File -ErrorAction SilentlyContinue
        $OpeningRows = Read-LedgerOpeningBalance -YearDir $YearDir
        if (-not $Files -and -not $OpeningRows) {
            return
        }

        # Aggregate amounts per account
        $Totals = @{}

        # Seed opening balances from ib.txt (ingående balans metadata).
        foreach ($Row in $OpeningRows) {
            $AccNum = $Row.Account
            if (-not $Totals.ContainsKey($AccNum)) {
                $Totals[$AccNum] = @{ Opening = [decimal]0; Debit = [decimal]0; Credit = [decimal]0 }
            }
            $Totals[$AccNum].Opening += [decimal]$Row.Amount
        }

        foreach ($File in $Files) {
            $Lines = Get-Content $File.FullName

            foreach ($Line in $Lines) {
                if ($Line -match '^(\d+)\t([^\t]+)') {
                    $AccNum = $Matches[1]
                    $Amount = [decimal]$Matches[2]

                    if (-not $Totals.ContainsKey($AccNum)) {
                        $Totals[$AccNum] = @{ Opening = [decimal]0; Debit = [decimal]0; Credit = [decimal]0 }
                    }

                    if ($Amount -gt 0) {
                        $Totals[$AccNum].Debit += $Amount
                    }
                    elseif ($Amount -lt 0) {
                        $Totals[$AccNum].Credit += [Math]::Abs($Amount)
                    }
                }
            }
        }

        # Build sorted result
        $Totals.GetEnumerator() | Sort-Object Key | ForEach-Object {
            $AccNum = $_.Key
            $Opening = $_.Value.Opening
            $Debit = $_.Value.Debit
            $Credit = $_.Value.Credit

            [PSCustomObject]@{
                AccountNumber  = $AccNum
                AccountName    = if ($AccountNames.ContainsKey($AccNum)) { $AccountNames[$AccNum] } else { '' }
                OpeningBalance = $Opening
                Debit          = $Debit
                Credit         = $Credit
                Balance        = $Opening + $Debit - $Credit
            }
        }
    }
}

