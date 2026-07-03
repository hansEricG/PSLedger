<#
.SYNOPSIS
Books the corporate income tax (bolagsskatt) as a verification.

.DESCRIPTION
Records the corporate tax for a limited company (aktiebolag) by creating a
verification that debits the tax expense account (8910 Skatt på årets resultat by
default) and credits the tax liability account (2510 Skatteskulder by default).

The tax amount can be supplied directly with -Amount or piped in from
Get-LedgerTaxEstimate, whose EstimatedTax and FiscalYear properties bind to this
command's parameters.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12'). Must match an existing fiscal
year directory.

.PARAMETER Date
The date of the tax verification (typically the fiscal year end date).

.PARAMETER Amount
The tax amount to book. Always positive. Binds to the EstimatedTax property when
piping from Get-LedgerTaxEstimate.

.PARAMETER TaxAccount
The tax expense account to debit. Defaults to '8910' (Skatt på årets resultat).

.PARAMETER LiabilityAccount
The tax liability account to credit. Defaults to '2510' (Skatteskulder).

.PARAMETER Description
Description for the verification. Defaults to 'Skatt på årets resultat'.

.EXAMPLE
Add-LedgerTaxEntry -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12' `
    -Date '2024-12-31' -Amount 41200

Books 41 200 kr of corporate tax on 2024-12-31: debit 8910, credit 2510.

.EXAMPLE
Get-LedgerTaxEstimate -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12' |
    Add-LedgerTaxEntry -JournalPath .\MinAB.ledger -Date '2024-12-31'

Estimates the corporate tax and books it in one pipeline, using the estimate's
EstimatedTax and FiscalYear.
#>
function Add-LedgerTaxEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [datetime]$Date,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('EstimatedTax')]
        [decimal]$Amount,

        [Parameter()]
        [string]$TaxAccount = '8910',

        [Parameter()]
        [string]$LiabilityAccount = '2510',

        [Parameter()]
        [string]$Description = 'Skatt på årets resultat'
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $TaxAmount = [Math]::Round([decimal]$Amount, 2)
        if ($TaxAmount -le 0) {
            throw "Tax amount must be positive. Got: $TaxAmount"
        }

        if (-not $PSCmdlet.ShouldProcess($FiscalYear, "Book tax of $TaxAmount")) {
            return
        }

        # Debit the tax expense account, credit the tax liability account.
        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
            -Date $Date -Description $Description -Rows @(
            @{ Account = $TaxAccount; Amount = $TaxAmount }
            @{ Account = $LiabilityAccount; Amount = -$TaxAmount }
        )

        [PSCustomObject]@{
            FiscalYear       = $FiscalYear
            Date             = $Date
            Description      = $Description
            TaxAccount       = $TaxAccount
            LiabilityAccount = $LiabilityAccount
            Amount           = $TaxAmount
        }
    }
}
