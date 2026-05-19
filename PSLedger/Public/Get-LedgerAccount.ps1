function Get-LedgerAccount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [string]$AccountNumber
    )

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $KontoplanFile = Join-Path $JournalPath 'kontoplan.txt'
    if (-not (Test-Path $KontoplanFile)) {
        return
    }

    $Lines = Get-Content $KontoplanFile

    $Accounts = foreach ($Line in $Lines) {
        if ($Line -match '^(\d+)\t(.+)$') {
            [PSCustomObject]@{
                AccountNumber = $Matches[1]
                AccountName   = $Matches[2]
            }
        }
    }

    if ($AccountNumber) {
        $Accounts | Where-Object { $_.AccountNumber -eq $AccountNumber }
    }
    else {
        $Accounts
    }
}
