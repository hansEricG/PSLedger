# Read/write helpers for a fiscal year's opening balance (ingående balans).
#
# The opening balance is stored as metadata in a plain-text file 'ib.txt' in the
# fiscal year directory — NOT as a verification. Each line is a tab-separated
# pair of account number and signed amount (debit positive, credit negative),
# matching the SIE #IB sign convention:
#
#     1910<TAB>15000.00
#     2081<TAB>-15000.00
#
# The absence of ib.txt means the fiscal year has no opening balance.

function Get-LedgerOpeningBalancePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$YearDir
    )
    Join-Path $YearDir 'ib.txt'
}

function Read-LedgerOpeningBalance {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$YearDir
    )

    $ibFile = Get-LedgerOpeningBalancePath -YearDir $YearDir
    if (-not (Test-Path $ibFile -PathType Leaf)) {
        return @()
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $lineNo = 0
    foreach ($Line in (Get-Content $ibFile)) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($Line)) { continue }
        if ($Line -match '^(\d+)\t(.+)$') {
            $amount = $null
            try {
                $amount = [decimal]$Matches[2]
            }
            catch {
                Write-Warning "Skipping opening balance row with an unparseable amount in '$ibFile' (line ${lineNo}): '$Line'"
            }
            if ($null -ne $amount) {
                $rows.Add([PSCustomObject]@{
                    Account = $Matches[1]
                    Amount  = $amount
                }) | Out-Null
            }
        }
        else {
            Write-Warning "Skipping malformed opening balance row in '$ibFile' (line ${lineNo}): '$Line'. Expected '<account><TAB><amount>'."
        }
    }
    , $rows.ToArray()
}

function Write-LedgerOpeningBalance {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$YearDir,

        # Rows with Account and Amount properties/keys. Rows with a zero amount
        # are omitted so ib.txt only records non-zero opening balances.
        [Parameter(Mandatory)]
        [AllowNull()]
        $Rows
    )

    $ibFile = Get-LedgerOpeningBalancePath -YearDir $YearDir

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($row in $Rows) {
        if ($null -eq $row) { continue }
        $account = $row.Account
        $amount = [decimal]$row.Amount
        if ([Math]::Round($amount, 2) -eq 0) { continue }
        $lines.Add("$account`t$amount") | Out-Null
    }

    Set-LedgerFileContent -Path $ibFile -Value $lines
}
