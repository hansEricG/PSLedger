<#
.SYNOPSIS
Displays the general ledger (huvudbok) for a specific account.

.DESCRIPTION
Lists all transactions affecting the specified account in chronological order
with a running balance. If the account has an opening balance (from the fiscal
year's opening balance metadata, ib.txt), it is shown as the first row (ingående
saldo) and the running balance starts from it; the opening balance is not counted
in the period Debit/Credit columns. Each returned object includes the verification
number, date, description, debit or credit amount, and running balance.
Optionally filters by date range; when -FromDate is set, the opening row reflects
the carried-forward balance at that date (the opening balance plus any
transactions dated before -FromDate).

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER Account
The account number to display (e.g. '1910').

.PARAMETER FromDate
Optional. Only include transactions on or after this date.

.PARAMETER ToDate
Optional. Only include transactions on or before this date.

.EXAMPLE
Get-LedgerLedger -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Account '1910'

Returns all transactions for account 1910 (Kassa och bank) with running balance.

.EXAMPLE
Get-LedgerLedger -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Account '3010' -FromDate '2024-04-01' -ToDate '2024-06-30' |
    Format-Table VerificationNumber, Date, Description, Debit, Credit, Balance

Displays Q2 activity for the sales account as a formatted table.
#>
function Get-LedgerLedger {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$Account,

        [datetime]$FromDate,

        [datetime]$ToDate
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $entries = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Account $Account

        # Opening balance (ingående balans) is stored as metadata in ib.txt, not
        # as a verification. Read the account's opening balance and the fiscal
        # year start date (used as the date for the opening row).
        $YearDir = Join-Path $JournalPath $FiscalYear
        $openingBalance = [decimal]0
        $hasOpening = $false
        foreach ($row in (Read-LedgerOpeningBalance -YearDir $YearDir)) {
            if ($row.Account -eq $Account) {
                $openingBalance += [decimal]$row.Amount
                $hasOpening = $true
            }
        }

        $yearStart = $null
        $YearFile = Join-Path $YearDir 'year.txt'
        if (Test-Path $YearFile) {
            foreach ($Line in (Get-Content $YearFile)) {
                if ($Line -match '^StartDate:\s*(.+)$') { $yearStart = $Matches[1]; break }
            }
        }

        if (-not $entries -and -not $hasOpening) { return }

        $regular = @($entries | Sort-Object { [datetime]$_.Date }, VerificationNumber)

        # Carry the opening balance forward. When -FromDate is set and the account
        # has an opening balance, also fold in transactions dated before -FromDate
        # so the opening row reflects the correct carried-forward balance at that
        # date (ingående saldo per periodens början), not just the year-start value.
        $broughtForward = $openingBalance
        if ($hasOpening -and $FromDate) {
            foreach ($entry in $regular) {
                if (([datetime]$entry.Date) -lt $FromDate) {
                    foreach ($row in $entry.Rows) {
                        if ($row.Account -eq $Account) { $broughtForward += [decimal]$row.Amount }
                    }
                }
            }
        }

        $balance = $broughtForward

        # Emit the opening balance (ingående saldo) as the first row. When a
        # -FromDate is set it reflects the carried-forward balance at that date.
        if ($hasOpening) {
            $openingDate = if ($FromDate) { $FromDate.ToString('yyyy-MM-dd') } else { $yearStart }
            [PSCustomObject]@{
                VerificationNumber = $null
                Date               = $openingDate
                Description        = 'Ingående balans'
                Debit              = [decimal]0
                Credit             = [decimal]0
                Balance            = $broughtForward
            }
        }

        foreach ($entry in $regular) {
            $entryDate = [datetime]$entry.Date
            if ($FromDate -and $entryDate -lt $FromDate) { continue }
            if ($ToDate -and $entryDate -gt $ToDate) { continue }

            foreach ($row in $entry.Rows) {
                if ($row.Account -ne $Account) { continue }

                $amount = [decimal]$row.Amount
                $debit = if ($amount -gt 0) { $amount } else { [decimal]0 }
                $credit = if ($amount -lt 0) { [Math]::Abs($amount) } else { [decimal]0 }
                $balance += $amount

                [PSCustomObject]@{
                    VerificationNumber = $entry.VerificationNumber
                    Date               = $entry.Date
                    Description        = $entry.Description
                    Debit              = $debit
                    Credit             = $credit
                    Balance            = $balance
                }
            }
        }
    }
}

