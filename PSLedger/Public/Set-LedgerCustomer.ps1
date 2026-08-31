<#
.SYNOPSIS
Updates a customer in the journal's customer register.

.DESCRIPTION
Updates the Name, OrgNumber, Email and/or PaymentTermsDays of an existing
customer in customers.txt. Only the fields you supply are changed; the others
keep their current values. The customer must already exist.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER CustomerNumber
The number of the customer to update.

.PARAMETER Name
The new customer name.

.PARAMETER OrgNumber
The new organisation number. Pass an empty string to clear it.

.PARAMETER Email
The new email address. Pass an empty string to clear it.

.PARAMETER PaymentTermsDays
The new default payment terms in days.

.EXAMPLE
Set-LedgerCustomer -JournalPath .\MinFirma.ledger -CustomerNumber '10' -Email 'ny@volvo.se'

Updates only the email address for customer 10.

.EXAMPLE
Set-LedgerCustomer -JournalPath .\MinFirma.ledger -CustomerNumber '10' -Name 'Volvo Group AB' -PaymentTermsDays 45

Renames customer 10 and changes the payment terms to 45 days.
#>
function Set-LedgerCustomer {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$CustomerNumber,

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

    $CustomerFile = Join-Path $JournalPath 'customers.txt'
    if (-not (Test-Path $CustomerFile)) {
        throw "Customer '$CustomerNumber' does not exist."
    }

    $updateName = $PSBoundParameters.ContainsKey('Name')
    $updateOrg = $PSBoundParameters.ContainsKey('OrgNumber')
    $updateEmail = $PSBoundParameters.ContainsKey('Email')
    $updateTerms = $PSBoundParameters.ContainsKey('PaymentTermsDays')

    if (-not ($updateName -or $updateOrg -or $updateEmail -or $updateTerms)) {
        throw "Nothing to update. Specify -Name, -OrgNumber, -Email and/or -PaymentTermsDays."
    }

    $lines = @(Get-Content $CustomerFile -Encoding UTF8)
    $found = $false
    $newLines = foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t"
        if ($parts[0] -eq $CustomerNumber) {
            $found = $true
            $curName = if ($parts.Count -ge 2) { $parts[1] } else { '' }
            $curOrg = if ($parts.Count -ge 3) { $parts[2] } else { '' }
            $curEmail = if ($parts.Count -ge 4) { $parts[3] } else { '' }
            $curTerms = if ($parts.Count -ge 5) { $parts[4] } else { '30' }

            if ($updateName) { $curName = $Name }
            if ($updateOrg) { $curOrg = $OrgNumber }
            if ($updateEmail) { $curEmail = $Email }
            if ($updateTerms) { $curTerms = $PaymentTermsDays }

            "$CustomerNumber`t$curName`t$curOrg`t$curEmail`t$curTerms"
        }
        else {
            $line
        }
    }

    if (-not $found) {
        throw "Customer '$CustomerNumber' does not exist."
    }

    if ($PSCmdlet.ShouldProcess($CustomerNumber, "Update customer")) {
        $newLines | Set-Content -Path $CustomerFile -Encoding UTF8
    }
}
