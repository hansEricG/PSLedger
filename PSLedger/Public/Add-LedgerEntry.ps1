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
