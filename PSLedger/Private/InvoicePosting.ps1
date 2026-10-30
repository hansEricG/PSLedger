function Get-LedgerInvoicePostingPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [int]$InvoiceNumber
    )
    Join-Path $JournalPath 'invoices' 'posting' (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
}

function Read-LedgerInvoicePosting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [switch]$Payment
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
    $fileName = if ($Payment) { "$id.txt" } else { Get-LedgerInvoiceFileName -InvoiceNumber $invoiceNumber }
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
            PaymentDate = $date; PaymentAmount = $amount; PaymentAccount = $fields.PaymentAccount
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
    $directory = Join-Path $JournalPath 'invoices' 'posting'
    if (Test-Path -LiteralPath $directory) {
        foreach ($file in Get-ChildItem -LiteralPath $directory -Filter 'inv*.txt' -File -ErrorAction Stop) {
            $operation = Read-LedgerInvoicePosting -Path $file.FullName
            if ($operation.FiscalYear -eq $FiscalYear) { $operation.VerificationNumber }
        }
    }
    foreach ($operation in Get-LedgerInvoicePaymentOperation -JournalPath $JournalPath) {
        if ($operation.FiscalYear -eq $FiscalYear) { $operation.VerificationNumber }
    }
}

function Save-LedgerInvoicePosting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [psobject]$Operation,
        [switch]$Payment
    )
    $null = New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force -ErrorAction Stop
    $lines = @(
        '; PSLedger customer invoice posting'
        "FormatVersion:`t1"
        "OperationId:`t$($Operation.OperationId)"
        "InvoiceNumber:`t$($Operation.InvoiceNumber)"
        "FiscalYear:`t$($Operation.FiscalYear)"
        "VerificationNumber:`t$($Operation.VerificationNumber)"
        "InvoiceHash:`t$($Operation.InvoiceHash)"
        "VerificationHash:`t$($Operation.VerificationHash)"
    )
    if ($Payment) {
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
