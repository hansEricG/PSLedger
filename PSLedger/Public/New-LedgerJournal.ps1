function New-LedgerJournal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [string]$OrgNumber
    )

    if (Test-Path $Path) {
        throw "Journal already exists: $Path"
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    $Lines = @(
        "; PSLedger Journal"
        "; Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ""
        "Name: $Name"
    )

    if ($OrgNumber) {
        $Lines += "OrgNumber: $OrgNumber"
    }

    $JournalFile = Join-Path $Path 'journal.txt'
    $Lines | Set-Content -Path $JournalFile -Encoding UTF8
}
