<#
.SYNOPSIS
Copies closing balances as opening balances into a new fiscal year.

.DESCRIPTION
Reads the trial balance from a source fiscal year, takes all balance-sheet
accounts (1xxx assets and 2xxx equity/liabilities), and creates an opening
verification (ver0001.txt) in the target fiscal year. The entry is dated on
the target year's start date with the description 'Ingående balans'.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FromFiscalYear
The source fiscal year to read closing balances from.

.PARAMETER ToFiscalYear
The target fiscal year where the opening balance entry will be created.

.EXAMPLE
Copy-LedgerOpeningBalance -JournalPath .\MinFirma.ledger -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12'

Creates an opening balance verification in the 2025 fiscal year based on
2024's closing balances.

.EXAMPLE
Close-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'
New-LedgerFiscalYear -JournalPath .\MinFirma.ledger -StartDate '2025-01-01' -EndDate '2025-12-31'
Copy-LedgerOpeningBalance -JournalPath .\MinFirma.ledger -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12'

Typical year-end workflow: close old year, create new, copy balances.
#>
function Copy-LedgerOpeningBalance {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FromFiscalYear,

        [Parameter(Mandatory)]
        [string]$ToFiscalYear
    )

    # Validate source fiscal year
    $FromDir = Join-Path $JournalPath $FromFiscalYear
    if (-not (Test-Path $FromDir -PathType Container)) {
        throw "Source fiscal year not found: $FromFiscalYear"
    }

    # Validate target fiscal year
    $ToDir = Join-Path $JournalPath $ToFiscalYear
    if (-not (Test-Path $ToDir -PathType Container)) {
        throw "Target fiscal year not found: $ToFiscalYear"
    }

    # Check target has no entries
    $ExistingFiles = Get-ChildItem -Path $ToDir -Filter 'ver*.txt' -File -ErrorAction SilentlyContinue
    if ($ExistingFiles) {
        throw "Target fiscal year $ToFiscalYear already has verifications. Cannot create opening balance."
    }

    # Get balance accounts from source year
    $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FromFiscalYear
    if (-not $Balance) {
        throw "No entries found in source fiscal year $FromFiscalYear."
    }

    # Filter to balance sheet accounts (1xxx and 2xxx)
    $BalanceAccounts = $Balance | Where-Object { $_.AccountNumber -match '^[12]' -and $_.Balance -ne 0 }

    # Calculate year's result from P&L accounts (3xxx-8xxx) and add to 2099
    $PLAccounts = $Balance | Where-Object { $_.AccountNumber -match '^[3-8]' }
    $YearResult = if ($PLAccounts) { ($PLAccounts | Measure-Object -Property Balance -Sum).Sum } else { [decimal]0 }

    if (-not $BalanceAccounts -and $YearResult -eq 0) {
        throw "No balance sheet accounts with non-zero balances in $FromFiscalYear."
    }

    # Merge year's result into account 2099
    if ($YearResult -ne 0) {
        $Existing2099 = $BalanceAccounts | Where-Object { $_.AccountNumber -eq '2099' }
        if ($Existing2099) {
            $BalanceAccounts = $BalanceAccounts | Where-Object { $_.AccountNumber -ne '2099' }
            $YearResult += $Existing2099.Balance
        }
        $BalanceAccounts = @($BalanceAccounts) + @([PSCustomObject]@{
            AccountNumber = '2099'
            AccountName   = 'Årets resultat'
            Debit         = [decimal]0
            Credit        = [decimal]0
            Balance       = $YearResult
        })
    }

    if (-not $BalanceAccounts) {
        throw "No balance sheet accounts with non-zero balances in $FromFiscalYear."
    }

    # Get target year start date
    $YearFile = Join-Path $ToDir 'year.txt'
    $StartDate = $null
    if (Test-Path $YearFile) {
        foreach ($Line in (Get-Content $YearFile)) {
            if ($Line -match '^StartDate:\s*(.+)$') {
                $StartDate = $Matches[1]
                break
            }
        }
    }
    if (-not $StartDate) {
        throw "Cannot determine start date for target fiscal year $ToFiscalYear."
    }

    # Build verification content
    $Lines = @(
        "Date: $StartDate"
        "Description: Ingående balans"
        ""
    )

    foreach ($Acc in $BalanceAccounts) {
        $Lines += "$($Acc.AccountNumber)`t$($Acc.Balance)"
    }

    $FilePath = Join-Path $ToDir 'ver0001.txt'
    $Lines | Set-Content -Path $FilePath -Encoding UTF8
}
