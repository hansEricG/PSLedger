<#
.SYNOPSIS
Books a year-end appropriation (bokslutsdisposition) as a verification.

.DESCRIPTION
Records a bokslutsdisposition for a limited company (aktiebolag) by creating a
verification between an untaxed reserve (obeskattad reserv, account class 21xx) and
the corresponding appropriation account (account group 88). Two reserve types are
supported:

- Periodiseringsfond: allocation debits 8811 and credits 2110; a reversal
  (-Reverse) debits 2110 and credits 8819.
- Overavskrivning (ackumulerade överavskrivningar): a change debits 8850 and credits
  2150; a reversal (-Reverse) debits 2150 and credits 8850.

An allocation reduces the year's result and increases the untaxed reserve; a
reversal does the opposite. Account defaults follow the BAS chart and can be
overridden with -ReserveAccount and -AppropriationAccount.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12'). Must match an existing fiscal
year directory.

.PARAMETER Date
The date of the appropriation verification (typically the fiscal year end date).

.PARAMETER Type
The kind of appropriation: 'Periodiseringsfond' or 'Overavskrivning'.

.PARAMETER Amount
The amount to appropriate. Always positive; -Reverse controls the direction.

.PARAMETER Reverse
Reverses (dissolves) the reserve instead of allocating to it, increasing the year's
result.

.PARAMETER Description
Description for the verification. Defaults to a text based on the type and
direction.

.PARAMETER ReserveAccount
The untaxed reserve balance account. Defaults to 2110 (Periodiseringsfonder) or 2150
(Ackumulerade överavskrivningar) depending on -Type.

.PARAMETER AppropriationAccount
The appropriation account (account group 88) affecting the result. Defaults follow
the type and direction (8811/8819 for periodiseringsfond, 8850 for överavskrivning).

.EXAMPLE
Add-LedgerAppropriation -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12' `
    -Date '2024-12-31' -Type Periodiseringsfond -Amount 50000

Allocates 50 000 kr to the tax allocation reserve: debit 8811, credit 2110.

.EXAMPLE
Add-LedgerAppropriation -JournalPath .\MinAB.ledger -FiscalYear '2024-01_2024-12' `
    -Date '2024-12-31' -Type Periodiseringsfond -Amount 30000 -Reverse

Reverses 30 000 kr of an earlier tax allocation reserve: debit 2110, credit 8819,
increasing the year's result.
#>
function Add-LedgerAppropriation {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [datetime]$Date,

        [Parameter(Mandatory)]
        [ValidateSet('Periodiseringsfond', 'Overavskrivning')]
        [string]$Type,

        [Parameter(Mandatory)]
        [decimal]$Amount,

        [Parameter()]
        [switch]$Reverse,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$ReserveAccount,

        [Parameter()]
        [string]$AppropriationAccount
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $AppropriationAmount = [Math]::Round([decimal]$Amount, 2)
        if ($AppropriationAmount -le 0) {
            throw "Amount must be positive. Got: $AppropriationAmount"
        }

        # Resolve default accounts and description per type and direction.
        if (-not $ReserveAccount) {
            $ReserveAccount = if ($Type -eq 'Periodiseringsfond') { '2110' } else { '2150' }
        }
        if (-not $AppropriationAccount) {
            $AppropriationAccount = if ($Type -eq 'Periodiseringsfond') {
                if ($Reverse) { '8819' } else { '8811' }
            }
            else {
                '8850'
            }
        }
        if (-not $Description) {
            $Description = switch ($Type) {
                'Periodiseringsfond' {
                    if ($Reverse) { 'Återföring från periodiseringsfond' } else { 'Avsättning till periodiseringsfond' }
                }
                'Overavskrivning' {
                    if ($Reverse) { 'Återföring av överavskrivningar' } else { 'Förändring av överavskrivningar' }
                }
            }
        }

        if (-not $PSCmdlet.ShouldProcess($FiscalYear, "Book $Type appropriation of $AppropriationAmount")) {
            return
        }

        # An allocation debits the appropriation account and credits the reserve; a
        # reversal does the opposite, increasing the year's result.
        $Rows = if ($Reverse) {
            @(
                @{ Account = $ReserveAccount; Amount = $AppropriationAmount }
                @{ Account = $AppropriationAccount; Amount = -$AppropriationAmount }
            )
        }
        else {
            @(
                @{ Account = $AppropriationAccount; Amount = $AppropriationAmount }
                @{ Account = $ReserveAccount; Amount = -$AppropriationAmount }
            )
        }

        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
            -Date $Date -Description $Description -Rows $Rows

        [PSCustomObject]@{
            FiscalYear           = $FiscalYear
            Date                 = $Date
            Type                 = $Type
            Reverse              = [bool]$Reverse
            Description          = $Description
            ReserveAccount       = $ReserveAccount
            AppropriationAccount = $AppropriationAccount
            Amount               = $AppropriationAmount
        }
    }
}
