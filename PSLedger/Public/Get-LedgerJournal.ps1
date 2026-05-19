function Get-LedgerJournal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path -PathType Container)) {
        throw "Journal not found: $Path"
    }

    $JournalFile = Join-Path $Path 'journal.txt'
    if (-not (Test-Path $JournalFile)) {
        throw "Invalid journal - journal.txt not found in: $Path"
    }

    $Content = Get-Content $JournalFile

    $Journal = [PSCustomObject]@{
        Path      = $Path
        Name      = $null
        OrgNumber = $null
    }

    foreach ($Line in $Content) {
        if ($Line -match '^Name:\s*(.+)$') {
            $Journal.Name = $Matches[1]
        }
        elseif ($Line -match '^OrgNumber:\s*(.+)$') {
            $Journal.OrgNumber = $Matches[1]
        }
    }

    $Journal
}
