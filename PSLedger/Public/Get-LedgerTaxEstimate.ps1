<#
.SYNOPSIS
Estimates the corporate income tax (bolagsskatt) for a fiscal year.

.DESCRIPTION
Calculates an estimated corporate tax for a limited company (aktiebolag) from the
ledger. The accounting result before tax is derived from the profit and loss
accounts up to and including appropriations (account classes 3-8, excluding the tax
accounts 8900-8989 and account 8999 Årets resultat).

The taxable result (skattemässigt resultat) is the accounting result before tax
adjusted for non-deductible expenses (ej avdragsgilla kostnader, added back) and
non-taxable income (ej skattepliktiga intäkter, subtracted). The estimated tax is
the taxable result multiplied by the tax rate, rounded to whole kronor. A negative
taxable result gives no tax.

This is an estimate to support the year-end closing; consult Skatteverket's rules
for the exact taxable base and rounding.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER TaxRate
The corporate tax rate as a fraction. Defaults to 0.206 (20.6 %), the Swedish
corporate tax rate since 2021.

.PARAMETER NonDeductibleExpenses
Non-deductible expenses (ej avdragsgilla kostnader) to add back to the accounting
result when computing the taxable result. Defaults to 0.

.PARAMETER NonTaxableIncome
Non-taxable income (ej skattepliktiga intäkter) to subtract from the accounting
result when computing the taxable result. Defaults to 0.

.EXAMPLE
Get-LedgerTaxEstimate -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12'

Estimates the corporate tax at the default rate from the year's result before tax.

.EXAMPLE
Get-LedgerTaxEstimate -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12' `
    -NonDeductibleExpenses 15000 -NonTaxableIncome 2000

Adds back 15 000 kr of non-deductible expenses and removes 2 000 kr of non-taxable
income before applying the tax rate, returning the taxable result and estimated tax.
#>
function Get-LedgerTaxEstimate {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [decimal]$TaxRate = 0.206,

        [Parameter()]
        [decimal]$NonDeductibleExpenses = 0,

        [Parameter()]
        [decimal]$NonTaxableIncome = 0
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $Balance = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear

        # Result before tax: profit and loss accounts up to and including
        # appropriations (3000-8899), excluding tax accounts (8900-8989) and account
        # 8999 (Årets resultat). Raw balances are negated so a profit is positive.
        $RawSum = [decimal]0
        foreach ($Row in $Balance) {
            $Number = 0
            if ([int]::TryParse($Row.AccountNumber, [ref]$Number) -and $Number -ge 3000 -and $Number -le 8899) {
                $RawSum += $Row.Balance
            }
        }
        $ResultBeforeTax = [Math]::Round(-$RawSum, 2)

        $TaxableResult = [Math]::Round($ResultBeforeTax + $NonDeductibleExpenses - $NonTaxableIncome, 2)

        $EstimatedTax = if ($TaxableResult -gt 0) {
            [Math]::Round($TaxableResult * $TaxRate, 0, [MidpointRounding]::AwayFromZero)
        }
        else {
            [decimal]0
        }

        [PSCustomObject]@{
            FiscalYear            = $FiscalYear
            ResultBeforeTax       = $ResultBeforeTax
            NonDeductibleExpenses = $NonDeductibleExpenses
            NonTaxableIncome      = $NonTaxableIncome
            TaxableResult         = $TaxableResult
            TaxRate               = $TaxRate
            EstimatedTax          = $EstimatedTax
        }
    }
}
