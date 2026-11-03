function Get-LedgerInvoicePaymentOperation {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$JournalPath)

    $ids = [Collections.Generic.HashSet[guid]]::new()
    foreach ($store in 'invoices', 'supplierinvoices') {
        $directory = Join-Path $JournalPath $store 'payments'
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $directory -Filter '*.txt' -File -ErrorAction Stop) {
            $operation = Read-LedgerInvoicePosting -Path $file.FullName -Payment -Supplier:($store -eq 'supplierinvoices')
            if (-not $ids.Add($operation.OperationId)) { throw "PaymentId $($operation.OperationId) is duplicated in the journal." }
            $operation
        }
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
    $supplier = $Operation.InvoiceType -eq 'Supplier'
    $description = if ($supplier) { "Betalning leverantörsfaktura $($Operation.InvoiceNumber)" } else { "Betalning kundfaktura $($Operation.InvoiceNumber)" }
    $debitAccount = if ($supplier) { $Invoice.PayableAccount } else { $Operation.PaymentAccount }
    $creditAccount = if ($supplier) { $Operation.PaymentAccount } else { $Invoice.ReceivableAccount }
    if ($entry.Date -ne $Operation.PaymentDate.ToString('yyyy-MM-dd') -or
        $entry.Description -ne $description -or
        $entry.Rows.Count -ne 2 -or
        $entry.Rows[0].Account -ne $debitAccount -or $entry.Rows[0].Amount -ne $Operation.PaymentAmount -or
        $entry.Rows[1].Account -ne $creditAccount -or $entry.Rows[1].Amount -ne -$Operation.PaymentAmount) {
        throw "Payment $($Operation.OperationId) inputs do not match its saved verification. Recovery stopped."
    }
}

function Assert-LedgerNoPendingInvoicePayment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [psobject]$Invoice,
        [ValidateSet('Customer', 'Supplier')] [string]$InvoiceType = 'Customer',
        [guid]$ExceptPaymentId = [guid]::Empty,
        [guid]$ExceptChargeId = [guid]::Empty,
        [switch]$ExceptCredit
    )
    $readInvoice = {
        param($number, $supplier)
        if ($Invoice -and $Invoice.InvoiceNumber -eq $number -and ($InvoiceType -eq 'Supplier') -eq $supplier) { return $Invoice }
        if ($supplier) {
            Read-LedgerSupplierInvoiceFile -Path (Join-Path $JournalPath 'supplierinvoices' (Get-LedgerSupplierInvoiceFileName -InvoiceNumber $number))
        }
        else {
            Read-LedgerInvoiceFile -Path (Join-Path $JournalPath 'invoices' (Get-LedgerInvoiceFileName -InvoiceNumber $number))
        }
    }
    foreach ($operation in Get-LedgerInvoicePaymentOperation -JournalPath $JournalPath) {
        if ($operation.OperationId -eq $ExceptPaymentId -or
            ($Invoice -and ($operation.InvoiceNumber -ne $Invoice.InvoiceNumber -or $operation.InvoiceType -ne $InvoiceType))) { continue }
        $supplier = $operation.InvoiceType -eq 'Supplier'
        $current = & $readInvoice $operation.InvoiceNumber $supplier
        if (-not (Get-LedgerRecordedInvoicePayment -Invoice $current -Operation $operation)) {
            $command = if ($supplier) { 'Add-LedgerSupplierPayment' } else { 'Add-LedgerInvoicePayment' }
            throw "$($operation.InvoiceType) invoice $($operation.InvoiceNumber) has an unfinished payment. Resume it with $command -JournalPath '$JournalPath' -InvoiceNumber $($operation.InvoiceNumber) -PaymentId '$($operation.OperationId)' before making other changes or matching bank transactions."
        }
    }
    if ($Invoice -and $InvoiceType -ne 'Customer') { return }
    foreach ($operation in Get-LedgerInvoiceChargeOperation -JournalPath $JournalPath) {
        if ($operation.OperationId -eq $ExceptChargeId -or ($Invoice -and $operation.InvoiceNumber -ne $Invoice.InvoiceNumber)) { continue }
        $current = & $readInvoice $operation.InvoiceNumber $false
        if (-not (Get-LedgerRecordedInvoiceCharge -Invoice $current -Operation $operation)) {
            throw "Customer invoice $($operation.InvoiceNumber) has an unfinished charge. Resume it with $(Get-LedgerInvoiceChargeCommand -Operation $operation -JournalPath $JournalPath) before making other changes or matching bank transactions."
        }
    }
    foreach ($operation in Get-LedgerInvoiceCreditOperation -JournalPath $JournalPath) {
        if ($Invoice -and $operation.InvoiceNumber -ne $Invoice.InvoiceNumber) { continue }
        if ($ExceptCredit -and $Invoice -and $operation.InvoiceNumber -eq $Invoice.InvoiceNumber) { continue }
        $current = & $readInvoice $operation.InvoiceNumber $false
        if ($current.Status -ne 'Credited') {
            throw "Customer invoice $($operation.InvoiceNumber) has an unfinished credit. Resume it with Add-LedgerCreditInvoice -JournalPath '$JournalPath' -InvoiceNumber $($operation.InvoiceNumber) before making other changes or matching bank transactions."
        }
    }
}
