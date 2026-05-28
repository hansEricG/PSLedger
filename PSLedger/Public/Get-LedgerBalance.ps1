<#
.SYNOPSIS
Generates a trial balance (saldobalans) for a fiscal year.

.DESCRIPTION
Reads all verifications in the specified fiscal year and aggregates amounts
per account. Returns one object per account with total debit, total credit,
and net balance. Account names are resolved from the journal's chart of accounts.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.EXAMPLE
Get-LedgerBalance -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Returns the trial balance with Debit, Credit, and Balance per account.

.EXAMPLE
Get-LedgerBalance -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' |
    Format-Table AccountNumber, AccountName, Debit, Credit, Balance

Displays the trial balance as a formatted table.
#>
function Get-LedgerBalance {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

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
    if (-not $Files) {
        return
    }

    # Aggregate amounts per account
    $Totals = @{}

    foreach ($File in $Files) {
        foreach ($Line in (Get-Content $File.FullName)) {
            if ($Line -match '^(\d+)\t(.+)$') {
                $AccNum = $Matches[1]
                $Amount = [decimal]$Matches[2]

                if (-not $Totals.ContainsKey($AccNum)) {
                    $Totals[$AccNum] = @{ Debit = [decimal]0; Credit = [decimal]0 }
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
        $Debit = $_.Value.Debit
        $Credit = $_.Value.Credit

        [PSCustomObject]@{
            AccountNumber = $AccNum
            AccountName   = if ($AccountNames.ContainsKey($AccNum)) { $AccountNames[$AccNum] } else { '' }
            Debit         = $Debit
            Credit        = $Credit
            Balance       = $Debit - $Credit
        }
    }
}
