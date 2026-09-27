<#
.SYNOPSIS
Books a write-down (nedskrivning) of an asset as a verification.

.DESCRIPTION
Records a nedskrivning by creating a verification that debits a write-down
expense account and credits a value adjustment (accumulated write-down) account:

    <ExpenseAccount>      +<amount>
    <AdjustmentAccount>   -<amount>

The amount can be given directly with -Amount, or derived from a holding recorded
with Set-LedgerHolding by giving -Account and -Name. The holding is then written
down to its market value: the amount is BookValue - MarketValue for the holding
(when it has a BookValue), otherwise the account's book value (including value
adjustment accounts in the same ten-group) less its market value when it is the
only holding on the account. After booking, the holding's BookValue is set to its
market value so later comparisons start from the written-down value.

Typical BAS accounts: 8271/1359 for other long-term securities (K2) and 7710/1098
for crypto assets reported as intangible fixed assets (K3).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2026-09_2027-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER Date
The date of the write-down. Defaults to the fiscal year's end date (the balance date).

.PARAMETER Description
Description for the verification. Defaults to 'Nedskrivning <holding> till
marknadsvärde' for a holding, otherwise 'Nedskrivning'.

.PARAMETER ExpenseAccount
The write-down expense account to debit (e.g. 8271 or 7710).

.PARAMETER AdjustmentAccount
The value adjustment / accumulated write-down account to credit (e.g. 1359 or 1098).

.PARAMETER Amount
The write-down amount. Always positive.

.PARAMETER Account
The account of the holding to write down to its market value.

.PARAMETER Name
The name of the holding to write down to its market value.

.EXAMPLE
Add-LedgerImpairment -JournalPath .\HEG.ledger -FiscalYear '2025-09_2026-08' `
    -ExpenseAccount 8271 -AdjustmentAccount 1359 -Amount 24348 `
    -Description 'Nedskrivning Knowit 200 st till 94,50 kr (bestående värdenedgång)'

Books a known write-down of 24 348 kr on the balance date.

.EXAMPLE
Add-LedgerImpairment -JournalPath .\HEG.ledger -FiscalYear '2026-09_2027-08' `
    -Account 1090 -Name 'Bitcoin (BTC)' -ExpenseAccount 7710 -AdjustmentAccount 1098

Writes the bitcoin holding down to its recorded market value (K3) and updates the
holding's book value.
#>
function Add-LedgerImpairment {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'DirectAmount')]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$FiscalYear,

        [Parameter()]
        [datetime]$Date,

        [Parameter()]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+$')]
        [string]$ExpenseAccount,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+$')]
        [string]$AdjustmentAccount,

        [Parameter(Mandatory, ParameterSetName = 'DirectAmount')]
        [decimal]$Amount,

        [Parameter(Mandatory, ParameterSetName = 'Holding', ValueFromPipelineByPropertyName)]
        [ValidatePattern('^\d+$')]
        [string]$Account,

        [Parameter(Mandatory, ParameterSetName = 'Holding', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    process {
        $ResolvedJournal = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $ResolvedYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $ResolvedJournal

        $YearDir = Join-Path $ResolvedJournal $ResolvedYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $ResolvedYear"
        }

        $EntryDate = $Date
        if (-not $PSBoundParameters.ContainsKey('Date')) {
            $Year = Get-LedgerFiscalYear -JournalPath $ResolvedJournal | Where-Object { $_.Name -eq $ResolvedYear } | Select-Object -First 1
            $EntryDate = [datetime]::ParseExact($Year.EndDate.Trim(), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        }

        $Holding = $null
        if ($PSCmdlet.ParameterSetName -eq 'Holding') {
            $Valuation = Get-LedgerHoldingValuation -JournalPath $ResolvedJournal -FiscalYear $ResolvedYear
            $Holding = $Valuation.Holdings | Where-Object { $_.Account -eq $Account -and $_.Name -eq $Name } | Select-Object -First 1
            if (-not $Holding) {
                throw "Holding '$Name' on account $Account not found in $ResolvedYear."
            }
            if ($null -ne $Holding.BookValue) {
                $WriteDown = $Holding.BookValue - $Holding.MarketValue
            }
            else {
                $OnAccount = @($Valuation.Holdings | Where-Object { $_.Account -eq $Account })
                if ($OnAccount.Count -ne 1) {
                    throw "Holding '$Name' has no BookValue and shares account $Account with other holdings. Record its BookValue with Set-LedgerHolding or use -Amount."
                }
                $AccountRow = $Valuation.Accounts | Where-Object { $_.Account -eq $Account }
                $WriteDown = $AccountRow.BookValue - $AccountRow.MarketValue
            }
            $WriteDown = [Math]::Round([decimal]$WriteDown, 2)
            if ($WriteDown -le 0) {
                throw "Holding '$Name' is not below its book value (market value $($Holding.MarketValue)). Nothing to write down."
            }
            if (-not $Description) {
                $Description = "Nedskrivning $Name till marknadsvärde"
            }
        }
        else {
            $WriteDown = [Math]::Round([decimal]$Amount, 2)
            if ($WriteDown -le 0) {
                throw "Write-down amount must be positive. Got: $WriteDown"
            }
        }
        if (-not $Description) {
            $Description = 'Nedskrivning'
        }

        if (-not $PSCmdlet.ShouldProcess($ResolvedYear, "Book write-down of $WriteDown")) {
            return
        }

        $Entry = Add-LedgerEntry -JournalPath $ResolvedJournal -FiscalYear $ResolvedYear `
            -Date $EntryDate -Description $Description -PassThru -Rows @(
            @{ Account = $ExpenseAccount; Amount = $WriteDown }
            @{ Account = $AdjustmentAccount; Amount = -$WriteDown }
        )

        if ($Holding) {
            Set-LedgerHolding -JournalPath $ResolvedJournal -FiscalYear $ResolvedYear -Account $Account -Name $Name `
                -BookValue $Holding.MarketValue -WarningAction SilentlyContinue -Confirm:$false
        }

        [PSCustomObject]@{
            FiscalYear         = $ResolvedYear
            VerificationNumber = $Entry.VerificationNumber
            Date               = $EntryDate
            Description        = $Description
            ExpenseAccount     = $ExpenseAccount
            AdjustmentAccount  = $AdjustmentAccount
            Amount             = $WriteDown
            Holding            = if ($Holding) { $Name } else { $null }
        }
    }
}
