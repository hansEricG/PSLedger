# Recoverable SIE import. An immutable plan in <year>/import.txt binds the import
# to its source file, reserves the verification numbers and records hashes of the
# planned opening balance and verifications, so an interrupted Import-LedgerSie
# can be completed by repeating it with the same file.

function Get-LedgerSieImportPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [string]$FiscalYear
    )
    Join-Path $JournalPath $FiscalYear 'import.txt'
}

function Read-LedgerSieImport {
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$Path)
    $fields = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';')) { continue }
        if ($line -notmatch '^([A-Za-z]+):\t(.+)$' -or $fields.ContainsKey($Matches[1])) {
            throw "Invalid SIE import record '$Path': malformed or duplicate field."
        }
        $fields[$Matches[1]] = $Matches[2]
    }
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $id = [guid]::Empty
    $first = 0
    $count = -1
    $hash = '^[0-9a-f]{64}$'
    $valid = $fields.FormatVersion -eq '1' -and
        [guid]::TryParseExact([string]$fields.OperationId, 'D', [ref]$id) -and $id -ne [guid]::Empty -and
        $fields.FiscalYear -eq (Split-Path (Split-Path $Path -Parent) -Leaf) -and
        [string]$fields.SourceHash -cmatch $hash -and [string]$fields.VerificationsHash -cmatch $hash -and
        [int]::TryParse([string]$fields.FirstVerification, [Globalization.NumberStyles]::None, $invariant, [ref]$first) -and $first -gt 0 -and
        [int]::TryParse([string]$fields.VerificationCount, [Globalization.NumberStyles]::None, $invariant, [ref]$count) -and
        (-not $fields.ContainsKey('OpeningBalanceHash') -or $fields.OpeningBalanceHash -cmatch $hash) -and
        (-not $fields.ContainsKey('PriorOpeningBalanceHash') -or
            ($fields.ContainsKey('OpeningBalanceHash') -and $fields.PriorOpeningBalanceHash -cmatch $hash))
    if (-not $valid) {
        throw "Invalid SIE import record '$Path': missing or invalid identity, numbers or hashes."
    }
    [pscustomobject]@{
        OperationId             = $id
        FiscalYear              = $fields.FiscalYear
        SourceHash              = $fields.SourceHash
        FirstVerification       = $first
        VerificationCount       = $count
        VerificationsHash       = $fields.VerificationsHash
        OpeningBalanceHash      = $fields.OpeningBalanceHash
        PriorOpeningBalanceHash = $fields.PriorOpeningBalanceHash
    }
}

function Save-LedgerSieImport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [psobject]$Operation
    )
    $lines = @(
        '; PSLedger SIE import'
        "FormatVersion:`t1"
        "OperationId:`t$($Operation.OperationId)"
        "FiscalYear:`t$($Operation.FiscalYear)"
        "SourceHash:`t$($Operation.SourceHash)"
        "FirstVerification:`t$($Operation.FirstVerification)"
        "VerificationCount:`t$($Operation.VerificationCount)"
        "VerificationsHash:`t$($Operation.VerificationsHash)"
    )
    if ($Operation.OpeningBalanceHash) { $lines += "OpeningBalanceHash:`t$($Operation.OpeningBalanceHash)" }
    if ($Operation.PriorOpeningBalanceHash) { $lines += "PriorOpeningBalanceHash:`t$($Operation.PriorOpeningBalanceHash)" }
    Set-LedgerFileContent -Path $Path -NoClobber -Value $lines
}

function Get-LedgerTextLinesHash {
    # SHA-256 of lines as written to a file (LF-normalised), matching Get-LedgerContentHash.
    [CmdletBinding()]
    [OutputType([string])]
    param ([Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$Lines)
    Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($Lines -join "`n") + "`n"))
}