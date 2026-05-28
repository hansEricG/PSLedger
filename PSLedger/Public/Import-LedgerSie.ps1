<#
.SYNOPSIS
Imports verifications from a SIE 4 file into a journal.

.DESCRIPTION
Reads a SIE 4 file (typically a SIE 4E export from another system or a SIE 4I
file from a supplier) and adds its verifications to the target journal. The
target fiscal year must exist and be open. The file is validated with
Test-LedgerSie first; any errors abort the import before any file is written.
Accounts referenced in the SIE file must already exist in the chart of
accounts unless -CreateMissingAccounts is specified.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12') to import into.

.PARAMETER Path
Path to the SIE file to import.

.PARAMETER CreateMissingAccounts
If specified, accounts referenced in #TRANS rows that are not yet in the
chart of accounts are added automatically using the names from the SIE file's
#KONTO records.

.EXAMPLE
Import-LedgerSie -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Path .\fromfortnox.se

Imports verifications from a SIE file into an existing fiscal year.

.EXAMPLE
Import-LedgerSie -JournalPath .\NyFirma.ledger -FiscalYear '2024-01_2024-12' -Path .\export.se -CreateMissingAccounts

Imports into a journal whose chart of accounts is incomplete, adding any
referenced accounts on the fly.
#>
function Import-LedgerSie {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$CreateMissingAccounts
    )

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $YearDir = Join-Path $JournalPath $FiscalYear
    if (-not (Test-Path $YearDir -PathType Container)) {
        throw "Fiscal year not found: $FiscalYear"
    }

    $YearFile = Join-Path $YearDir 'year.txt'
    if (Test-Path $YearFile) {
        foreach ($Line in (Get-Content $YearFile)) {
            if ($Line -match '^Status:\s*Closed') {
                throw "Fiscal year $FiscalYear is Closed. Cannot import entries."
            }
        }
    }

    $validation = Test-LedgerSie -Path $Path
    if (-not $validation.IsValid) {
        $msg = "SIE file is invalid: " + ($validation.Errors -join '; ')
        throw $msg
    }

    $text = Read-SieText -Path $Path
    $records = ConvertFrom-SieText -Text $text

    $sieAccountOrder = New-Object System.Collections.Generic.List[string]
    $sieAccounts = @{}
    foreach ($rec in $records) {
        if ($rec.Tag -eq 'KONTO' -and $rec.Fields.Count -ge 1) {
            $name = if ($rec.Fields.Count -ge 2) { $rec.Fields[1] } else { '' }
            if (-not $sieAccounts.ContainsKey($rec.Fields[0])) {
                $sieAccountOrder.Add($rec.Fields[0]) | Out-Null
            }
            $sieAccounts[$rec.Fields[0]] = $name
        }
    }

    $existing = @{}
    foreach ($a in (Get-LedgerAccount -JournalPath $JournalPath)) {
        $existing[$a.AccountNumber] = $true
    }

    $referenced = @{}
    foreach ($rec in $records) {
        if ($rec.Tag -ne 'VER') { continue }
        foreach ($t in $rec.Transactions) {
            if ($t.Fields.Count -ge 1) { $referenced[$t.Fields[0]] = $true }
        }
    }

    # Walk accounts in SIE file order so the imported chart preserves order.
    $orderedReferenced = New-Object System.Collections.Generic.List[string]
    foreach ($acct in $sieAccountOrder) {
        if ($referenced.ContainsKey($acct)) { $orderedReferenced.Add($acct) | Out-Null }
    }
    foreach ($acct in $referenced.Keys) {
        if (-not $sieAccounts.ContainsKey($acct)) { $orderedReferenced.Add($acct) | Out-Null }
    }

    foreach ($acct in $orderedReferenced) {
        if (-not $existing.ContainsKey($acct)) {
            if ($CreateMissingAccounts) {
                $name = if ($sieAccounts.ContainsKey($acct)) { $sieAccounts[$acct] } else { "Imported $acct" }
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $acct -AccountName $name
                $existing[$acct] = $true
            }
            else {
                throw "Account $acct in SIE file does not exist in chart of accounts. Use -CreateMissingAccounts to add it automatically."
            }
        }
    }

    $imported = 0
    foreach ($rec in $records) {
        if ($rec.Tag -ne 'VER') { continue }
        if ($rec.Fields.Count -lt 3) { continue }

        $verDate = $rec.Fields[2]
        $verDesc = if ($rec.Fields.Count -ge 4) { $rec.Fields[3] } else { '' }
        $date = [datetime]::ParseExact($verDate, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)

        $rows = foreach ($t in $rec.Transactions) {
            $amountText = $t.Fields[1] -replace ',', '.'
            $amount = [decimal]::Parse($amountText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture)
            @{ Account = $t.Fields[0]; Amount = $amount }
        }

        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
            -Date $date -Description $verDesc -Rows @($rows)
        $imported++
    }

    [PSCustomObject]@{
        Path             = $Path
        ImportedEntries  = $imported
        ImportedAccounts = if ($CreateMissingAccounts) { ($referenced.Keys | Where-Object { $sieAccounts.ContainsKey($_) }).Count } else { 0 }
    }
}
