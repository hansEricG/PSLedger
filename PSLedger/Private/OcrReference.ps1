# Helpers for Swedish OCR payment references (betalningsreferens). An OCR
# reference is the base number (typically the invoice number) followed by an
# optional length-control digit and a trailing modulus-10 (Luhn) check digit, so
# the receiving bank can validate the reference automatically.

function Get-LedgerLuhnCheckDigit {
    <#
    .SYNOPSIS
    Returns the modulus-10 (Luhn) check digit for a string of digits.

    .DESCRIPTION
    Doubles every second digit counting from the right of the supplied body (the
    rightmost body digit is doubled), subtracts 9 from any product greater than 9,
    sums the results and returns the digit that makes the total a multiple of ten.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Digits
    )
    $sum = 0
    $double = $true
    for ($i = $Digits.Length - 1; $i -ge 0; $i--) {
        $d = [int][string]$Digits[$i]
        if ($double) {
            $d *= 2
            if ($d -gt 9) { $d -= 9 }
        }
        $sum += $d
        $double = -not $double
    }
    return (10 - ($sum % 10)) % 10
}

function Get-LedgerOcrReference {
    <#
    .SYNOPSIS
    Builds a Swedish OCR payment reference for a base number.

    .DESCRIPTION
    Produces an OCR reference consisting of the base number's digits, an optional
    length-control digit and a trailing Luhn check digit. With length control
    (the default) the length digit is the total length of the finished reference
    (including the length and check digits) modulo ten, which lets the bank verify
    both the length and the checksum.

    .PARAMETER BaseNumber
    The base number, typically an invoice number. Non-digit characters are ignored.

    .PARAMETER NoLengthControl
    Omit the length-control digit and append only the Luhn check digit.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$BaseNumber,

        [Parameter()]
        [switch]$NoLengthControl
    )
    $digits = $BaseNumber -replace '\D', ''
    if ([string]::IsNullOrEmpty($digits)) {
        throw "BaseNumber must contain at least one digit."
    }

    $body = $digits
    if (-not $NoLengthControl) {
        $completeLength = $digits.Length + 2
        $lengthDigit = $completeLength % 10
        $body = $digits + [string]$lengthDigit
    }

    $check = Get-LedgerLuhnCheckDigit -Digits $body
    return $body + [string]$check
}
