function Get-LedgerBankTransactionHash {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [psobject]$Transaction)

    $fields = @(
        $Transaction.StatementNumber
        $Transaction.TransactionId
        $Transaction.BankAccount
        $Transaction.Date.ToString('yyyy-MM-dd')
        $Transaction.Amount.ToString('0.############################', [Globalization.CultureInfo]::InvariantCulture)
        $Transaction.BankReference
        $Transaction.Reference
        $Transaction.Counterparty
        $Transaction.Text
    )
    Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($fields -join "`t") + "`n"))
}

function Get-LedgerBankInvoicePaymentOperation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [psobject]$Transaction,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Operations
    )
    $found = @($Operations | Where-Object {
        $_.PSObject.Properties['BankTransactionId'] -and $_.BankTransactionId -eq $Transaction.TransactionId
    })
    if ($found.Count -gt 1) { throw "Bank transaction $($Transaction.TransactionId) has conflicting payment plans." }
    if ($found.Count) {
        $operation = $found[0]
        $signedAmount = if ($operation.InvoiceType -eq 'Supplier') { -$operation.PaymentAmount } else { $operation.PaymentAmount }
        if ($operation.BankStatementNumber -ne $Transaction.StatementNumber -or
            $operation.BankTransactionHash -ne (Get-LedgerBankTransactionHash -Transaction $Transaction) -or
            $operation.PaymentDate -ne $Transaction.Date -or $signedAmount -ne $Transaction.Amount -or
            $operation.PaymentAccount -ne $Transaction.BankAccount) {
            throw "Bank transaction $($Transaction.TransactionId) differs from its saved payment plan. Recovery stopped."
        }
        $operation
    }
}

function Assert-LedgerBankPaymentLink {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [psobject]$Transaction,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    if ($Transaction.Status -eq 'Unmatched' -and -not $Transaction.MatchType -and -not $Transaction.MatchRef -and
        -not $Transaction.FiscalYear -and -not $Transaction.VerificationNumber) { return }
    if ($Transaction.Status -eq 'Matched' -and $Transaction.MatchType -eq "$($Operation.InvoiceType)Invoice" -and
        $Transaction.MatchRef -eq "$($Operation.InvoiceNumber)" -and $Transaction.FiscalYear -eq $Operation.FiscalYear -and
        $Transaction.VerificationNumber -eq $Operation.VerificationNumber) { return }
    throw "Bank transaction $($Transaction.TransactionId) has a conflicting saved link. Recovery stopped."
}
