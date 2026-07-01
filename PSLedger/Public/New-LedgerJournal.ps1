<#
.SYNOPSIS
Creates a new PSLedger journal.

.DESCRIPTION
Creates a new journal directory at the specified path with a journal.txt file
containing company information. The journal is the top-level container for all
bookkeeping data including chart of accounts, fiscal years, and verifications.

.PARAMETER Path
The path where the journal directory will be created. Typically ends with .ledger
(e.g. 'C:\Bookkeeping\MyCompany.ledger').

.PARAMETER Name
The company or organisation name.

.PARAMETER OrgNumber
Optional organisation number (e.g. '556677-8899').

.PARAMETER Metadata
Optional hashtable of additional free-form company fields to store, such as
@{ VatNumber = 'SE556677889901'; Email = 'info@firma.se' }. Keys must be simple
identifiers; the reserved keys Name, OrgNumber and SchemaVersion are not allowed
(use the dedicated parameters instead).

.EXAMPLE
New-LedgerJournal -Path .\MinFirma.ledger -Name 'MinFirma AB'

Creates a basic journal without an organisation number.

.EXAMPLE
New-LedgerJournal -Path C:\Bokföring\Konsult.ledger -Name 'Konsult AB' -OrgNumber '556677-8899' -Metadata @{ VatNumber = 'SE556677889901' }

Creates a journal with full company details including a VAT number.
#>
function New-LedgerJournal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [string]$OrgNumber,

        [hashtable]$Metadata
    )

    if (Test-Path $Path) {
        throw "Journal already exists: $Path"
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null

    $Lines = @(
        "; PSLedger Journal"
        "; Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ""
        "SchemaVersion: $script:CurrentSchemaVersion"
        "Name: $Name"
    )

    if ($OrgNumber) {
        $Lines += "OrgNumber: $OrgNumber"
    }

    if ($Metadata) {
        foreach ($Key in $Metadata.Keys) {
            Test-LedgerMetadataKey -Key $Key
            $Value = Format-LedgerMetadataValue -Value ([string]$Metadata[$Key])
            if (-not [string]::IsNullOrEmpty($Value)) {
                $Lines += "${Key}: $Value"
            }
        }
    }

    $JournalFile = Join-Path $Path 'journal.txt'
    $Lines | Set-Content -Path $JournalFile -Encoding UTF8
}
