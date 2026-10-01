<#
.SYNOPSIS
Reconciles a bank account in the ledger against the bank (bankavstämning).

.DESCRIPTION
Compares the ledger balance of the bank account with the bank's balance on a
given date and lists what explains the difference:

- UnmatchedBankTransactions: imported bank transactions up to the date that
  are not in the ledger by that date - unmatched transactions, and matched
  transactions whose verification is dated after the date.
- UnmatchedLedgerEntries: verifications in the fiscal year up to the date that
  touch the bank account but are not linked to a bank transaction dated on or
  before the date, i.e. not (yet) seen by the bank. Only verifications dated
  on or after the first imported bank transaction are considered.

The ledger balance is the opening balance (ib.txt) plus all verifications up
to and including the date. The bank balance starts from the known balance
closest before the date - a statement's closing balance, or its opening
balance - and adds all imported transactions after that point up to the date.
Supply -BankBalance to use a balance read from the internet bank instead.

Difference is LedgerBalance minus BankBalance. UnexplainedDifference is what
remains after the unmatched items on both sides are taken into account; it
should be zero. Status is 'Reconciled' when the balances agree and nothing is
unmatched, 'Differences' otherwise, and 'NoBankBalance' when no bank balance
is known.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Account
The bank account in the ledger. Defaults to '1930'.

.PARAMETER AsOf
The reconciliation date. Defaults to the last date covered by the imported
statements for the account, or today if nothing has been imported.

.PARAMETER BankBalance
Optional. The bank's balance on the reconciliation date, overriding the
balance derived from imported statements.

.PARAMETER FiscalYear
Optional. The fiscal year to read the ledger from. Defaults to the fiscal year
containing the reconciliation date.

.EXAMPLE
Get-LedgerBankReconciliation -JournalPath .\MinFirma.ledger

Reconciles account 1930 on the last date covered by the imported statements.

.EXAMPLE
$r = Get-LedgerBankReconciliation -Account 1930 -AsOf '2024-12-31'
$r | Format-List LedgerBalance, BankBalance, Difference, UnexplainedDifference, Status
$r.UnmatchedBankTransactions | Format-Table TransactionId, Date, Amount, Text
$r.UnmatchedLedgerEntries | Format-Table VerificationNumber, Date, Amount, Description

