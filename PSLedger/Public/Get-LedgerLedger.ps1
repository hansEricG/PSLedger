<#
.SYNOPSIS
Displays the general ledger (huvudbok) for a specific account.

.DESCRIPTION
Lists all transactions affecting the specified account in chronological order
with a running balance. Each returned object includes the verification number,
date, description, debit or credit amount, and running balance. Optionally
filters by date range.

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

        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$Account,

        [datetime]$FromDate,

        [datetime]$ToDate
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $entries = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Account $Account

    if (-not $entries) { return }

    $sorted = $entries | Sort-Object { [datetime]$_.Date }, VerificationNumber

    $balance = [decimal]0

    foreach ($entry in $sorted) {
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
