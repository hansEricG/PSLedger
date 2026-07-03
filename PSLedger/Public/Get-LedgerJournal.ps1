<#
.SYNOPSIS
Reads journal information from an existing PSLedger journal.

.DESCRIPTION
Reads the journal.txt file from the specified journal directory and returns
a PSCustomObject with the company information (Path, Name, OrgNumber, CompanyType,
SchemaVersion). Any additional free-form fields are exposed as an ordered
dictionary on the Metadata property (e.g. $journal.Metadata.VatNumber).

To read metadata for the current session journal (set via
Set-LedgerCurrentJournal) without specifying a path, use Get-LedgerCurrentJournal.

.PARAMETER Path
The path to an existing journal directory.

.EXAMPLE
Get-LedgerJournal -Path .\MinFirma.ledger

Returns an object with Name, OrgNumber, and Path properties.

.EXAMPLE
$journal = Get-LedgerJournal -Path .\MinFirma.ledger
Write-Output "Company: $($journal.Name) ($($journal.OrgNumber))"

Captures the journal metadata into a variable.
#>
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
        Path          = $Path
        Name          = $null
        OrgNumber     = $null
        CompanyType   = $null
        SchemaVersion = 1
        Metadata      = [ordered]@{}
    }

    foreach ($Line in $Content) {
        if ($Line -match '^Name:\s*(.+)$') {
            $Journal.Name = $Matches[1]
        }
        elseif ($Line -match '^OrgNumber:\s*(.+)$') {
            $Journal.OrgNumber = $Matches[1]
        }
        elseif ($Line -match '^CompanyType:\s*(.+)$') {
            $Journal.CompanyType = $Matches[1]
        }
        elseif ($Line -match '^SchemaVersion:\s*(\d+)\s*$') {
            $Journal.SchemaVersion = [int]$Matches[1]
        }
        elseif ($Line -match '^([A-Za-z][A-Za-z0-9_]*):\s*(.*)$' -and
                $script:LedgerReservedJournalKeys -notcontains $Matches[1]) {
            $Journal.Metadata[$Matches[1]] = $Matches[2]
        }
    }

    $Journal
}
