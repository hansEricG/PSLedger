<#
.SYNOPSIS
Books a planned (straight-line) depreciation as a verification.

.DESCRIPTION
Records a planenlig avskrivning (planned depreciation) by creating a verification
that debits a depreciation expense account (class 78xx) and credits an accumulated
depreciation account (a contra-asset, e.g. 1229). This spreads the cost of a fixed
asset over its useful life following the matching principle.

The depreciation amount can be given directly with -Amount, or calculated with the
straight-line method from -AcquisitionCost and -UsefulLifeYears (amount =
acquisition cost / useful life, rounded to two decimals).

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12'). Must match an existing fiscal
year directory.

.PARAMETER Date
The date of the depreciation verification (typically the fiscal year end date).

.PARAMETER Description
Description for the verification. Defaults to 'Planenlig avskrivning'.

.PARAMETER ExpenseAccount
The depreciation expense account to debit (class 78xx, e.g. 7832 Avskrivningar på
inventarier och verktyg).

.PARAMETER AccumulatedDepreciationAccount
The accumulated depreciation account (contra-asset) to credit (e.g. 1229
Ackumulerade avskrivningar på inventarier och verktyg).

.PARAMETER Amount
The depreciation amount to book. Always positive. Use this to book a known amount.

.PARAMETER AcquisitionCost
The acquisition cost (anskaffningsvärde) of the asset. Used together with
-UsefulLifeYears to calculate the annual straight-line depreciation.

.PARAMETER UsefulLifeYears
The useful life of the asset in years (nyttjandeperiod). Used together with
-AcquisitionCost to calculate the annual straight-line depreciation.

.EXAMPLE
Add-LedgerDepreciation -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' `
    -Date '2024-12-31' -ExpenseAccount '7832' `
    -AccumulatedDepreciationAccount '1229' -Amount 20000

Books a known planned depreciation of 20 000 kr on 2024-12-31: debit 7832, credit
1229.

.EXAMPLE
Add-LedgerDepreciation -JournalPath .\Byggfirman.ledger -FiscalYear '2024-01_2024-12' `
    -Date '2024-12-31' -Description 'Avskrivning maskiner' -ExpenseAccount '7831' `
    -AccumulatedDepreciationAccount '1219' -AcquisitionCost 250000 -UsefulLifeYears 5

Calculates a straight-line depreciation of 50 000 kr (250 000 / 5) and books it:
debit 7831 (Avskrivningar på maskiner), credit 1219 (Ackumulerade avskrivningar på
maskiner).
#>
function Add-LedgerDepreciation {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'DirectAmount')]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [datetime]$Date,

        [Parameter()]
        [string]$Description = 'Planenlig avskrivning',

        [Parameter(Mandatory)]
        [string]$ExpenseAccount,

        [Parameter(Mandatory)]
        [string]$AccumulatedDepreciationAccount,

        [Parameter(Mandatory, ParameterSetName = 'DirectAmount')]
        [decimal]$Amount,

        [Parameter(Mandatory, ParameterSetName = 'StraightLine')]
        [decimal]$AcquisitionCost,

        [Parameter(Mandatory, ParameterSetName = 'StraightLine')]
        [int]$UsefulLifeYears
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        if ($PSCmdlet.ParameterSetName -eq 'StraightLine') {
            if ($AcquisitionCost -le 0) {
                throw "AcquisitionCost must be positive. Got: $AcquisitionCost"
            }
            if ($UsefulLifeYears -le 0) {
                throw "UsefulLifeYears must be positive. Got: $UsefulLifeYears"
            }
            $DepreciationAmount = [Math]::Round([decimal]$AcquisitionCost / $UsefulLifeYears, 2)
        }
        else {
            $DepreciationAmount = [Math]::Round([decimal]$Amount, 2)
        }

        if ($DepreciationAmount -le 0) {
            throw "Depreciation amount must be positive. Got: $DepreciationAmount"
        }

        if (-not $PSCmdlet.ShouldProcess($FiscalYear, "Book depreciation of $DepreciationAmount")) {
            return
        }

        # Debit the expense account, credit the accumulated depreciation account.
        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
            -Date $Date -Description $Description -Rows @(
            @{ Account = $ExpenseAccount; Amount = $DepreciationAmount }
            @{ Account = $AccumulatedDepreciationAccount; Amount = -$DepreciationAmount }
        )

        [PSCustomObject]@{
            FiscalYear                     = $FiscalYear
            Date                           = $Date
            Description                    = $Description
            ExpenseAccount                 = $ExpenseAccount
            AccumulatedDepreciationAccount = $AccumulatedDepreciationAccount
            Amount                         = $DepreciationAmount
        }
    }
}
