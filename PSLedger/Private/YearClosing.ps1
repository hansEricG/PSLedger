# Recoverable fiscal-year closing. An immutable plan in <year>/closing.txt is written
# before the result verification and the status change, so an interrupted
# Close-LedgerFiscalYear can be completed by repeating it.

function Get-LedgerYearClosingPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [string]$FiscalYear
    )
    Join-Path $JournalPath $FiscalYear 'closing.txt'
}

function Read-LedgerYearClosing {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$Path)
    $fields = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';')) { continue }
        if ($line -notmatch '^([A-Za-z]+):\t(.+)$' -or $fields.ContainsKey($Matches[1])) {
            throw "Invalid fiscal year closing record '$Path': malformed or duplicate field."
        }
        $fields[$Matches[1]] = $Matches[2]
    }
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $id = [guid]::Empty
    $number = -1
    $amount = [decimal]0
    $valid = $fields.FormatVersion -eq '1' -and
        [guid]::TryParseExact([string]$fields.OperationId, 'D', [ref]$id) -and $id -ne [guid]::Empty -and
        $fields.FiscalYear -eq (Split-Path (Split-Path $Path -Parent) -Leaf) -and
        [int]::TryParse([string]$fields.ResultVerification, [Globalization.NumberStyles]::None, $invariant, [ref]$number)
    if ($valid -and $fields.ContainsKey('ResultAmount')) {
        $valid = [decimal]::TryParse($fields.ResultAmount, [Globalization.NumberStyles]::AllowLeadingSign -bor [Globalization.NumberStyles]::AllowDecimalPoint, $invariant, [ref]$amount)
    }
    if ($valid -and $number -gt 0) {
        $valid = $fields.ContainsKey('ResultAmount') -and $amount -ne 0 -and
            $fields.ResultAccount -match '^\d+$' -and $fields.EquityAccount -match '^\d+$' -and
            $fields.VerificationHash -cmatch '^[0-9a-f]{64}$'
    }
    elseif ($valid) {
        $valid = -not ($fields.ContainsKey('ResultAccount') -or $fields.ContainsKey('EquityAccount') -or $fields.ContainsKey('VerificationHash')) -and
            (-not $fields.ContainsKey('ResultAmount') -or $amount -eq 0)
    }
    if (-not $valid) {
        throw "Invalid fiscal year closing record '$Path': missing or invalid identity, result or hash."
    }
    [pscustomobject]@{
        OperationId        = $id
        FiscalYear         = $fields.FiscalYear
        VerificationNumber = $number
        SkipResultEntry    = -not $fields.ContainsKey('ResultAmount')
        ResultAmount       = $amount
        ResultAccount      = $fields.ResultAccount
        EquityAccount      = $fields.EquityAccount
        VerificationHash   = $fields.VerificationHash
    }
}

function Save-LedgerYearClosing {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    $lines = @(
        '; PSLedger fiscal year closing'
        "FormatVersion:`t1"
        "OperationId:`t$($Operation.OperationId)"
        "FiscalYear:`t$($Operation.FiscalYear)"
        "ResultVerification:`t$($Operation.VerificationNumber)"
    )
    if (-not $Operation.SkipResultEntry) {
        $lines += "ResultAmount:`t$(([decimal]$Operation.ResultAmount).ToString([Globalization.CultureInfo]::InvariantCulture))"
    }
    if ($Operation.VerificationNumber -gt 0) {
        $lines += "ResultAccount:`t$($Operation.ResultAccount)"
        $lines += "EquityAccount:`t$($Operation.EquityAccount)"
        $lines += "VerificationHash:`t$($Operation.VerificationHash)"
    }
    Set-LedgerFileContent -Path $Path -NoClobber -Value $lines
}

function Get-LedgerYearClosingEntry {
    # The result verification parameters derived from a closing plan.
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [psobject]$Operation,
        [Parameter(Mandatory)] [datetime]$Date
    )
    @{
        JournalPath = $JournalPath; FiscalYear = $Operation.FiscalYear; Date = $Date
        Description = 'Årets resultat (bokslut)'; OperationId = $Operation.OperationId
        Rows = @(
            @{ Account = $Operation.ResultAccount; Amount = -$Operation.ResultAmount }
            @{ Account = $Operation.EquityAccount; Amount = $Operation.ResultAmount }
        )
    }
}
