# Recoverable operation plans for late charges (fees and interest) and credit
# notes on customer invoices. Plans are immutable, written before the
# verification and reserve its number, so an interrupted command can be
# completed by repeating it.

function Read-LedgerInvoiceOperationFields {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$Path)
    $fields = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';')) { continue }
        if ($line -notmatch '^([A-Za-z]+):\t(.+)$' -or $fields.ContainsKey($Matches[1])) {
            throw "Invalid invoice operation record '$Path': malformed or duplicate field."
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
        throw "Invalid invoice operation record '$Path': missing or invalid identity, reservation or hash."
    }
    $null = Assert-LedgerSafeLeafName -Name $fields.FiscalYear -Kind 'fiscal year'
    [pscustomobject]@{
        Fields = $fields
        Operation = [pscustomobject]@{
            OperationId = $id; InvoiceNumber = $invoiceNumber; FiscalYear = $fields.FiscalYear
            VerificationNumber = $verificationNumber; InvoiceHash = $fields.InvoiceHash; VerificationHash = $fields.VerificationHash
        }
    }
}

function ConvertFrom-LedgerInvoiceOperationDate {
    [CmdletBinding()]
    param ([string]$Text)
    $date = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Text, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$date)) { return $null }
    $date
}

function Read-LedgerInvoiceChargeOperation {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$Path)
    $record = Read-LedgerInvoiceOperationFields -Path $Path
    $fields = $record.Fields
    $operation = $record.Operation
    $date = ConvertFrom-LedgerInvoiceOperationDate -Text $fields.ChargeDate
    $amount = [decimal]0
    $reminderCount = 0
    if ($fields.ChargeType -cnotin 'Fee', 'Interest' -or $null -eq $date -or
        $fields.ChargeAmount -notmatch '^\d+(\.\d{1,2})?$' -or
        -not [decimal]::TryParse([string]$fields.ChargeAmount, [Globalization.NumberStyles]::AllowDecimalPoint,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$amount) -or $amount -le 0 -or
        $fields.ChargeAccount -notmatch '^\d+$' -or
        ($fields.ContainsKey('ReminderCount') -and ($fields.ChargeType -ne 'Fee' -or
            -not [int]::TryParse([string]$fields.ReminderCount, [ref]$reminderCount) -or $reminderCount -le 0))) {
        throw "Invalid invoice charge record '$Path': invalid charge type, date, amount, account or reminder count."
    }
    if ((Split-Path $Path -Leaf) -ne "$($operation.OperationId).txt") {
        throw "Invalid invoice charge record '$Path': identity does not match its filename."
    }
    $operation | Add-Member -NotePropertyMembers @{
        ChargeType = $fields.ChargeType; ChargeDate = $date; ChargeAmount = $amount
        ChargeAccount = $fields.ChargeAccount; ReminderCount = $reminderCount
    }
    $operation
}

function Get-LedgerInvoiceChargeOperation {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$JournalPath)
    $directory = Join-Path $JournalPath 'invoices' 'charges'
    if (-not (Test-Path -LiteralPath $directory)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $directory -Filter '*.txt' -File -ErrorAction Stop) {
        Read-LedgerInvoiceChargeOperation -Path $file.FullName
    }
}

function Save-LedgerInvoiceChargeOperation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    $null = New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force -ErrorAction Stop
    $lines = @(
        '; PSLedger customer invoice charge'
        "FormatVersion:`t1"
        "OperationId:`t$($Operation.OperationId)"
        "InvoiceNumber:`t$($Operation.InvoiceNumber)"
        "FiscalYear:`t$($Operation.FiscalYear)"
        "VerificationNumber:`t$($Operation.VerificationNumber)"
        "InvoiceHash:`t$($Operation.InvoiceHash)"
        "VerificationHash:`t$($Operation.VerificationHash)"
        "ChargeType:`t$($Operation.ChargeType)"
        "ChargeDate:`t$($Operation.ChargeDate.ToString('yyyy-MM-dd'))"
        "ChargeAmount:`t$(Format-LedgerInvoiceAmount -Value $Operation.ChargeAmount)"
        "ChargeAccount:`t$($Operation.ChargeAccount)"
    )
    if ($Operation.ReminderCount) { $lines += "ReminderCount:`t$($Operation.ReminderCount)" }
    Set-LedgerFileContent -Path $Path -NoClobber -Value $lines
}

function Get-LedgerRecordedInvoiceCharge {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [psobject]$Invoice,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    $charges = @($Invoice.Charges | Where-Object {
        $_.VerificationNumber -eq $Operation.VerificationNumber -and $_.FiscalYear -eq $Operation.FiscalYear
    })
    if ($charges.Count -gt 1 -or ($charges.Count -eq 1 -and
            ($charges[0].Date -ne $Operation.ChargeDate -or $charges[0].Amount -ne $Operation.ChargeAmount -or
            $charges[0].Type -ne $Operation.ChargeType -or $charges[0].Account -ne $Operation.ChargeAccount -or
            ($Operation.ReminderCount -and [int]$Invoice.ReminderCount -lt $Operation.ReminderCount)))) {
        throw "Invoice $($Invoice.InvoiceNumber) has conflicting charge references for ChargeId $($Operation.OperationId). Recovery stopped."
    }
    $charges
}

