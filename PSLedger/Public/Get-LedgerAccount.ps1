<#
.SYNOPSIS
Retrieves accounts from the journal's chart of accounts.

.DESCRIPTION
Reads accounts.txt and returns PSCustomObjects with AccountNumber and
AccountName properties. Can optionally filter by a specific account number.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER AccountNumber
Optional. If specified, returns only the account with that number.

.EXAMPLE
Get-LedgerAccount -JournalPath .\MinFirma.ledger

Returns all accounts in the chart.

.EXAMPLE
Get-LedgerAccount -JournalPath .\MinFirma.ledger -AccountNumber '1910'

Returns only the account with number 1910.

.EXAMPLE
Get-LedgerAccount -JournalPath .\MinFirma.ledger | Where-Object { $_.AccountNumber -like '3*' }

Returns all income accounts (3xxx in BAS).
#>
function Get-LedgerAccount {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [string]$AccountNumber
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $KontoplanFile = Join-Path $JournalPath 'accounts.txt'
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
