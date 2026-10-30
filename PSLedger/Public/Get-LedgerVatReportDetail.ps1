<#
.SYNOPSIS
Explains the VAT report's contribution and mapping for each active account.

.DESCRIPTION
Returns one row per account occurring in verifications in the requested period,
including accounts that do not contribute to the VAT declaration. Opening
balances are not included. Accounts whose period balance is zero are retained.

Balance is the signed period movement (debit positive, credit negative).
Amount is the account's contribution to its VAT box: sales and output VAT are
negated, while purchase bases and input VAT retain their sign. Amount and Box
are null when the account does not contribute. Box 49 is calculated by
Get-LedgerVatReport and has no individual account mapping.

Source is BAS, vat.txt or None. Rule identifies the matched account or range.
Status is Mapped for an explicit box rule, Implicit for the BAS catch-all to
box 05, Excluded for an explicit no-box rule, or Unmapped if no rule matches.
Unmapped does not necessarily mean an error: bank and many expense accounts
normally have no VAT box. A warning is emitted for implicit matches in
3100-3399, just as in Get-LedgerVatReport.

Get-LedgerVatReport aggregates these same contributions, so the detail and
summary use identical date filtering, mapping precedence and sign conventions.

.PARAMETER JournalPath
The path to an existing journal directory. Defaults to the current journal.

.PARAMETER FiscalYear
The fiscal year identifier, for example '2024-01_2024-12'. Defaults to the
current fiscal year, or the latest year if none is selected.

.PARAMETER FromDate
Start of the reporting period (inclusive).

.PARAMETER ToDate
End of the reporting period (inclusive). Must not precede FromDate.

.EXAMPLE
Get-LedgerVatReportDetail -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -FromDate '2024-01-01' -ToDate '2024-03-31'

Shows the account balances, VAT contributions and rules used for Q1.

.EXAMPLE
Get-LedgerVatReportDetail -JournalPath .\Konsultbyrån.ledger -FiscalYear '2024-01_2024-12' -FromDate '2024-01-01' -ToDate '2024-03-31' |
    Format-Table AccountNumber, AccountName, Balance, Box, Amount, Source, Rule, Status

Explains, for example, how account 3308 contributes to box 39, a vat.txt
override changes account 3060, and account 1930 has no VAT mapping.
#>
function Get-LedgerVatReportDetail {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
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
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath
        if ($ToDate -lt $FromDate) {
            throw "ToDate ($($ToDate.ToString('yyyy-MM-dd'))) must not be earlier than FromDate ($($FromDate.ToString('yyyy-MM-dd')))."
        }

        $entries = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
            -FromDate $FromDate -ToDate $ToDate
        $rules = @(Get-VatBoxMapping -JournalPath $JournalPath)
        $definitions = @{}
        foreach ($definition in Get-VatBoxDefinition) { $definitions[$definition.Box] = $definition }
        $accountNames = @{}
        foreach ($account in Get-LedgerAccount -JournalPath $JournalPath) {
            $accountNames[$account.AccountNumber] = $account.AccountName
        }

        $totals = @{}
        foreach ($entry in $entries) {
            foreach ($row in $entry.Rows) {
                $account = [string]$row.Account
                if (-not $totals.ContainsKey($account)) { $totals[$account] = [decimal]0 }
                $totals[$account] += [decimal]$row.Amount
            }
        }

        foreach ($account in ($totals.Keys | Sort-Object { [long]$_ }, { $_ })) {
            $rule = Resolve-VatBoxRule -Account $account -Rules $rules
            $box = $null
            $amount = $null
            $ruleText = $null
            $source = 'None'
            $status = 'Unmapped'
            if ($null -ne $rule) {
                $source = if ($rule.Source -eq 'Default') { 'BAS' } else { $rule.Source }
                $ruleText = if ($rule.From -eq $rule.To) { "$($rule.From)" } else { "$($rule.From)-$($rule.To)" }
                $box = $rule.Box
                if ($null -eq $box) {
                    $status = 'Excluded'
                }
                else {
                    $status = if ($rule.Implicit) { 'Implicit' } else { 'Mapped' }
                    $amount = if ($definitions[$box].Kind -in 'Sales', 'OutputVat') { -$totals[$account] } else { $totals[$account] }
                    if ($rule.Implicit -and [long]$account -ge 3100 -and [long]$account -le 3399) {
                        Write-Warning ("Account $account is reported in box 05 (taxable sales), but BAS uses 3100–3399 for " +
                            "sales outside Sweden, margin scheme and reverse charge. Map it to the right box in vat.txt.")
                    }
                }
            }

            [PSCustomObject]@{
                FiscalYear    = $FiscalYear
                AccountNumber = $account
                AccountName   = $accountNames[$account]
                Balance       = $totals[$account]
                Box           = $box
                Amount        = $amount
                Source        = $source
                Rule          = $ruleText
                Status        = $status
            }
        }
    }
}
