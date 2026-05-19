function Add-LedgerAccount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$AccountNumber,

        [Parameter(Mandatory)]
        [string]$AccountName
    )

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $KontoplanFile = Join-Path $JournalPath 'kontoplan.txt'

    if (Test-Path $KontoplanFile) {
        $Existing = Get-Content $KontoplanFile
        foreach ($Line in $Existing) {
            if ($Line -match "^$AccountNumber\s+") {
                throw "Account $AccountNumber already exists in chart of accounts."
            }
        }
    }

    $Entry = "$AccountNumber`t$AccountName"
    $Entry | Add-Content -Path $KontoplanFile -Encoding UTF8
}
