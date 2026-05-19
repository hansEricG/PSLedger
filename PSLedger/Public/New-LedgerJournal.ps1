function New-LedgerJournal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path $Path) {
        throw "Journal file already exists: $Path"
    }

    $Header = @(
        '; PSLedger Journal'
        "; Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ''
    )

    $Header | Set-Content -Path $Path -Encoding UTF8
}
