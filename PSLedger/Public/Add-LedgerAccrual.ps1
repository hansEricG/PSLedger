<#
.SYNOPSIS
Creates an accrual with automatic reversal in the next period.

.DESCRIPTION
Creates two coupled verifications: one that moves an expense or revenue to a
balance sheet account (accrual), and a reversal that undoes it at a specified
future date. This implements the matching principle by recognising costs and
revenues in the correct period.

Both verifications reference each other in their descriptions. The reversal is
always the mirror image of the accrual (same accounts, opposite amounts).

.PARAMETER JournalPath
Path to the journal (.ledger directory).

.PARAMETER FiscalYear
Fiscal year for the accrual verification (format: yyyy-MM_yyyy-MM).

.PARAMETER Date
Date for the accrual verification.

.PARAMETER Description
Description for both verifications. The function appends cross-reference text.

.PARAMETER ExpenseAccount
The expense (or revenue) account to relieve in the accrual period.

.PARAMETER AccrualAccount
The balance sheet account that holds the accrual (e.g., 1730 or 2990).

.PARAMETER Amount
The amount to accrue. Always positive — the function determines debit/credit direction.

.PARAMETER ReversalFiscalYear
Fiscal year for the reversal verification. Must already exist.

.PARAMETER ReversalDate
Date for the reversal verification.

.EXAMPLE
Add-LedgerAccrual -JournalPath .\mycompany.ledger -FiscalYear '2024-01_2024-12' `
    -Date '2024-12-31' -Description 'Förutbetald försäkring Q1 2025' `
    -ExpenseAccount '6310' -AccrualAccount '1730' -Amount 12000 `
    -ReversalFiscalYear '2025-01_2025-12' -ReversalDate '2025-01-01'

Creates an accrual on 2024-12-31 (debit 1730, credit 6310) and a reversal
on 2025-01-01 (debit 6310, credit 1730).

.EXAMPLE
Add-LedgerAccrual -JournalPath .\ab.ledger -FiscalYear '2024-01_2024-12' `
    -Date '2024-12-31' -Description 'Förutbetald hyra jan' `
    -ExpenseAccount '5010' -AccrualAccount '1710' -Amount 8000 `
    -ReversalFiscalYear '2025-01_2025-12' -ReversalDate '2025-01-01'

Accrues a prepaid rent expense of 8000 kr at year-end with automatic reversal
in January.
#>
function Add-LedgerAccrual {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [datetime]$Date,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [string]$ExpenseAccount,

        [Parameter(Mandatory)]
        [string]$AccrualAccount,

        [Parameter(Mandatory)]
        [decimal]$Amount,

        [Parameter(Mandatory)]
        [string]$ReversalFiscalYear,

        [Parameter(Mandatory)]
        [datetime]$ReversalDate
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if ($Amount -le 0) {
        throw "Amount must be positive. Got: $Amount"
    }

    # Verify reversal fiscal year exists
    $reversalYearDir = Join-Path $JournalPath $ReversalFiscalYear
    if (-not (Test-Path $reversalYearDir)) {
        throw "Reversal fiscal year '$ReversalFiscalYear' does not exist. Create it first with New-LedgerFiscalYear."
    }

    # Create accrual: debit balance sheet account, credit expense account
    Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
        -Date $Date -Description "$Description (periodisering)" -Rows @(
        @{ Account = $AccrualAccount; Amount = $Amount }
        @{ Account = $ExpenseAccount; Amount = -$Amount }
    )

    # Create reversal: debit expense account, credit balance sheet account
    Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $ReversalFiscalYear `
        -Date $ReversalDate -Description "$Description (återföring)" -Rows @(
        @{ Account = $ExpenseAccount; Amount = $Amount }
        @{ Account = $AccrualAccount; Amount = -$Amount }
    )

    [PSCustomObject]@{
        AccrualDate       = $Date
        AccrualFiscalYear = $FiscalYear
        ReversalDate      = $ReversalDate
        ReversalFiscalYear = $ReversalFiscalYear
        ExpenseAccount    = $ExpenseAccount
        AccrualAccount    = $AccrualAccount
        Amount            = $Amount
        Description       = $Description
    }
}
