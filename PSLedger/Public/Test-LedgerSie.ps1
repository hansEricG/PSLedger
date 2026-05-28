<#
.SYNOPSIS
Validates a SIE file without importing it.

.DESCRIPTION
Parses a SIE 4 (or compatible) file and runs structural checks: every #VER
block must balance to zero, every #TRANS must reference a #KONTO declared in
the same file, and verification numbers within a series must be unique.
Returns a result object with IsValid, Errors, Warnings and Summary properties.

.PARAMETER Path
Path to the SIE file to validate.

.EXAMPLE
Test-LedgerSie -Path .\export.se

Returns a result object. Use the IsValid property to check the outcome.

.EXAMPLE
$result = Test-LedgerSie -Path .\fromfortnox.se
if (-not $result.IsValid) { $result.Errors | ForEach-Object { Write-Warning $_ } }

Inspect errors before deciding whether to import.
#>
function Test-LedgerSie {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    $text = Read-SieText -Path $Path
    $records = ConvertFrom-SieText -Text $text

    $accounts = @{}
    $verKeys = @{}
    $verCount = 0
    $transCount = 0
    $sieType = $null

    foreach ($rec in $records) {
        switch ($rec.Tag) {
            'SIETYP' {
                if ($rec.Fields.Count -ge 1) { $sieType = $rec.Fields[0] }
            }
            'KONTO' {
                if ($rec.Fields.Count -lt 1) {
                    $errors.Add("#KONTO record missing account number")
                    continue
                }
                $accounts[$rec.Fields[0]] = if ($rec.Fields.Count -ge 2) { $rec.Fields[1] } else { '' }
            }
            'VER' {
                $verCount++
                if ($rec.Fields.Count -lt 3) {
                    $errors.Add("#VER record has too few fields: $($rec.Fields -join ' ')")
                    continue
                }
                $series = $rec.Fields[0]
                $verNo = $rec.Fields[1]
                $key = "$series/$verNo"
                if ($verKeys.ContainsKey($key)) {
                    $errors.Add("Duplicate verification: #VER $series $verNo")
                }
                $verKeys[$key] = $true

                $sum = [decimal]0
                foreach ($t in $rec.Transactions) {
                    $transCount++
                    if ($t.Fields.Count -lt 2) {
                        $errors.Add("#TRANS in VER $series $verNo has too few fields")
                        continue
                    }
                    $acct = $t.Fields[0]
                    if (-not $accounts.ContainsKey($acct)) {
                        $errors.Add("#TRANS in VER $series $verNo references unknown account: $acct")
                    }
                    $amountText = $t.Fields[1] -replace ',', '.'
                    $amount = [decimal]0
                    if (-not [decimal]::TryParse($amountText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$amount)) {
                        $errors.Add("#TRANS in VER $series $verNo has invalid amount: $($t.Fields[1])")
                        continue
                    }
                    $sum += $amount
                }
                if ($sum -ne 0) {
                    $errors.Add("#VER $series $verNo does not balance. Sum: $sum")
                }
            }
        }
    }

    if (-not $sieType) {
        $warnings.Add("Missing #SIETYP record")
    }
    elseif ($sieType -ne '4') {
        $warnings.Add("SIE type is $sieType; PSLedger is optimised for type 4")
    }

    [PSCustomObject]@{
        Path        = $Path
        IsValid     = ($errors.Count -eq 0)
        SieType     = $sieType
        Accounts    = $accounts.Count
        Verifications = $verCount
        Transactions = $transCount
        Errors      = $errors.ToArray()
        Warnings    = $warnings.ToArray()
    }
}