Year-end bank reconciliation for the annual accounts, with the open items on
both sides.
#>
function Get-LedgerBankReconciliation {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$Account = '1930',

        [Parameter()]
        [datetime]$AsOf,

        [Parameter()]
        [decimal]$BankBalance,

        [Parameter()]
        [string]$FiscalYear
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $statements = @(Get-LedgerBankStatementData -JournalPath $JournalPath | Where-Object BankAccount -eq $Account)
    $allTransactions = @($statements | ForEach-Object { $_.Transactions })

    if ($PSBoundParameters.ContainsKey('AsOf')) {
        $AsOf = $AsOf.Date
    }
    else {
        $lastDates = @($statements | ForEach-Object { $_.ToDate } | Where-Object { $_ }) + @($allTransactions | ForEach-Object { $_.Date })
        $AsOf = if ($lastDates) { ($lastDates | Measure-Object -Maximum).Maximum } else { (Get-Date).Date }
    }

    if (-not $FiscalYear) {
        $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $AsOf
        if (-not $FiscalYear) {
            throw "No fiscal year covers $($AsOf.ToString('yyyy-MM-dd')). Specify -FiscalYear."
        }
    }
    $yearDir = Join-Path $JournalPath $FiscalYear
    if (-not (Test-Path $yearDir -PathType Container)) {
        throw "Fiscal year not found: $FiscalYear"
    }

    # Ledger balance: opening balance plus all verifications up to AsOf.
    $ledgerBalance = [decimal]0
    foreach ($row in @(Read-LedgerOpeningBalance -YearDir $yearDir)) {
        if ($row.Account -eq $Account) { $ledgerBalance += [decimal]$row.Amount }
    }
    $allMovements = @(Get-LedgerBankAccountMovements -JournalPath $JournalPath -FiscalYear $FiscalYear -BankAccount $Account)
    $movements = @($allMovements | Where-Object { $_.Date -le $AsOf })
    foreach ($m in $movements) { $ledgerBalance += $m.Amount }

    # Bank balance unless supplied: start from the known balance closest before
    # AsOf (a statement's closing balance at its ToDate, or its opening balance
    # just before its FromDate) and add every stored transaction after that
    # point. Transactions are summed across all statements because duplicates
    # from overlapping files are stored only once.
    $bank = $null
    $bankSource = ''
    if ($PSBoundParameters.ContainsKey('BankBalance')) {
        $bank = $BankBalance
        $bankSource = 'Parameter'
    }
    else {
        $anchors = foreach ($s in $statements) {
            if ($null -ne $s.ClosingBalance -and $s.ToDate -and $s.ToDate -le $AsOf) {
                [PSCustomObject]@{ Date = $s.ToDate; Balance = [decimal]$s.ClosingBalance; Statement = $s.StatementNumber }
            }
            if ($null -ne $s.OpeningBalance -and $s.FromDate -and $s.FromDate -le $AsOf) {
                [PSCustomObject]@{ Date = $s.FromDate.AddDays(-1); Balance = [decimal]$s.OpeningBalance; Statement = $s.StatementNumber }
            }
        }
        $anchor = $anchors | Sort-Object Date, Statement | Select-Object -Last 1
        if ($anchor) {
            $bank = $anchor.Balance
            foreach ($t in $allTransactions) {
                if ($t.Date -gt $anchor.Date -and $t.Date -le $AsOf) { $bank += $t.Amount }
            }
            $bankSource = "Statement $($anchor.Statement)"
        }
    }

    # A bank transaction and its verification only offset each other when both
    # are on or before AsOf; a pair split by AsOf (e.g. a payment booked on
    # 30 December that clears on 2 January) is an open item on one side.
    $movementDates = @{}
    foreach ($m in $allMovements) { $movementDates["$($m.FiscalYear)|$($m.VerificationNumber)"] = $m.Date }
    $bankUpToAsOf = @($allTransactions | Where-Object { $_.Date -le $AsOf -and $_.Status -ne 'Ignored' })
    $linked = [System.Collections.Generic.HashSet[string]]::new()
    $openBank = foreach ($t in $bankUpToAsOf) {
        if ($t.Status -eq 'Unmatched') { $t; continue }
        if ($null -eq $t.VerificationNumber) { continue }
        $key = "$($t.FiscalYear)|$($t.VerificationNumber)"
        [void]$linked.Add($key)
        $afterAsOf = if ($t.FiscalYear -eq $FiscalYear) {
            $movementDates.ContainsKey($key) -and $movementDates[$key] -gt $AsOf
        } else {
            [string]::CompareOrdinal($t.FiscalYear, $FiscalYear) -gt 0
        }
        if ($afterAsOf) { $t }
    }
    $unmatchedBank = @($openBank | Sort-Object Date, TransactionId | ForEach-Object { ConvertTo-LedgerBankTransactionOutput -Transaction $_ })

    $coverageStart = if ($allTransactions) { ($allTransactions | Measure-Object -Property Date -Minimum).Minimum } else { $null }
    $unmatchedLedger = @()
    if ($coverageStart) {
        $unmatchedLedger = @($movements | Where-Object {
            $_.Date -ge $coverageStart -and $_.Amount -ne 0 -and -not $linked.Contains("$($_.FiscalYear)|$($_.VerificationNumber)")
        } | Sort-Object Date, VerificationNumber)
    }
    $unmatchedBankSum = [decimal]0
    foreach ($t in $unmatchedBank) { $unmatchedBankSum += $t.Amount }
    $unmatchedLedgerSum = [decimal]0
    foreach ($m in $unmatchedLedger) { $unmatchedLedgerSum += $m.Amount }

    $difference = $null
    $unexplained = $null
    $status = 'NoBankBalance'
    if ($null -ne $bank) {
        $difference = $ledgerBalance - $bank
        $unexplained = $difference - $unmatchedLedgerSum + $unmatchedBankSum
        $status = if ($difference -eq 0 -and $unmatchedBank.Count -eq 0 -and $unmatchedLedger.Count -eq 0) { 'Reconciled' } else { 'Differences' }
    }

    [PSCustomObject]@{
        Account                   = $Account
        AsOf                      = $AsOf
        FiscalYear                = $FiscalYear
        LedgerBalance             = $ledgerBalance
        BankBalance               = $bank
        BankBalanceSource         = $bankSource
        Difference                = $difference
        UnmatchedBankTransactions = $unmatchedBank
        UnmatchedBankAmount       = $unmatchedBankSum
        UnmatchedLedgerEntries    = $unmatchedLedger
        UnmatchedLedgerAmount     = $unmatchedLedgerSum
        UnexplainedDifference     = $unexplained
        Status                    = $status
    }
}