function Get-LedgerInvoiceChargeCommand {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [psobject]$Operation, [Parameter(Mandatory)] [string]$JournalPath)
    $common = "-JournalPath '$JournalPath' -InvoiceNumber $($Operation.InvoiceNumber) -ChargeId '$($Operation.OperationId)'"
    $amount = Format-LedgerInvoiceAmount -Value $Operation.ChargeAmount
    if ($Operation.ReminderCount) { "Add-LedgerInvoiceReminder $common -Fee $amount -BookFee" }
    elseif ($Operation.ChargeType -eq 'Interest') { "Add-LedgerInvoiceInterest $common" }
    else { "Add-LedgerInvoiceFee $common -Amount $amount" }
}

function Get-LedgerInvoiceCreditPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [int]$InvoiceNumber
    )
    Join-Path $JournalPath 'invoices' 'credits' (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
}

function Read-LedgerInvoiceCreditOperation {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$Path)
    $record = Read-LedgerInvoiceOperationFields -Path $Path
    $fields = $record.Fields
    $operation = $record.Operation
    $creditNumber = 0
    $date = ConvertFrom-LedgerInvoiceOperationDate -Text $fields.CreditDate
    if (-not [int]::TryParse([string]$fields.CreditInvoiceNumber, [ref]$creditNumber) -or
        $creditNumber -le 0 -or $creditNumber -eq $operation.InvoiceNumber -or $null -eq $date) {
        throw "Invalid credit invoice record '$Path': invalid credit invoice number or date."
    }
    if ((Split-Path $Path -Leaf) -ne (Get-LedgerInvoiceFileName -InvoiceNumber $operation.InvoiceNumber)) {
        throw "Invalid credit invoice record '$Path': identity does not match its filename."
    }
    $operation | Add-Member -NotePropertyMembers @{ CreditInvoiceNumber = $creditNumber; CreditDate = $date }
    $operation
}

function Get-LedgerInvoiceCreditOperation {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$JournalPath)
    $directory = Join-Path $JournalPath 'invoices' 'credits'
    if (-not (Test-Path -LiteralPath $directory)) { return }
    $numbers = [Collections.Generic.HashSet[int]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $directory -Filter 'inv*.txt' -File -ErrorAction Stop) {
        $operation = Read-LedgerInvoiceCreditOperation -Path $file.FullName
        if (-not $numbers.Add($operation.CreditInvoiceNumber)) {
            throw "Credit invoice number $($operation.CreditInvoiceNumber) is reserved by more than one credit plan."
        }
        $operation
    }
}

function Save-LedgerInvoiceCreditOperation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    $null = New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force -ErrorAction Stop
    Set-LedgerFileContent -Path $Path -NoClobber -Value @(
        '; PSLedger customer credit invoice'
        "FormatVersion:`t1"
        "OperationId:`t$($Operation.OperationId)"
        "InvoiceNumber:`t$($Operation.InvoiceNumber)"
        "CreditInvoiceNumber:`t$($Operation.CreditInvoiceNumber)"
        "FiscalYear:`t$($Operation.FiscalYear)"
        "VerificationNumber:`t$($Operation.VerificationNumber)"
        "InvoiceHash:`t$($Operation.InvoiceHash)"
        "VerificationHash:`t$($Operation.VerificationHash)"
        "CreditDate:`t$($Operation.CreditDate.ToString('yyyy-MM-dd'))"
    )
}

function Assert-LedgerCreditNote {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [psobject]$CreditNote,
        [Parameter(Mandatory)] [psobject]$Original,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    if ($CreditNote.InvoiceNumber -ne $Operation.CreditInvoiceNumber -or $CreditNote.Status -ne 'Credited' -or
        $CreditNote.CustomerNumber -ne $Original.CustomerNumber -or
        $CreditNote.InvoiceDate -ne $Operation.CreditDate -or
        $CreditNote.BookedVerification -ne $Operation.VerificationNumber -or
        $CreditNote.BookedFiscalYear -ne $Operation.FiscalYear -or
        $CreditNote.Description -ne "Kreditfaktura för faktura $($Operation.InvoiceNumber)" -or
        $CreditNote.Total -ne -$Original.Total) {
        throw "Credit invoice $($Operation.CreditInvoiceNumber) differs from the credit plan for invoice $($Operation.InvoiceNumber). Recovery stopped."
    }
}

function Get-LedgerNextInvoiceNumber {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$JournalPath)
    $invoiceDir = Get-LedgerInvoiceDirectory -JournalPath $JournalPath
    $numbers = @(Get-ChildItem -LiteralPath $invoiceDir -Filter 'inv*.txt' -File -ErrorAction SilentlyContinue |
            ForEach-Object { if ($_.BaseName -match '^inv(\d+)$') { [int]$Matches[1] } })
    $numbers += @(Get-LedgerInvoiceCreditOperation -JournalPath $JournalPath | ForEach-Object CreditInvoiceNumber)
    if ($numbers.Count) { [int]($numbers | Measure-Object -Maximum).Maximum + 1 } else { 1 }
}
