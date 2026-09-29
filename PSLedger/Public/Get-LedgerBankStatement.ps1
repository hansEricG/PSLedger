<#
.SYNOPSIS
Lists imported bank statements.

.DESCRIPTION
Returns one object per statement imported with Import-LedgerBankStatement,
with its bank account, period, opening and closing balance and a count of
transactions per status.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER StatementNumber
Optional. Return only this statement.

.PARAMETER Account
Optional. Return only statements for this bank account (e.g. '1930').

.EXAMPLE
Get-LedgerBankStatement -JournalPath .\MinFirma.ledger

Lists all imported statements.

.EXAMPLE
Get-LedgerBankStatement -Account 1930 |
    Format-Table StatementNumber, FromDate, ToDate, OpeningBalance, ClosingBalance, Unmatched

Shows the statements for the business account and how many transactions are
still unmatched in each.
#>
function Get-LedgerBankStatement {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [int]$StatementNumber,

        [Parameter()]
        [string]$Account
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    foreach ($s in @(Get-LedgerBankStatementData -JournalPath $JournalPath)) {
        if ($PSBoundParameters.ContainsKey('StatementNumber') -and $s.StatementNumber -ne $StatementNumber) { continue }
        if ($Account -and $s.BankAccount -ne $Account) { continue }
        $tx = @($s.Transactions)
        [PSCustomObject]@{
            StatementNumber = $s.StatementNumber
            BankAccount     = $s.BankAccount
            Source          = $s.Source
            FileName        = $s.FileName
            StatementId     = $s.StatementId
            AccountId       = $s.AccountId
            Currency        = $s.Currency
            FromDate        = $s.FromDate
            ToDate          = $s.ToDate
            OpeningBalance  = $s.OpeningBalance
            ClosingBalance  = $s.ClosingBalance
            ImportedDate    = $s.ImportedDate
            Transactions    = $tx.Count
            Unmatched       = @($tx | Where-Object Status -eq 'Unmatched').Count
            Matched         = @($tx | Where-Object Status -eq 'Matched').Count
            Ignored         = @($tx | Where-Object Status -eq 'Ignored').Count
        }
    }
}
