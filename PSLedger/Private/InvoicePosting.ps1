function Get-LedgerInvoicePostingPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [int]$InvoiceNumber,
        [switch]$Supplier
    )
    if ($Supplier) {
        return Join-Path $JournalPath 'supplierinvoices' 'posting' (Get-LedgerSupplierInvoiceFileName -InvoiceNumber $InvoiceNumber)
    }
    Join-Path $JournalPath 'invoices' 'posting' (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
}

function Read-LedgerInvoicePosting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [switch]$Payment,
        [switch]$Supplier
    )

    $fields = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';')) { continue }
        if ($line -notmatch '^([A-Za-z]+):\t(.+)$' -or $fields.ContainsKey($Matches[1])) {
            throw "Invalid invoice posting record '$Path': malformed or duplicate field."
        }
        $fields[$Matches[1]] = $Matches[2]
    }
    $id = [guid]::Empty
    $invoiceNumber = 0
    $verificationNumber = 0
    if ($fields.FormatVersion -ne '1' -or
        -not [guid]::TryParseExact([string]$fields.OperationId, 'D', [ref]$id) -or $id -eq [guid]::Empty -or
        -not [int]::TryParse([string]$fields.InvoiceNumber, [ref]$invoiceNumber) -or $invoiceNumber -le 0 -or
        -not [int]::TryParse([string]$fields.VerificationNumber, [ref]$verificationNumber) -or $verificationNumber -le 0 -or
        [string]::IsNullOrWhiteSpace($fields.FiscalYear) -or
        $fields.InvoiceHash -cnotmatch '^[0-9a-f]{64}$' -or $fields.VerificationHash -cnotmatch '^[0-9a-f]{64}$') {
        throw "Invalid invoice posting record '$Path': missing or invalid identity, reservation or hash."
    }
    $null = Assert-LedgerSafeLeafName -Name $fields.FiscalYear -Kind 'fiscal year'
    $fileName = if ($Payment) { "$id.txt" }
    elseif ($Supplier) { Get-LedgerSupplierInvoiceFileName -InvoiceNumber $invoiceNumber }
    else { Get-LedgerInvoiceFileName -InvoiceNumber $invoiceNumber }
    if (-not $Payment -and (($Supplier -and $fields.InvoiceType -ne 'Supplier') -or
            (-not $Supplier -and $fields.ContainsKey('InvoiceType') -and $fields.InvoiceType -ne 'Customer'))) {
        throw "Invalid invoice posting record '$Path': invoice type does not match its posting directory."
    }
    if ((Split-Path $Path -Leaf) -ne $fileName) {
        throw "Invalid invoice posting record '$Path': identity does not match its filename."
    }
    $operation = [pscustomobject]@{
        OperationId = $id
        InvoiceNumber = $invoiceNumber
        FiscalYear = $fields.FiscalYear
        VerificationNumber = $verificationNumber
        InvoiceHash = $fields.InvoiceHash
        VerificationHash = $fields.VerificationHash
    }
    if ($Payment) {
        $invoiceType = if ($Supplier) { 'Supplier' } else { 'Customer' }
        if (($Supplier -and $fields.InvoiceType -ne 'Supplier') -or
            ($fields.ContainsKey('InvoiceType') -and $fields.InvoiceType -ne $invoiceType)) {
            throw "Invalid invoice posting record '$Path': invoice type does not match its payment directory."
        }
        $date = [datetime]::MinValue
        $amount = [decimal]0
        if (-not [datetime]::TryParseExact([string]$fields.PaymentDate, 'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date) -or
            $fields.PaymentAmount -notmatch '^\d+(\.\d{1,2})?$' -or
            -not [decimal]::TryParse([string]$fields.PaymentAmount, [Globalization.NumberStyles]::AllowDecimalPoint,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$amount) -or $amount -le 0 -or
            $fields.PaymentAccount -notmatch '^\d+$') {
            throw "Invalid invoice posting record '$Path': invalid payment date, amount or account."
        }
        $operation | Add-Member -NotePropertyMembers @{
            PaymentDate = $date; PaymentAmount = $amount; PaymentAccount = $fields.PaymentAccount; InvoiceType = $invoiceType
        }
        if ($fields.ContainsKey('BankTransactionId') -or $fields.ContainsKey('BankStatementNumber') -or $fields.ContainsKey('BankTransactionHash')) {
            $transactionId = 0
            $statementNumber = 0
            if (-not [int]::TryParse([string]$fields.BankTransactionId, [ref]$transactionId) -or $transactionId -le 0 -or
                -not [int]::TryParse([string]$fields.BankStatementNumber, [ref]$statementNumber) -or $statementNumber -le 0 -or
                $fields.BankTransactionHash -cnotmatch '^[0-9a-f]{64}$') {
                throw "Invalid invoice posting record '$Path': invalid bank transaction identity or hash."
            }
            $operation | Add-Member -NotePropertyMembers @{
                BankTransactionId = $transactionId; BankStatementNumber = $statementNumber; BankTransactionHash = $fields.BankTransactionHash
            }
        }
    }
    $operation
}

