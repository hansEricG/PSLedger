<#
.SYNOPSIS
Adds an account to the journal's chart of accounts.

.DESCRIPTION
Appends a new account entry to accounts.txt in the specified journal.
The file is created if it doesn't exist. Duplicate account numbers are
not allowed.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER AccountNumber
The account number (typically 4 digits following the BAS standard, e.g. '1910').

.PARAMETER AccountName
The descriptive name for the account (e.g. 'Kassa').

.EXAMPLE
Add-LedgerAccount -JournalPath .\MinFirma.ledger -AccountNumber '1910' -AccountName 'Kassa'

.EXAMPLE
# Add several accounts for a basic chart
Add-LedgerAccount -JournalPath .\MinFirma.ledger -AccountNumber '1910' -AccountName 'Kassa'
Add-LedgerAccount -JournalPath .\MinFirma.ledger -AccountNumber '2440' -AccountName 'Leverantörsskulder'
Add-LedgerAccount -JournalPath .\MinFirma.ledger -AccountNumber '3010' -AccountName 'Försäljning tjänster'
Add-LedgerAccount -JournalPath .\MinFirma.ledger -AccountNumber '5010' -AccountName 'Lokalhyra'
#>
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

    $KontoplanFile = Join-Path $JournalPath 'accounts.txt'

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
