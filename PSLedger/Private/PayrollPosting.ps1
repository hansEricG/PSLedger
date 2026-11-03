# Recoverable payroll posting. An immutable plan in payslips/posting/payNNNN.txt
# is written before the verification and reserves its number, so an interrupted
# Invoke-LedgerPayrollPosting can be completed by repeating it.

function Get-LedgerPayslipPostingPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [int]$PayslipNumber
    )
    Join-Path $JournalPath 'payslips' 'posting' (Get-LedgerPayslipFileName -PayslipNumber $PayslipNumber)
}

function Read-LedgerPayslipPosting {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$Path)
    $fields = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';')) { continue }
        if ($line -notmatch '^([A-Za-z]+):\t(.+)$' -or $fields.ContainsKey($Matches[1])) {
            throw "Invalid payslip posting record '$Path': malformed or duplicate field."
        }
        $fields[$Matches[1]] = $Matches[2]
    }
    $id = [guid]::Empty
    $payslipNumber = 0
    $verificationNumber = 0
    if ($fields.FormatVersion -ne '1' -or
        -not [guid]::TryParseExact([string]$fields.OperationId, 'D', [ref]$id) -or $id -eq [guid]::Empty -or
        -not [int]::TryParse([string]$fields.PayslipNumber, [ref]$payslipNumber) -or $payslipNumber -le 0 -or
        -not [int]::TryParse([string]$fields.VerificationNumber, [ref]$verificationNumber) -or $verificationNumber -le 0 -or
        [string]::IsNullOrWhiteSpace($fields.FiscalYear) -or
        $fields.PayslipHash -cnotmatch '^[0-9a-f]{64}$' -or $fields.VerificationHash -cnotmatch '^[0-9a-f]{64}$') {
        throw "Invalid payslip posting record '$Path': missing or invalid identity, reservation or hash."
    }
    $null = Assert-LedgerSafeLeafName -Name $fields.FiscalYear -Kind 'fiscal year'
    if ((Split-Path $Path -Leaf) -ne (Get-LedgerPayslipFileName -PayslipNumber $payslipNumber)) {
        throw "Invalid payslip posting record '$Path': identity does not match its filename."
    }
    [pscustomobject]@{
        OperationId = $id; PayslipNumber = $payslipNumber; FiscalYear = $fields.FiscalYear
        VerificationNumber = $verificationNumber; PayslipHash = $fields.PayslipHash; VerificationHash = $fields.VerificationHash
    }
}

function Get-LedgerPayslipPostingOperation {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$JournalPath)
    $directory = Join-Path $JournalPath 'payslips' 'posting'
    if (-not (Test-Path -LiteralPath $directory)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $directory -Filter 'pay*.txt' -File -ErrorAction Stop) {
        Read-LedgerPayslipPosting -Path $file.FullName
    }
}

function Save-LedgerPayslipPosting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    $null = New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force -ErrorAction Stop
    Set-LedgerFileContent -Path $Path -NoClobber -Value @(
        '; PSLedger payslip posting'
        "FormatVersion:`t1"
        "OperationId:`t$($Operation.OperationId)"
        "PayslipNumber:`t$($Operation.PayslipNumber)"
        "FiscalYear:`t$($Operation.FiscalYear)"
        "VerificationNumber:`t$($Operation.VerificationNumber)"
        "PayslipHash:`t$($Operation.PayslipHash)"
        "VerificationHash:`t$($Operation.VerificationHash)"
    )
}