function Get-LedgerInvoicePostingReservation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [string]$FiscalYear
    )
    foreach ($store in @(
            @{ Directory = 'invoices'; Filter = 'inv*.txt'; Supplier = $false }
            @{ Directory = 'supplierinvoices'; Filter = 'sup*.txt'; Supplier = $true }
        )) {
        $directory = Join-Path $JournalPath $store.Directory 'posting'
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $directory -Filter $store.Filter -File -ErrorAction Stop) {
            $operation = Read-LedgerInvoicePosting -Path $file.FullName -Supplier:$store.Supplier
            if ($operation.FiscalYear -eq $FiscalYear) { $operation.VerificationNumber }
        }
    }
    foreach ($operation in @(Get-LedgerInvoicePaymentOperation -JournalPath $JournalPath) +
        @(Get-LedgerInvoiceChargeOperation -JournalPath $JournalPath) +
        @(Get-LedgerInvoiceCreditOperation -JournalPath $JournalPath)) {
        if ($operation.FiscalYear -eq $FiscalYear) { $operation.VerificationNumber }
    }
}

function Save-LedgerInvoicePosting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [psobject]$Operation,
        [switch]$Payment,
        [switch]$Supplier
    )
    $null = New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force -ErrorAction Stop
    $header = if ($Payment -and $Operation.InvoiceType -eq 'Supplier') { '; PSLedger supplier invoice payment' }
    elseif ($Supplier) { '; PSLedger supplier invoice posting' }
    else { '; PSLedger customer invoice posting' }
    $lines = @(
        $header
        "FormatVersion:`t1"
        "OperationId:`t$($Operation.OperationId)"
        "InvoiceNumber:`t$($Operation.InvoiceNumber)"
        "FiscalYear:`t$($Operation.FiscalYear)"
        "VerificationNumber:`t$($Operation.VerificationNumber)"
        "InvoiceHash:`t$($Operation.InvoiceHash)"
        "VerificationHash:`t$($Operation.VerificationHash)"
    )
    if ($Supplier -and -not $Payment) { $lines += "InvoiceType:`tSupplier" }
    if ($Payment) {
        if ($Operation.InvoiceType -eq 'Supplier') { $lines += "InvoiceType:`tSupplier" }
        $lines += @(
            "PaymentDate:`t$($Operation.PaymentDate.ToString('yyyy-MM-dd'))"
            "PaymentAmount:`t$(Format-LedgerInvoiceAmount -Value $Operation.PaymentAmount)"
            "PaymentAccount:`t$($Operation.PaymentAccount)"
        )
        if ($Operation.PSObject.Properties['BankTransactionId']) {
            $lines += @(
                "BankTransactionId:`t$($Operation.BankTransactionId)"
                "BankStatementNumber:`t$($Operation.BankStatementNumber)"
                "BankTransactionHash:`t$($Operation.BankTransactionHash)"
            )
        }
    }
    Set-LedgerFileContent -Path $Path -NoClobber -Value $lines
}

function Assert-LedgerInvoicePostingIntegrity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [string]$FiscalYear,
        [int]$UnsealedVerification = 0
    )
    $check = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
    $issues = @($check.Issues | Where-Object {
        -not ($_.Kind -eq 'Verification' -and $_.Problem -eq 'Unsealed' -and $_.Key -eq "$UnsealedVerification")
    })
    if ($issues.Count) {
        throw "Invoice posting cannot continue because of integrity issues. Run Test-LedgerIntegrity and resolve them first: $($issues.Detail -join ' ')"
    }
}

