<#
.SYNOPSIS
Builds the movement schedule for a fixed asset group, the data behind an
anläggningstillgångar note in an årsredovisning.

.DESCRIPTION
Reports the change during the year in a group of fixed asset accounts, split into
the acquisition value roll-forward (ingående anskaffningsvärde, årets inköp, årets
avyttringar, utgående ackumulerat anskaffningsvärde) and, when a depreciation or
write-down account range is supplied, the accumulated depreciation/write-down
roll-forward (ingående, årets, utgående) and the resulting carrying amount
(utgående redovisat värde).

Acquisition values are taken from the account range's opening balance and the
period debit (purchases) and credit (disposals). Depreciation and write-downs are
taken from the depreciation account range. The carrying amount is the closing
acquisition value plus the (negative) closing accumulated depreciation.

Returns $null when the acquisition value range contains no accounts.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-09_2025-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER FromAccount
The first account number of the acquisition value range (e.g. 1350).

.PARAMETER ToAccount
The last account number of the acquisition value range (e.g. 1359).

.PARAMETER DepreciationFromAccount
The first account number of the accumulated depreciation/write-down range. Omit
for asset groups without a separate depreciation account.

.PARAMETER DepreciationToAccount
The last account number of the accumulated depreciation/write-down range.

.PARAMETER Label
A label for the note (e.g. 'Andra långfristiga värdepappersinnehav').

.EXAMPLE
Get-LedgerFixedAssetNote -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' `
    -FromAccount 1210 -ToAccount 1218 -DepreciationFromAccount 1219 -DepreciationToAccount 1219 `
    -Label 'Inventarier'

Returns the acquisition value and accumulated depreciation roll-forward for the
inventory (inventarier) asset group.

.EXAMPLE
Get-LedgerFixedAssetNote -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -FromAccount 1350 -ToAccount 1359 -Label 'Andra långfristiga värdepappersinnehav'

Returns the acquisition value roll-forward for long-term securities held as
financial fixed assets.
#>
function Get-LedgerFixedAssetNote {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [int]$FromAccount,

        [Parameter(Mandatory)]
        [int]$ToAccount,

        [Parameter()]
        [int]$DepreciationFromAccount,

        [Parameter()]
        [int]$DepreciationToAccount,

        [Parameter()]
        [string]$Label
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $Balance = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)
        if (-not $Balance) {
            return
        }

        function Select-Range {
            param ([int]$From, [int]$To)
            $rows = @()
            foreach ($Row in $Balance) {
                $Number = 0
                if ([int]::TryParse($Row.AccountNumber, [ref]$Number) -and $Number -ge $From -and $Number -le $To) {
                    $rows += $Row
                }
            }
            $rows
        }

        $CostRows = @(Select-Range -From $FromAccount -To $ToAccount)
        if (-not $CostRows) {
            return
        }

        $OpeningAcquisition = ($CostRows | Measure-Object -Property OpeningBalance -Sum).Sum
        $Purchases = ($CostRows | Measure-Object -Property Debit -Sum).Sum
        $Disposals = -1 * ($CostRows | Measure-Object -Property Credit -Sum).Sum
        $ClosingAcquisition = ($CostRows | Measure-Object -Property Balance -Sum).Sum

        $HasDepreciation = $PSBoundParameters.ContainsKey('DepreciationFromAccount') -and
            $PSBoundParameters.ContainsKey('DepreciationToAccount')

        $OpeningDepreciation = [decimal]0
        $YearDepreciation = [decimal]0
        $ClosingDepreciation = [decimal]0
        if ($HasDepreciation) {
            $DepRows = @(Select-Range -From $DepreciationFromAccount -To $DepreciationToAccount)
            $OpeningDepreciation = ($DepRows | Measure-Object -Property OpeningBalance -Sum).Sum
            $ClosingDepreciation = ($DepRows | Measure-Object -Property Balance -Sum).Sum
            $YearDepreciation = $ClosingDepreciation - $OpeningDepreciation
        }

        [PSCustomObject]@{
            Label                  = if ($Label) { $Label } else { "Konto $FromAccount-$ToAccount" }
            FiscalYear             = $FiscalYear
            OpeningAcquisition     = [decimal]$OpeningAcquisition
            Purchases              = [decimal]$Purchases
            Disposals              = [decimal]$Disposals
            ClosingAcquisition     = [decimal]$ClosingAcquisition
            HasDepreciation        = [bool]$HasDepreciation
            OpeningDepreciation    = [decimal]$OpeningDepreciation
            YearDepreciation       = [decimal]$YearDepreciation
            ClosingDepreciation    = [decimal]$ClosingDepreciation
            BookValue              = [decimal]$ClosingAcquisition + [decimal]$ClosingDepreciation
        }
    }
}
