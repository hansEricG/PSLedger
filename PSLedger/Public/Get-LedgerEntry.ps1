function Get-LedgerEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [int]$VerificationNumber
    )

    $YearDir = Join-Path $JournalPath $FiscalYear
    if (-not (Test-Path $YearDir -PathType Container)) {
        throw "Fiscal year not found: $FiscalYear"
    }

    $Pattern = if ($VerificationNumber) {
        'ver' + $VerificationNumber.ToString('0000') + '.txt'
    }
    else {
        'ver*.txt'
    }

    $Files = Get-ChildItem -Path $YearDir -Filter $Pattern -File -ErrorAction SilentlyContinue | Sort-Object Name
    if (-not $Files) {
        return
    }

    $Entries = foreach ($File in $Files) {
        $VerNum = if ($File.BaseName -match '^ver(\d+)$') { [int]$Matches[1] }

        $Lines = Get-Content $File.FullName
        $EntryDate = $null
        $EntryDesc = $null
        $EntryRows = @()

        foreach ($Line in $Lines) {
            if ($Line -match '^Date:\s*(.+)$') {
                $EntryDate = $Matches[1]
            }
            elseif ($Line -match '^Description:\s*(.+)$') {
                $EntryDesc = $Matches[1]
            }
            elseif ($Line -match '^(\d+)\t(.+)$') {
                $EntryRows += [PSCustomObject]@{
                    Account = $Matches[1]
                    Amount  = [decimal]$Matches[2]
                }
            }
        }

        [PSCustomObject]@{
            VerificationNumber = $VerNum
            Date               = $EntryDate
            Description        = $EntryDesc
            Rows               = $EntryRows
        }
    }

    $Entries
}
