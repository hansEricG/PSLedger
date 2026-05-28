<#
.SYNOPSIS
Generates a VAT report (momsrapport) for a period.

.DESCRIPTION
Reads all verifications in the specified date range and maps account totals to
Swedish VAT declaration boxes (Skatteverkets momsdeklaration). Returns objects
for each box with amount, and a summary showing VAT to pay or reclaim.

The mapping follows BAS standard accounts:
  Box 05 — Taxable domestic sales (accounts 3000–3799)
  Box 10 — Output VAT 25 % (2610–2611)
  Box 11 — Output VAT 12 % (2620–2621)
  Box 12 — Output VAT 6 % (2630–2631)
  Box 48 — Input VAT (2640–2649)
  Box 49 — VAT to pay/reclaim (sum of output minus input)

Sales amounts are reported as positive absolute values (credit accounts
negated). VAT amounts are reported as absolute values.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER FromDate
Start of the VAT reporting period (inclusive).

.PARAMETER ToDate
End of the VAT reporting period (inclusive).

.EXAMPLE
Get-LedgerVatReport -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -FromDate '2024-01-01' -ToDate '2024-03-31'

Returns VAT boxes for Q1 2024.

.EXAMPLE
Get-LedgerVatReport -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -FromDate '2024-01-01' -ToDate '2024-01-31' |
    Format-Table Box, Name, Amount

Displays January's VAT report as a formatted table.
#>
function Get-LedgerVatReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [datetime]$FromDate,

        [Parameter(Mandatory)]
        [datetime]$ToDate
    )

    $entries = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
        -FromDate $FromDate -ToDate $ToDate

    $mapping = Get-VatBoxMapping

    # Accumulate amounts per account
    $accountTotals = @{}
    if ($entries) {
        foreach ($entry in $entries) {
            foreach ($row in $entry.Rows) {
                $acct = $row.Account
                if (-not $accountTotals.ContainsKey($acct)) {
                    $accountTotals[$acct] = [decimal]0
                }
                $accountTotals[$acct] += [decimal]$row.Amount
            }
        }
    }

    # Map accounts to boxes
    $boxTotals = @{}
    foreach ($map in $mapping) {
        $box = $map.Box
        if (-not $boxTotals.ContainsKey($box)) {
            $boxTotals[$box] = @{ Amount = [decimal]0; Name = $map.Name }
        }
        foreach ($acct in $accountTotals.Keys) {
            if ($acct -match $map.AccountPattern) {
                $boxTotals[$box].Amount += $accountTotals[$acct]
            }
        }
    }

    # Sales boxes (3xxx) are credit accounts — negate to show positive sales
    if ($boxTotals.ContainsKey(5)) {
        $boxTotals[5].Amount = [Math]::Abs($boxTotals[5].Amount)
    }

    # VAT accounts (26xx) — output VAT is credit (negate), input VAT is debit (negate for "to deduct")
    foreach ($box in @(10, 11, 12)) {
        if ($boxTotals.ContainsKey($box)) {
            $boxTotals[$box].Amount = [Math]::Abs($boxTotals[$box].Amount)
        }
    }
    if ($boxTotals.ContainsKey(48)) {
        $boxTotals[48].Amount = [Math]::Abs($boxTotals[48].Amount)
    }

    # Box 49 — output VAT minus input VAT
    $outputVat = [decimal]0
    foreach ($box in @(10, 11, 12)) {
        if ($boxTotals.ContainsKey($box)) { $outputVat += $boxTotals[$box].Amount }
    }
    $inputVat = if ($boxTotals.ContainsKey(48)) { $boxTotals[48].Amount } else { [decimal]0 }
    $vatToPay = $outputVat - $inputVat

    $results = foreach ($box in ($boxTotals.Keys | Sort-Object)) {
        [PSCustomObject]@{
            Box    = $box
            Name   = $boxTotals[$box].Name
            Amount = $boxTotals[$box].Amount
        }
    }

    $results += [PSCustomObject]@{
        Box    = 49
        Name   = 'Moms att betala eller få tillbaka'
        Amount = $vatToPay
    }

    $results
}
