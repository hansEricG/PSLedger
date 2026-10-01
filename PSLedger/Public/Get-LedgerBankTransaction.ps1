<#
.SYNOPSIS
Lists imported bank transactions.

.DESCRIPTION
Returns the transactions imported with Import-LedgerBankStatement, with their
status ('Unmatched', 'Matched' or 'Ignored') and, for matched transactions,
how they were matched (MatchType and MatchRef) and the verification they are
linked to. The output can be piped to Set-LedgerBankTransaction.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER TransactionId
Optional. Return only this transaction.

.PARAMETER StatementNumber
Optional. Return only transactions from this statement.

.PARAMETER Account
Optional. Return only transactions for this bank account (e.g. '1930').

.PARAMETER Status
Optional. Return only transactions with this status.

.PARAMETER FromDate
Optional. Return only transactions on or after this date.

.PARAMETER ToDate
Optional. Return only transactions on or before this date.

.EXAMPLE
Get-LedgerBankTransaction -JournalPath .\MinFirma.ledger -Status Unmatched

Lists the transactions that still need to be matched or posted.

.EXAMPLE
Get-LedgerBankTransaction -Status Unmatched | Where-Object Text -like '*Ränta*' |
    Set-LedgerBankTransaction -Account 8310

Posts all unmatched interest payments to 8310 (Ränteintäkter från
omsättningstillgångar).
#>
function Get-LedgerBankTransaction {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [int]$TransactionId,

        [Parameter()]
        [int]$StatementNumber,

        [Parameter()]
        [string]$Account,

        [Parameter()]
        [ValidateSet('Unmatched', 'Matched', 'Ignored')]
        [string]$Status,

        [Parameter()]
        [datetime]$FromDate,

        [Parameter()]
        [datetime]$ToDate
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    foreach ($s in @(Get-LedgerBankStatementData -JournalPath $JournalPath)) {
        if ($PSBoundParameters.ContainsKey('StatementNumber') -and $s.StatementNumber -ne $StatementNumber) { continue }
        if ($Account -and $s.BankAccount -ne $Account) { continue }
        foreach ($t in $s.Transactions) {
            if ($PSBoundParameters.ContainsKey('TransactionId') -and $t.TransactionId -ne $TransactionId) { continue }
            if ($Status -and $t.Status -ne $Status) { continue }
            if ($PSBoundParameters.ContainsKey('FromDate') -and $t.Date -lt $FromDate.Date) { continue }
            if ($PSBoundParameters.ContainsKey('ToDate') -and $t.Date -gt $ToDate.Date) { continue }
            ConvertTo-LedgerBankTransactionOutput -Transaction $t
        }
    }
}
