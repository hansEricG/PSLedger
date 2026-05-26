<#
.SYNOPSIS
Creates a new verification (journal entry) in a fiscal year.

.DESCRIPTION
Creates a sequentially numbered verification file (ver0001.txt, ver0002.txt, etc.)
in the specified fiscal year directory. Enforces double-entry bookkeeping by
requiring that the sum of all row amounts equals zero.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12'). Must match an existing
fiscal year directory.

.PARAMETER Date
The date of the transaction.

.PARAMETER Description
A description of the transaction.

.PARAMETER Rows
An array of hashtables, each with 'Account' (account number) and 'Amount'
(positive for debit, negative for credit). The sum of all amounts must be zero.

.EXAMPLE
$rows = @(
    @{ Account = '1910'; Amount = 5000 }
    @{ Account = '3010'; Amount = -5000 }
)
Add-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Date '2024-03-15' -Description 'Kontantförsäljning' -Rows $rows

Records a cash sale: debit 1910 (Kassa), credit 3010 (Försäljning).

.EXAMPLE
$rows = @(
    @{ Account = '5010'; Amount = 8000 }
    @{ Account = '2440'; Amount = -6400 }
    @{ Account = '2640'; Amount = -1600 }
)
Add-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Date '2024-03-20' -Description 'Hyra kontor' -Rows $rows

Records an office rent invoice with VAT split across multiple accounts.
#>
function Add-LedgerEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [datetime]$Date,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [hashtable[]]$Rows
    )

    $YearDir = Join-Path $JournalPath $FiscalYear
    if (-not (Test-Path $YearDir -PathType Container)) {
        throw "Fiscal year not found: $FiscalYear"
    }

    # Validate balance
    $Sum = ($Rows | ForEach-Object { $_.Amount }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    if ($Sum -ne 0) {
        throw "Entry does not balance. Sum of rows: $Sum (must be 0)."
    }

    # Validate accounts against chart of accounts (if it exists)
    $KontoplanFile = Join-Path $JournalPath 'accounts.txt'
    if (Test-Path $KontoplanFile) {
        $ValidAccounts = @{}
        foreach ($Line in (Get-Content $KontoplanFile)) {
            if ($Line -match '^(\d+)\t') {
                $ValidAccounts[$Matches[1]] = $true
            }
        }

        foreach ($Row in $Rows) {
            if (-not $ValidAccounts.ContainsKey($Row.Account)) {
                throw "Account $($Row.Account) does not exist in chart of accounts."
            }
        }
    }

    # Determine next verification number by scanning existing files
    $ExistingFiles = Get-ChildItem -Path $YearDir -Filter 'ver*.txt' -File -ErrorAction SilentlyContinue
    if ($ExistingFiles) {
        $MaxNum = $ExistingFiles |
            ForEach-Object { if ($_.BaseName -match '^ver(\d+)$') { [int]$Matches[1] } } |
            Measure-Object -Maximum |
            Select-Object -ExpandProperty Maximum
        $NextNum = $MaxNum + 1
    }
    else {
        $NextNum = 1
    }

    $FileName = 'ver' + $NextNum.ToString('0000') + '.txt'
    $FilePath = Join-Path $YearDir $FileName

    # Build file content
    $Lines = @(
        "Date: $($Date.ToString('yyyy-MM-dd'))"
        "Description: $Description"
        ""
    )

    foreach ($Row in $Rows) {
        $Lines += "$($Row.Account)`t$($Row.Amount)"
    }

    $Lines | Set-Content -Path $FilePath -Encoding UTF8
}
