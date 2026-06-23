<#
.SYNOPSIS
Displays the general ledger (huvudbok) for a specific account.

.DESCRIPTION
Lists all transactions affecting the specified account in chronological order
with a running balance. If the account has an opening balance (from the
'Ingående balans' verification), it is shown as the first row (ingående saldo)
and the running balance starts from it; the opening balance is not counted in
the period Debit/Credit columns. Each returned object includes the verification
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

        if (-not $entries) { return }

        $sorted = $entries | Sort-Object { [datetime]$_.Date }, VerificationNumber

        # Separate the opening balance entry ('Ingående balans') from regular
        # transactions so it can be shown as the running balance starting point.
        $openingBalance = [decimal]0
        $openingEntry = $null
        $regular = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $sorted) {
            if ($entry.Description -eq 'Ingående balans') {
                foreach ($row in $entry.Rows) {
                    if ($row.Account -eq $Account) { $openingBalance += [decimal]$row.Amount }
                }
                if (-not $openingEntry) { $openingEntry = $entry }
            }
            else {
                $regular.Add($entry) | Out-Null
            }
        }

        # Carry the opening balance forward. When -FromDate is set and the account
        # has an opening balance, also fold in transactions dated before -FromDate
        # so the opening row reflects the correct carried-forward balance at that
        # date (ingående saldo per periodens början), not just the year-start value.
        $broughtForward = $openingBalance
        if ($openingEntry -and $FromDate) {
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
        if ($openingEntry) {
            $openingDate = if ($FromDate) { $FromDate.ToString('yyyy-MM-dd') } else { $openingEntry.Date }
            $openingVer = if ($FromDate) { $null } else { $openingEntry.VerificationNumber }
            [PSCustomObject]@{
                VerificationNumber = $openingVer
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

