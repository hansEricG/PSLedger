<#
.SYNOPSIS
Books a write-down (nedskrivning) of an asset, or the reversal (återföring) of an
earlier write-down, as a verification.

.DESCRIPTION
Records a nedskrivning by creating a verification that debits a write-down
expense account and credits a value adjustment (accumulated write-down) account:

    <ExpenseAccount>      +<amount>
    <AdjustmentAccount>   -<amount>

With -Reverse the entry is turned around and records an återföring: the value
adjustment account is debited and ExpenseAccount (then a reversal account such as
8281 or 7760) is credited. A reversal can never exceed the write-downs accumulated
on the value adjustment account.

The amount can be given directly with -Amount, or derived from a holding recorded
with Set-LedgerHolding by giving -Account and -Name:

- Write-down: the holding is written down to its market value. The amount is
  BookValue - MarketValue for the holding (when it has a BookValue), otherwise the
  account's book value (including value adjustment accounts in the same ten-group)
  less its market value when it is the only holding on the account. After booking,
  the holding's BookValue is set to its market value.
- Reversal (-Reverse): the holding's book value is written back up to the lower of
  its market value and its acquisition cost (Cost). The holding needs both a
  BookValue and a Cost. After booking, BookValue is increased by the amount.

Typical BAS accounts: 8271/1359 (write-down) and 8281/1359 (reversal) for
long-term securities, and 7710/1098 and 7760/1098 for crypto assets reported as
intangible fixed assets (K3).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2026-09_2027-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER Date
The date of the entry. Defaults to the fiscal year's end date (the balance date).

.PARAMETER Description
Description for the verification. Defaults to 'Nedskrivning <holding> till
marknadsvärde' / 'Återföring av nedskrivning <holding>' for a holding, otherwise
'Nedskrivning' / 'Återföring av nedskrivning'.

.PARAMETER ExpenseAccount
The write-down expense account to debit (e.g. 8271 or 7710), or with -Reverse the
reversal account to credit (e.g. 8281 or 7760).

.PARAMETER AdjustmentAccount
The value adjustment / accumulated write-down account (e.g. 1359 or 1098).

.PARAMETER Amount
The amount to write down or reverse. Always positive.

.PARAMETER Account
The account of the holding to write down or reverse.

.PARAMETER Name
The name of the holding to write down or reverse.

.PARAMETER Reverse
Book a reversal (återföring) of an earlier write-down instead of a write-down.

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

.EXAMPLE
Add-LedgerImpairment -JournalPath .\HEG.ledger -FiscalYear '2027-09_2028-08' `
    -Account 1350 -Name 'Knowit' -ExpenseAccount 8281 -AdjustmentAccount 1359 -Reverse

Reverses the Knowit write-down as far as the recovered market value allows, but
never above the acquisition cost.
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
        [string]$Name,

        [Parameter()]
        [switch]$Reverse
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

            if ($Reverse) {
                if ($null -eq $Holding.BookValue -or $null -eq $Holding.Cost) {
                    throw "Holding '$Name' needs both BookValue and Cost to compute a reversal. Record them with Set-LedgerHolding or use -Amount."
                }
                $Booked = [Math]::Round([decimal]$Holding.Reversible, 2)
                if ($Booked -le 0) {
                    throw "Holding '$Name' has nothing to reverse (market value $($Holding.MarketValue), book value $($Holding.BookValue), cost $($Holding.Cost))."
                }
                if (-not $Description) { $Description = "Återföring av nedskrivning $Name" }
            }
            else {
                if ($null -ne $Holding.BookValue) {
                    $Booked = $Holding.BookValue - $Holding.MarketValue
                }
                else {
                    $OnAccount = @($Valuation.Holdings | Where-Object { $_.Account -eq $Account })
                    if ($OnAccount.Count -ne 1) {
                        throw "Holding '$Name' has no BookValue and shares account $Account with other holdings. Record its BookValue with Set-LedgerHolding or use -Amount."
                    }
                    $AccountRow = $Valuation.Accounts | Where-Object { $_.Account -eq $Account }
                    $Booked = $AccountRow.BookValue - $AccountRow.MarketValue
                }
                $Booked = [Math]::Round([decimal]$Booked, 2)
                if ($Booked -le 0) {
                    throw "Holding '$Name' is not below its book value (market value $($Holding.MarketValue)). Nothing to write down."
                }
                if ($null -eq $Holding.Cost) {
                    Write-Warning "Holding '$Name' has no Cost (anskaffningsvärde). Record it with Set-LedgerHolding -Cost so a later reversal can be computed."
                }
                if (-not $Description) { $Description = "Nedskrivning $Name till marknadsvärde" }
            }
        }
        else {
            $Booked = [Math]::Round([decimal]$Amount, 2)
            if ($Booked -le 0) {
                throw "Amount must be positive. Got: $Booked"
            }
        }
        if (-not $Description) {
            $Description = if ($Reverse) { 'Återföring av nedskrivning' } else { 'Nedskrivning' }
        }

        if ($Reverse) {
            # The value adjustment account carries a credit balance; a reversal must not exceed it.
            $AdjustmentRow = Get-LedgerBalance -JournalPath $ResolvedJournal -FiscalYear $ResolvedYear |
                Where-Object { $_.AccountNumber -eq $AdjustmentAccount } | Select-Object -First 1
            $Accumulated = if ($AdjustmentRow) { -[decimal]$AdjustmentRow.Balance } else { [decimal]0 }
            if ($Booked -gt $Accumulated) {
                throw "Reversal $Booked exceeds the write-downs accumulated on $AdjustmentAccount ($Accumulated)."
            }
        }

        $Action = if ($Reverse) { "Book reversal of write-down of $Booked" } else { "Book write-down of $Booked" }
        if (-not $PSCmdlet.ShouldProcess($ResolvedYear, $Action)) {
            return
        }

        $Sign = if ($Reverse) { -1 } else { 1 }
        $Entry = Add-LedgerEntry -JournalPath $ResolvedJournal -FiscalYear $ResolvedYear `
            -Date $EntryDate -Description $Description -PassThru -Rows @(
            @{ Account = $ExpenseAccount; Amount = $Sign * $Booked }
            @{ Account = $AdjustmentAccount; Amount = -$Sign * $Booked }
        )

        if ($Holding) {
            $NewBookValue = if ($Reverse) { $Holding.BookValue + $Booked } else { $Holding.MarketValue }
            Set-LedgerHolding -JournalPath $ResolvedJournal -FiscalYear $ResolvedYear -Account $Account -Name $Name `
                -BookValue $NewBookValue -WarningAction SilentlyContinue -Confirm:$false
        }

        [PSCustomObject]@{
            FiscalYear         = $ResolvedYear
            VerificationNumber = $Entry.VerificationNumber
            Date               = $EntryDate
            Description        = $Description
            Type               = if ($Reverse) { 'Reversal' } else { 'WriteDown' }
            ExpenseAccount     = $ExpenseAccount
            AdjustmentAccount  = $AdjustmentAccount
            Amount             = $Booked
            Holding            = if ($Holding) { $Name } else { $null }
        }
    }
}
