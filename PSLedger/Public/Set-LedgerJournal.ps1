<#
.SYNOPSIS
Updates company information in an existing PSLedger journal.

.DESCRIPTION
Updates the Name, OrgNumber and/or arbitrary metadata fields in a journal's
journal.txt file after the journal has been created. Only the fields you supply
are changed; comments and other metadata (such as the SchemaVersion) are
preserved.

If a supplied field is missing from journal.txt it is added; if it already
exists it is replaced in place. Passing an empty string for -OrgNumber, or an
empty/`$null` value for a -Metadata key, removes that field from the journal.

Supports -WhatIf and -Confirm.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Name
The new company or organisation name.

.PARAMETER OrgNumber
The new organisation number (e.g. '556677-8899'). Pass an empty string to
remove the organisation number.

.PARAMETER CompanyType
The company form. One of AB (aktiebolag), EF (enskild firma), HB (handelsbolag)
or KB (kommanditbolag). Pass an empty string to remove the company type.

.PARAMETER Metadata
A hashtable of additional free-form company fields to set, such as
@{ VatNumber = 'SE556677889901'; Email = 'info@firma.se' }. Keys must be simple
identifiers; the reserved keys Name, OrgNumber, SchemaVersion and CompanyType are
not allowed (use the dedicated parameters instead). Set a key's value to an empty
string or `$null` to remove that field.

.EXAMPLE
Set-LedgerJournal -JournalPath .\MinFirma.ledger -Name 'MinFirma Bokföring AB'

Renames the company.

.EXAMPLE
Set-LedgerJournal -JournalPath .\MinFirma.ledger -CompanyType AB

Sets the company form on a journal that was created without one.

.EXAMPLE
Set-LedgerJournal -JournalPath C:\Bokföring\Konsult.ledger -Metadata @{ VatNumber = 'SE556677889901'; Email = 'info@konsult.se' }

Adds a VAT number and contact email to the journal without touching other fields.
#>
function Set-LedgerJournal {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$OrgNumber,

        [Parameter()]
        [string]$CompanyType,

        [Parameter()]
        [hashtable]$Metadata
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

        if (-not (Test-Path $JournalPath -PathType Container)) {
            throw "Journal not found: $JournalPath"
        }

        $JournalFile = Join-Path $JournalPath 'journal.txt'
        if (-not (Test-Path $JournalFile)) {
            throw "Invalid journal - journal.txt not found in: $JournalPath"
        }

        $UpdateName = $PSBoundParameters.ContainsKey('Name')
        $UpdateOrg = $PSBoundParameters.ContainsKey('OrgNumber')
        $UpdateCompanyType = $PSBoundParameters.ContainsKey('CompanyType')

        # Collect every field to change into a single ordered map (key -> value).
        # An empty/$null value means "remove this field". Reserved keys keep their
        # dedicated parameters; -Metadata handles everything else.
        $Updates = [ordered]@{}

        if ($UpdateName) {
            $Updates['Name'] = $Name
        }
        if ($UpdateOrg) {
            $Updates['OrgNumber'] = $OrgNumber
        }
        if ($UpdateCompanyType) {
            if (-not [string]::IsNullOrEmpty($CompanyType)) {
                Test-LedgerCompanyType -CompanyType $CompanyType
            }
            $Updates['CompanyType'] = $CompanyType
        }
        if ($PSBoundParameters.ContainsKey('Metadata')) {
            foreach ($Key in $Metadata.Keys) {
                Test-LedgerMetadataKey -Key ([string]$Key)
                $Updates[[string]$Key] = Format-LedgerMetadataValue -Value ([string]$Metadata[$Key])
            }
        }

        if ($Updates.Count -eq 0) {
            throw "Nothing to update. Specify -Name, -OrgNumber, -CompanyType and/or -Metadata."
        }

        $Lines = @(Get-Content $JournalFile)
        $NewLines = [System.Collections.Generic.List[string]]::new()
        $Written = @{}

        foreach ($Line in $Lines) {
            $Matched = $false
            foreach ($Key in $Updates.Keys) {
                if ($Line -match "^$([regex]::Escape($Key)):\s*") {
                    $Matched = $true
                    $Written[$Key] = $true
                    $Value = $Updates[$Key]
                    if (-not [string]::IsNullOrEmpty($Value)) {
                        $NewLines.Add("${Key}: $Value")
                    }
                    break
                }
            }
            if (-not $Matched) {
                $NewLines.Add($Line)
            }
        }

        # Append any fields that weren't already present (skip removals).
        foreach ($Key in $Updates.Keys) {
            if (-not $Written.ContainsKey($Key)) {
                $Value = $Updates[$Key]
                if (-not [string]::IsNullOrEmpty($Value)) {
                    $NewLines.Add("${Key}: $Value")
                }
            }
        }

        if ($PSCmdlet.ShouldProcess($JournalPath, "Update journal metadata")) {
            $NewLines | Set-Content -Path $JournalFile -Encoding UTF8
        }
    }
}
