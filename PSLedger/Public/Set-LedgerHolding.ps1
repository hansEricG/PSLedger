<#
.SYNOPSIS
Records or updates a securities holding (innehav) for a fiscal year.

.DESCRIPTION
Stores a holding at the balance date in the fiscal year's holdings.txt (UTF-8,
tab-separated). A holding is identified by Account and Name: if a holding with
the same Account and Name exists it is updated, otherwise a new one is added.
When updating, only the supplied fields are changed; pass an empty string to
clear Isin, PriceDate or Source, and $null to clear BookValue.

The market value in SEK is computed as Quantity * Price * FxRate. It is used by
Get-LedgerShareholdingNote and the annual report instead of the single
SecuritiesMarketValue recorded with Set-LedgerReportInput, and by
Test-LedgerFiscalYear to flag holdings whose market value is below book value.

Holdings cannot be changed in a closed fiscal year.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-09_2025-08'). If omitted, uses the current
fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER Account
The account the holding is booked on, e.g. 1350 (long-term) or 1810 (short-term).

.PARAMETER Name
The name of the holding, e.g. 'Investor B'. Together with Account it identifies
the holding.

.PARAMETER Isin
Optional ISIN (International Securities Identification Number), e.g.
'SE0015811963'. The format and check digit are validated.

.PARAMETER Quantity
Number of shares or fund units held at the balance date. Required for a new holding.

.PARAMETER Price
Price per unit at the balance date, in Currency. Required for a new holding.

.PARAMETER Currency
ISO currency code of Price. Defaults to SEK.

.PARAMETER FxRate
Exchange rate in SEK per one unit of Currency at the balance date. Required when
Currency is not SEK; must be 1 (or omitted) for SEK.

.PARAMETER PriceDate
The date of the price, in yyyy-MM-dd format (normally the balance date).

.PARAMETER Source
Where the price was taken from, e.g. 'Nasdaq Stockholm' or 'Avanza årsbesked'.

.PARAMETER BookValue
Optional book value (redovisat värde) of this holding in SEK: acquisition cost
less any write-downs. Enables a per-holding impairment comparison when several
holdings share an account.

.EXAMPLE
Set-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -Account 1350 -Name 'Investor B' -Quantity 500 -Price 265.40

Records 500 Investor B shares at 265.40 SEK.

.EXAMPLE
Set-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -Account 1350 -Name 'Vanguard FTSE All-World' -Isin 'IE00BK5BQT80' `
    -Quantity 120 -Price 118.20 -Currency USD -FxRate 9.5312 `
    -PriceDate '2025-08-29' -Source 'Avanza årsbesked' -BookValue 110000

Records a USD-denominated fund with ISIN, price source and book value.
#>
function Set-LedgerHolding {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+$')]
        [string]$Account,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [AllowEmptyString()]
        [string]$Isin,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [decimal]$Quantity,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [decimal]$Price,

        [Parameter()]
        [ValidatePattern('^[A-Za-z]{3}$')]
        [string]$Currency,

        [Parameter()]
        [decimal]$FxRate,

        [Parameter()]
        [AllowEmptyString()]
        [string]$PriceDate,

        [Parameter()]
        [AllowEmptyString()]
        [string]$Source,

        [Parameter()]
        [AllowNull()]
        [Nullable[decimal]]$BookValue
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }
        Assert-LedgerFiscalYearOpen -YearDir $YearDir -FiscalYear $FiscalYear -Action 'change holdings'

        if ($Name -match "[`t`r`n]") {
            throw 'Name must not contain tabs or line breaks.'
        }
        if ($Source -match "[`t`r`n]") {
            throw 'Source must not contain tabs or line breaks.'
        }
        if ($PSBoundParameters.ContainsKey('Isin') -and $Isin -and -not (Test-LedgerIsin -Isin $Isin)) {
            throw "Invalid ISIN '$Isin'. Expected 2 letters, 9 alphanumerics and a valid check digit (e.g. SE0015811963)."
        }
        if ($PriceDate) {
            $parsed = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($PriceDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                throw "Invalid PriceDate '$PriceDate'. Expected yyyy-MM-dd."
            }
        }

        $existing = Read-LedgerHoldings -YearDir $YearDir
        $current = $existing | Where-Object { $_.Account -eq $Account -and $_.Name -eq $Name } | Select-Object -First 1

        if (-not $current) {
            foreach ($required in 'Quantity', 'Price') {
                if (-not $PSBoundParameters.ContainsKey($required)) {
                    throw "-$required is required when adding a new holding."
                }
            }
        }

        $bound = $PSBoundParameters
        $pick = {
            param($Key, $Fallback)
            if ($bound.ContainsKey($Key)) { $bound[$Key] } else { $Fallback }
        }

        $newCurrency = & $pick 'Currency' $current.Currency
        $newFxRate = & $pick 'FxRate' $current.FxRate
        # Switching to SEK resets an inherited foreign exchange rate.
        if ($PSBoundParameters.ContainsKey('Currency') -and -not $PSBoundParameters.ContainsKey('FxRate') -and
            $newCurrency.ToUpperInvariant() -ne "$($current.Currency)") {
            $newFxRate = $null
        }

        $record = New-LedgerHoldingRecord -Account $Account -Name $Name `
            -Isin (& $pick 'Isin' $current.Isin) `
            -Quantity (& $pick 'Quantity' $current.Quantity) `
            -Price (& $pick 'Price' $current.Price) `
            -Currency $newCurrency -FxRate $newFxRate `
            -PriceDate (& $pick 'PriceDate' $current.PriceDate) `
            -Source (& $pick 'Source' $current.Source) `
            -BookValue (& $pick 'BookValue' $current.BookValue)

        if ($record.Isin) {
            $dup = $existing | Where-Object { $_.Isin -eq $record.Isin -and -not ($_.Account -eq $Account -and $_.Name -eq $Name) }
            if ($dup) {
                Write-Warning "ISIN $($record.Isin) is already used by holding '$(@($dup)[0].Name)' on account $(@($dup)[0].Account)."
            }
        }
        if (-not (Get-LedgerAccount -JournalPath $JournalPath -AccountNumber $Account)) {
            Write-Warning "Account $Account is not in the chart of accounts."
        }
        if ((Get-LedgerHoldingValuationRule $Account) -eq 'Other') {
            Write-Warning "Account $Account is not a 13xx or 18xx securities account."
        }

        $rows = @($existing | Where-Object { -not ($_.Account -eq $Account -and $_.Name -eq $Name) }) + $record

        $action = if ($current) { "Update holding '$Name' on account $Account" } else { "Add holding '$Name' on account $Account" }
        $Path = Get-LedgerHoldingsPath -YearDir $YearDir
        if ($PSCmdlet.ShouldProcess($Path, $action)) {
            Write-LedgerHoldings -YearDir $YearDir -Rows $rows
        }
    }
}
