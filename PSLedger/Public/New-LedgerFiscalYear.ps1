function New-LedgerFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [Parameter(Mandatory)]
        [datetime]$EndDate
    )

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    if ($EndDate -le $StartDate) {
        throw "EndDate must be after StartDate."
    }

    $DirName = '{0:yyyy-MM}_{1:yyyy-MM}' -f $StartDate, $EndDate
    $YearDir = Join-Path $JournalPath $DirName

    if (Test-Path $YearDir) {
        throw "Fiscal year already exists: $DirName"
    }

    New-Item -ItemType Directory -Path $YearDir -Force | Out-Null

    $Lines = @(
        "StartDate: $($StartDate.ToString('yyyy-MM-dd'))"
        "EndDate: $($EndDate.ToString('yyyy-MM-dd'))"
        "Status: Open"
    )

    $YearFile = Join-Path $YearDir 'year.txt'
    $Lines | Set-Content -Path $YearFile -Encoding UTF8
}