function Assert-LedgerInvoicePostingVerification {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    if ((Get-LedgerContentHash -Path $Path) -ne $Operation.VerificationHash -or
        "OperationId: $($Operation.OperationId)" -notin @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)) {
        throw "Saved verification '$Path' differs from the invoice posting plan. Recovery stopped without rewriting it."
    }
}

function Complete-LedgerInvoicePostingVerification {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    $yearDir = Join-Path $JournalPath $Operation.FiscalYear
    $path = Join-Path $yearDir ('ver' + $Operation.VerificationNumber.ToString('0000') + '.txt')
    Assert-LedgerInvoicePostingVerification -Path $path -Operation $Operation
    Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $Operation.FiscalYear `
        -UnsealedVerification $Operation.VerificationNumber
    $chain = Read-LedgerIntegrityChain -YearDir $yearDir
    $state = Get-LedgerIntegrityState -Chain $chain
    if (-not $state.Verifications.Contains("$($Operation.VerificationNumber)")) {
        Register-LedgerIntegrityItem -YearDir $yearDir -Kind Verification -Key "$($Operation.VerificationNumber)" -Path $path
    }
}
function Invoke-LedgerInvoicePostingOperation {
    # Shared, resumable posting of a draft customer or supplier invoice. The caller
    # holds the journal lock. Returns $true when the posting completed, $false on WhatIf.
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [int]$InvoiceNumber,
        [string]$FiscalYear,
        [switch]$Supplier
    )
    if ($Supplier) {
        $label = 'Supplier invoice'
        $commandName = 'Invoke-LedgerSupplierInvoicePosting'
        $filePath = Join-Path (Get-LedgerSupplierInvoiceDirectory -JournalPath $JournalPath) (Get-LedgerSupplierInvoiceFileName -InvoiceNumber $InvoiceNumber)
    }
    else {
        $label = 'Invoice'
        $commandName = 'Invoke-LedgerInvoicePosting'
        $filePath = Join-Path (Get-LedgerInvoiceDirectory -JournalPath $JournalPath) (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
    }
    $lowerLabel = $label.ToLowerInvariant()
    if (-not (Test-Path $filePath)) {
        throw "$label $InvoiceNumber does not exist."
    }

    $invoice = if ($Supplier) { Read-LedgerSupplierInvoiceFile -Path $filePath } else { Read-LedgerInvoiceFile -Path $filePath }

    if ($invoice.Status -ne 'Draft') {
        throw "$label $InvoiceNumber is already posted (status '$($invoice.Status)', verification $($invoice.BookedVerification))."
    }
    if ($invoice.InvoiceNumber -ne $InvoiceNumber -or $invoice.BookedVerification -or $invoice.BookedFiscalYear) {
        throw "Draft $lowerLabel $InvoiceNumber has inconsistent identity or posting references. Inspect it before posting."
    }

    $operationPath = Get-LedgerInvoicePostingPath -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber -Supplier:$Supplier
    $operation = if (Test-Path -LiteralPath $operationPath) { Read-LedgerInvoicePosting -Path $operationPath -Supplier:$Supplier } else { $null }
    $invoiceHash = Get-LedgerContentHash -Path $filePath
    $postingYear = $FiscalYear
    if ($operation) {
        if ($invoiceHash -ne $operation.InvoiceHash) {
            throw "$label $InvoiceNumber has changed since its posting plan was saved. Recovery stopped without modifying the invoice or verification."
        }
        if ($postingYear -and $postingYear -ne $operation.FiscalYear) {
            throw "$label $InvoiceNumber has a posting plan for $($operation.FiscalYear), not $postingYear."
        }
        $postingYear = $operation.FiscalYear
    }

    # Resolve the fiscal year from the invoice date unless one was supplied.
    if (-not $postingYear) {
        $postingYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $invoice.InvoiceDate
        if (-not $postingYear) {
            throw "No fiscal year covers the invoice date $($invoice.InvoiceDate.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
        }
    }

    # Aggregate amounts per account so the verification is compact.
    $accountSums = [ordered]@{}
    $addAmount = {
        param($account, $amount)
        if ($accountSums.Contains($account)) {
            $accountSums[$account] += $amount
        }
        else {
            $accountSums[$account] = $amount
        }
    }

    if ($Supplier) {
        # Debit cost accounts (net) and input VAT, then credit the payable with the gross total.
        foreach ($row in $invoice.Rows) {
            & $addAmount $row.Account $row.Amount
            if ($row.VatAmount -ne 0) {
                & $addAmount $row.VatAccount $row.VatAmount
            }
        }
        & $addAmount $invoice.PayableAccount (-$invoice.Total)
        $description = "Leverantörsfaktura $InvoiceNumber - $($invoice.Description)"
    }
    else {
        # Debit the receivable with the gross total, then credit revenue (net) and VAT.
        & $addAmount $invoice.ReceivableAccount $invoice.Total
        foreach ($row in $invoice.Rows) {
            & $addAmount $row.Account (-$row.Amount)
            if ($row.VatAmount -ne 0) {
                & $addAmount $row.VatAccount (-$row.VatAmount)
            }
        }
        $description = "Kundfaktura $InvoiceNumber - $($invoice.Description)"
    }

    $entryRows = foreach ($account in $accountSums.Keys) {
        @{ Account = $account; Amount = [Math]::Round([decimal]$accountSums[$account], 2) }
    }

    $operationId = if ($operation) { $operation.OperationId } else { [guid]::NewGuid() }
    $entryParameters = @{
        JournalPath = $JournalPath; FiscalYear = $postingYear; Date = $invoice.InvoiceDate
        Description = $description; Rows = @($entryRows); OperationId = $operationId
    }
    $existingVerification = $false
    if ($operation) {
        $verificationPath = Join-Path $JournalPath $postingYear ('ver' + $operation.VerificationNumber.ToString('0000') + '.txt')
        $existingVerification = Test-Path -LiteralPath $verificationPath
        if ($existingVerification) {
            Assert-LedgerInvoicePostingVerification -Path $verificationPath -Operation $operation
        }
    }
    $unsealedNumber = if ($existingVerification) { $operation.VerificationNumber } else { 0 }
    Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $postingYear -UnsealedVerification $unsealedNumber
    if (-not $existingVerification) {
        $lines = @(Get-LedgerVerificationLines @entryParameters)
        $verificationHash = Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
        if ($operation -and $verificationHash -ne $operation.VerificationHash) {
            throw "$label $InvoiceNumber no longer produces the saved verification plan. Recovery stopped."
        }
        if (-not $operation) {
            $operation = [pscustomobject]@{
                OperationId = $operationId
                InvoiceNumber = $InvoiceNumber
                FiscalYear = $postingYear
                VerificationNumber = Get-LedgerNextVerificationNumber -JournalPath $JournalPath -FiscalYear $postingYear
                InvoiceHash = $invoiceHash
                VerificationHash = $verificationHash
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess("$label $InvoiceNumber", "Post to fiscal year $postingYear")) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $operationPath)) {
        Save-LedgerInvoicePosting -Path $operationPath -Operation $operation -Supplier:$Supplier
    }
    try {
        if (-not $existingVerification) {
            Write-LedgerVerification @entryParameters -ReservedNumber $operation.VerificationNumber -Confirm:$false
        }
        Complete-LedgerInvoicePostingVerification -JournalPath $JournalPath -Operation $operation
        if ((Get-LedgerContentHash -Path $filePath) -ne $operation.InvoiceHash) {
            throw "$label $InvoiceNumber changed during posting. Its saved verification was not removed."
        }

        $invoice.Status = 'Booked'
        $invoice.BookedVerification = $operation.VerificationNumber
        $invoice.BookedFiscalYear = $postingYear
        if ($Supplier) { Save-LedgerSupplierInvoiceFile -Invoice $invoice } else { Save-LedgerInvoiceFile -Invoice $invoice }
    }
    catch {
        throw [System.InvalidOperationException]::new(
            "Could not confirm completion of $lowerLabel $InvoiceNumber posting. Keep '$operationPath' and its reserved verification; rerun $commandName for this invoice to recover safely. $($_.Exception.Message)",
            $_.Exception)
    }
    $true
}
