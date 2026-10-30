function Get-LedgerInvoicePaymentOperation {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$JournalPath)

    $directory = Join-Path $JournalPath 'invoices' 'payments'
    if (-not (Test-Path -LiteralPath $directory)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $directory -Filter '*.txt' -File -ErrorAction Stop) {
        Read-LedgerInvoicePosting -Path $file.FullName -Payment
    }
}

function Get-LedgerRecordedInvoicePayment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [psobject]$Invoice,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    $payments = @($Invoice.Payments | Where-Object {
        $_.VerificationNumber -eq $Operation.VerificationNumber -and $_.FiscalYear -eq $Operation.FiscalYear
    })
    if ($payments.Count -gt 1 -or ($payments.Count -eq 1 -and
            ($payments[0].Date -ne $Operation.PaymentDate -or $payments[0].Amount -ne $Operation.PaymentAmount))) {
        throw "Invoice $($Invoice.InvoiceNumber) has conflicting payment references for PaymentId $($Operation.OperationId). Recovery stopped."
    }
    $payments
}

function Assert-LedgerInvoicePaymentVerification {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [psobject]$Invoice,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    $path = Join-Path $JournalPath $Operation.FiscalYear ('ver{0:D4}.txt' -f $Operation.VerificationNumber)
    Assert-LedgerInvoicePostingVerification -Path $path -Operation $Operation
    $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $Operation.FiscalYear -VerificationNumber $Operation.VerificationNumber
    if ($entry.Date -ne $Operation.PaymentDate.ToString('yyyy-MM-dd') -or
        $entry.Description -ne "Betalning kundfaktura $($Operation.InvoiceNumber)" -or
        $entry.Rows.Count -ne 2 -or
        $entry.Rows[0].Account -ne $Operation.PaymentAccount -or $entry.Rows[0].Amount -ne $Operation.PaymentAmount -or
        $entry.Rows[1].Account -ne $Invoice.ReceivableAccount -or $entry.Rows[1].Amount -ne -$Operation.PaymentAmount) {
        throw "Payment $($Operation.OperationId) inputs do not match its saved verification. Recovery stopped."
    }
}

function Assert-LedgerNoPendingInvoicePayment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [psobject]$Invoice,
        [guid]$ExceptPaymentId = [guid]::Empty
    )
    foreach ($operation in Get-LedgerInvoicePaymentOperation -JournalPath $JournalPath) {
        if ($operation.OperationId -eq $ExceptPaymentId -or
            ($Invoice -and $operation.InvoiceNumber -ne $Invoice.InvoiceNumber)) { continue }
        $current = if ($Invoice) { $Invoice } else {
            $path = Join-Path $JournalPath 'invoices' (Get-LedgerInvoiceFileName -InvoiceNumber $operation.InvoiceNumber)
            Read-LedgerInvoiceFile -Path $path
        }
        if (-not (Get-LedgerRecordedInvoicePayment -Invoice $current -Operation $operation)) {
            throw "Invoice $($operation.InvoiceNumber) has an unfinished payment. Resume it with Add-LedgerInvoicePayment -JournalPath '$JournalPath' -InvoiceNumber $($operation.InvoiceNumber) -PaymentId '$($operation.OperationId)' before making other changes or matching bank transactions."
        }
    }
}
