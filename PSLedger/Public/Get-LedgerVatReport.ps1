<#
.SYNOPSIS
Generates a VAT report (momsrapport) for a period.

.DESCRIPTION
Reads all verifications in the specified date range and maps account totals to
the boxes (rutor) of Skatteverket's VAT return (momsdeklaration). Returns one
object per box with its number, name and amount, followed by box 49.

The default mapping follows the BAS chart of accounts, for example:
  Box 05 — Taxable sales not in another box (the rest of 3000–3799)
  Box 06 — Taxable withdrawals (3401–3403)
  Box 07 — Separately booked taxable VMB margin, excluding VAT (3211)
  Box 08 — Rental income, voluntary tax liability (3913)
  Box 10/11/12 — Output VAT 25/12/6 % (2610–2613, 2616 and 262x/263x)
  Box 20/21 — Goods/services bought from another EU country (4515–4517, 4535–4537)
  Box 22 — Services bought from outside the EU (4531–4533)
  Box 23/24 — Domestic reverse-charge purchases (4415–4417, 4425–4427)
  Box 30/31/32 — Output VAT on purchases (2614, 2617 and 262x/263x)
  Box 35/36 — Goods sold to another EU country / outside the EU (3108, 3105)
  Box 37/38 — Triangular trade purchases/sales (4512, 3107)
  Box 39/40 — Services sold to another EU country / outside the EU (3308, 3305)
  Box 41 — Sales where the buyer is liable for VAT (3231–3233)
  Box 42 — Other sales, e.g. VAT-exempt (3004, 3404)
  Box 48 — Input VAT to deduct (2640–2647, 2649)
  Box 50 — Taxable value of imports (4545–4547)
  Box 60/61/62 — Output VAT on imports (2615, 2625, 2635)
  Box 49 — VAT to pay (positive) or reclaim (negative):
           10+11+12+30+31+32+60+61+62 − 48

A journal can override the mapping with a vat.txt file in the journal directory,
for example when its chart of accounts deviates from BAS. Each line holds an
account or an account range and a box number, separated by a tab; '-' as the
box means the accounts are not reported. Rules in vat.txt take precedence over
the defaults. See docs/File-format.md.

Sales and output VAT amounts are reported as credit amounts made positive;
purchase bases and input VAT as debit amounts. Boxes 05, 10, 11, 12 and 48 are
always returned; other boxes only when an account with activity in the period
maps to them.

Negative VMB sales (3212) do not contribute to any box. Positive VMB requires
the taxable margin excluding VAT to be booked separately on 3211; this report
does not calculate margins from purchase and sales prices or implement simplified
VMB. Use vat.txt if the taxable base is recorded on another account. Other taxable
rental income (3914), unlike voluntarily taxed rent, belongs in box 05.

A warning is written for accounts in 3100–3399 (BAS sales outside Sweden, margin
scheme and reverse charge) with activity that are not explicitly mapped and
therefore end up in box 05. Map them in vat.txt to silence the warning.
Use Get-LedgerVatReportDetail to see each account's contribution, matched rule,
mapping source and any accounts excluded from the declaration.

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
Get-LedgerVatReport -JournalPath .\Konsultbyrån.ledger -FiscalYear '2024-01_2024-12' -FromDate '2024-01-01' -ToDate '2024-01-31' |
    Format-Table Box, Name, Amount

Displays January's VAT report as a formatted table. Consulting sold to an EU
customer on account 3308 appears in box 39.
#>
function Get-LedgerVatReport {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [datetime]$FromDate,

        [Parameter(Mandatory)]
        [datetime]$ToDate
    )
    process {
        $details = @(Get-LedgerVatReportDetail -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate $FromDate -ToDate $ToDate)
        $definitions = @(Get-VatBoxDefinition)
        $amounts = @{}
        foreach ($box in 5, 10, 11, 12, 48) { $amounts[$box] = [decimal]0 }
        foreach ($detail in $details) {
            if ($null -eq $detail.Box) { continue }
            if (-not $amounts.ContainsKey($detail.Box)) { $amounts[$detail.Box] = [decimal]0 }
            $amounts[$detail.Box] += $detail.Amount
        }

        $vatToPay = [decimal]0
        foreach ($def in $definitions | Where-Object Kind -eq 'OutputVat') {
            if ($amounts.ContainsKey($def.Box)) { $vatToPay += $amounts[$def.Box] }
        }
        $vatToPay -= $amounts[48]

        foreach ($def in ($definitions | Where-Object Kind -ne 'Result' | Sort-Object Box)) {
            if (-not $amounts.ContainsKey($def.Box)) { continue }
            [PSCustomObject]@{
                Box    = $def.Box
                Name   = $def.Name
                Amount = $amounts[$def.Box]
            }
        }

        [PSCustomObject]@{
            Box    = 49
            Name   = 'Moms att betala eller få tillbaka'
            Amount = $vatToPay
        }
    }
}
