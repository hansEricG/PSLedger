<#
.SYNOPSIS
Updates a supplier in the journal's supplier register.

.DESCRIPTION
Updates the Name, OrgNumber, Email and/or PaymentTermsDays of an existing
supplier in suppliers.txt. Only the fields you supply are changed; the others
keep their current values. The supplier must already exist.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER SupplierNumber
The number of the supplier to update.

.PARAMETER Name
The new supplier name.

.PARAMETER OrgNumber
The new organisation number. Pass an empty string to clear it.

.PARAMETER Email
The new email address. Pass an empty string to clear it.

.PARAMETER PaymentTermsDays
The new default payment terms in days.

.EXAMPLE
Set-LedgerSupplier -JournalPath .\MinFirma.ledger -SupplierNumber '100' -Email 'ny@leverantor.se'

Updates only the email address for supplier 100.

.EXAMPLE
Set-LedgerSupplier -JournalPath .\MinFirma.ledger -SupplierNumber '100' -Name 'Kontorsbolaget i Sverige AB' -PaymentTermsDays 45

Renames supplier 100 and changes the payment terms to 45 days.
#>
function Set-LedgerSupplier {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$SupplierNumber,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$OrgNumber,

        [Parameter()]
        [string]$Email,

        [Parameter()]
        [ValidateRange(0, 3650)]
        [int]$PaymentTermsDays
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    $SupplierFile = Join-Path $JournalPath 'suppliers.txt'
    if (-not (Test-Path $SupplierFile)) {
        throw "Supplier '$SupplierNumber' does not exist."
    }

    $updateName = $PSBoundParameters.ContainsKey('Name')
    $updateOrg = $PSBoundParameters.ContainsKey('OrgNumber')
    $updateEmail = $PSBoundParameters.ContainsKey('Email')
    $updateTerms = $PSBoundParameters.ContainsKey('PaymentTermsDays')

    if (-not ($updateName -or $updateOrg -or $updateEmail -or $updateTerms)) {
        throw "Nothing to update. Specify -Name, -OrgNumber, -Email and/or -PaymentTermsDays."
    }

    $lines = @(Get-Content $SupplierFile -Encoding UTF8)
    $found = $false
    $newLines = foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t"
        if ($parts[0] -eq $SupplierNumber) {
            $found = $true
            $curName = if ($parts.Count -ge 2) { $parts[1] } else { '' }
            $curOrg = if ($parts.Count -ge 3) { $parts[2] } else { '' }
            $curEmail = if ($parts.Count -ge 4) { $parts[3] } else { '' }
            $curTerms = if ($parts.Count -ge 5) { $parts[4] } else { '30' }

            if ($updateName) { $curName = $Name }
            if ($updateOrg) { $curOrg = $OrgNumber }
            if ($updateEmail) { $curEmail = $Email }
            if ($updateTerms) { $curTerms = $PaymentTermsDays }

            "$SupplierNumber`t$curName`t$curOrg`t$curEmail`t$curTerms"
        }
        else {
            $line
        }
    }

    if (-not $found) {
        throw "Supplier '$SupplierNumber' does not exist."
    }

    if ($PSCmdlet.ShouldProcess($SupplierNumber, "Update supplier")) {
        $newLines | Set-Content -Path $SupplierFile -Encoding UTF8
    }
}
