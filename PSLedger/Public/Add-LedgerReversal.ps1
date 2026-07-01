<#
.SYNOPSIS
Creates a reversal verification to correct a previous entry.

.DESCRIPTION
Reads an existing verification and creates a new verification with the same
rows but negated amounts. The description is auto-generated to reference the
original verification number. This follows Swedish bookkeeping law which
prohibits editing or deleting posted entries.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER VerificationNumber
The verification number to reverse.

.PARAMETER Date
The date for the reversal entry. Defaults to today if not specified.

.EXAMPLE
Add-LedgerReversal -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -VerificationNumber 3

Creates a new verification that reverses entry #3 with today's date.

.EXAMPLE
Add-LedgerReversal -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -VerificationNumber 5 -Date '2024-06-30'

Creates a reversal of entry #5 dated 2024-06-30.
#>
function Add-LedgerReversal {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [int]$VerificationNumber,

        [datetime]$Date = (Get-Date)
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        # Get the original entry
        $Original = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -VerificationNumber $VerificationNumber
        if (-not $Original) {
            throw "Verification $VerificationNumber not found in fiscal year $FiscalYear."
        }

        # Build reversed rows
        $ReversedRows = $Original.Rows | ForEach-Object {
            @{ Account = $_.Account; Amount = -$_.Amount }
        }

        $Description = "Rättelse ver $VerificationNumber - $($Original.Description)"

        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date $Date -Description $Description -Rows $ReversedRows
    }
}

