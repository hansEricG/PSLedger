<#
.SYNOPSIS
Retrieves verifications (journal entries) from a fiscal year.

.DESCRIPTION
Reads verification files from the specified fiscal year and returns
PSCustomObjects with VerificationNumber, Date, Description, and Rows
(each row having Account and Amount properties). Supports filtering by
verification number, account, and date range.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER VerificationNumber
Optional. If specified, returns only the verification with that number.

.PARAMETER Account
Optional. If specified, returns only verifications containing a row with
this account number.

.PARAMETER FromDate
Optional. If specified, returns only verifications on or after this date.

.PARAMETER ToDate
Optional. If specified, returns only verifications on or before this date.

.EXAMPLE
Get-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Returns all verifications for the fiscal year.

.EXAMPLE
Get-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Account '1910'

Returns all verifications that involve account 1910 (Kassa).

.EXAMPLE
Get-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -FromDate '2024-03-01' -ToDate '2024-03-31'

Returns all verifications from March 2024.
#>
function Get-LedgerEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [int]$VerificationNumber,

        [string]$Account,

        [datetime]$FromDate,

        [datetime]$ToDate
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

        # Apply date filters
        if ($FromDate -or $ToDate) {
            $ParsedDate = [datetime]$EntryDate
            if ($FromDate -and $ParsedDate -lt $FromDate) { continue }
            if ($ToDate -and $ParsedDate -gt $ToDate) { continue }
        }

        # Apply account filter
        if ($Account) {
            $HasAccount = $EntryRows | Where-Object { $_.Account -eq $Account }
            if (-not $HasAccount) { continue }
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
