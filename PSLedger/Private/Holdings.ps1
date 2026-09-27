# Read/write helpers for a fiscal year's securities holdings (innehav).
#
# Holdings are stored as metadata in a plain-text file 'holdings.txt' in the
# fiscal year directory, UTF-8, tab-separated, with a header row:
#
#     Account<TAB>Name<TAB>Isin<TAB>Quantity<TAB>Price<TAB>Currency<TAB>FxRate<TAB>PriceDate<TAB>Source<TAB>BookValue<TAB>Cost
#     1350<TAB>Investor B<TAB>SE0015811963<TAB>500<TAB>265.40<TAB>SEK<TAB>1<TAB>2025-08-29<TAB>Nasdaq<TAB>98000<TAB>120000
#
# A holding is identified by (Account, Name). Isin, PriceDate, Source, BookValue
# (redovisat värde) and Cost (anskaffningsvärde) are optional. Price is per unit in
# Currency; FxRate is SEK per unit of Currency (1 for SEK). The market value in SEK
# is Quantity * Price * FxRate. Numbers use the invariant culture (dot as decimal
# separator). Columns are mapped by the header row, so files written before a
# column was added are still read.
#
# The absence of holdings.txt means no holdings are recorded for the fiscal year.

$script:LedgerHoldingsFileName = 'holdings.txt'
$script:LedgerHoldingsColumns = @(
    'Account', 'Name', 'Isin', 'Quantity', 'Price', 'Currency', 'FxRate', 'PriceDate', 'Source', 'BookValue', 'Cost'
)

function Get-LedgerHoldingsPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$YearDir
    )
    Join-Path $YearDir $script:LedgerHoldingsFileName
}

function ConvertTo-LedgerHoldingDecimal {
    [CmdletBinding()]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $value = [decimal]0
    if ([decimal]::TryParse($Text.Trim(), [System.Globalization.NumberStyles]::Number,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
        return $value
    }
    throw "Invalid number '$Text'."
}

function New-LedgerHoldingRecord {
    # Builds a normalised holding record and computes its SEK market value.
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Account,
        [Parameter(Mandatory)] [string]$Name,
        [AllowNull()] [AllowEmptyString()] [string]$Isin,
        [Parameter(Mandatory)] [decimal]$Quantity,
        [Parameter(Mandatory)] [decimal]$Price,
        [AllowNull()] [AllowEmptyString()] [string]$Currency,
        [AllowNull()] $FxRate,
        [AllowNull()] [AllowEmptyString()] [string]$PriceDate,
        [AllowNull()] [AllowEmptyString()] [string]$Source,
        [AllowNull()] $BookValue,
        [AllowNull()] $Cost
    )

    $currencyCode = if ([string]::IsNullOrWhiteSpace($Currency)) { 'SEK' } else { $Currency.Trim().ToUpperInvariant() }
    $rate = if ($null -eq $FxRate -or "$FxRate" -eq '') { $null } else { [decimal]$FxRate }
    if ($currencyCode -eq 'SEK') {
        if ($null -ne $rate -and $rate -ne 1) {
            throw "FxRate must be 1 for SEK holdings (got $rate)."
        }
        $rate = [decimal]1
    }
    elseif ($null -eq $rate -or $rate -le 0) {
        throw "FxRate (SEK per 1 $currencyCode) is required and must be positive for holdings in $currencyCode."
    }

    [PSCustomObject]@{
        Account     = $Account
        Name        = $Name
        Isin        = if ([string]::IsNullOrWhiteSpace($Isin)) { $null } else { $Isin.Trim().ToUpperInvariant() }
        Quantity    = $Quantity
        Price       = $Price
        Currency    = $currencyCode
        FxRate      = $rate
        PriceDate   = if ([string]::IsNullOrWhiteSpace($PriceDate)) { $null } else { $PriceDate.Trim() }
        Source      = if ([string]::IsNullOrWhiteSpace($Source)) { $null } else { $Source.Trim() }
        BookValue   = if ($null -eq $BookValue -or "$BookValue" -eq '') { $null } else { [decimal]$BookValue }
        Cost        = if ($null -eq $Cost -or "$Cost" -eq '') { $null } else { [decimal]$Cost }
        MarketValue = [Math]::Round($Quantity * $Price * $rate, 2)
    }
}

function Read-LedgerHoldings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$YearDir
    )

    $file = Get-LedgerHoldingsPath -YearDir $YearDir
    if (-not (Test-Path $file -PathType Leaf)) {
        return , @()
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $columns = $script:LedgerHoldingsColumns
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $file -Encoding UTF8)) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t"
        if ($parts[0] -eq 'Account') {
            # Header row: map columns by name so column order may evolve.
            $columns = $parts
            continue
        }

        $fields = @{}
        for ($i = 0; $i -lt $columns.Count -and $i -lt $parts.Count; $i++) {
            $fields[$columns[$i]] = $parts[$i]
        }

        try {
            if ($fields['Account'] -notmatch '^\d+$' -or [string]::IsNullOrWhiteSpace($fields['Name'])) {
                throw 'Account and Name are required.'
            }
            $quantity = ConvertTo-LedgerHoldingDecimal $fields['Quantity']
            $price = ConvertTo-LedgerHoldingDecimal $fields['Price']
            if ($null -eq $quantity -or $null -eq $price) {
                throw 'Quantity and Price are required.'
            }
            $record = New-LedgerHoldingRecord -Account $fields['Account'] -Name $fields['Name'] `
                -Isin $fields['Isin'] -Quantity $quantity -Price $price -Currency $fields['Currency'] `
                -FxRate (ConvertTo-LedgerHoldingDecimal $fields['FxRate']) -PriceDate $fields['PriceDate'] `
                -Source $fields['Source'] -BookValue (ConvertTo-LedgerHoldingDecimal $fields['BookValue']) `
                -Cost (ConvertTo-LedgerHoldingDecimal $fields['Cost'])
            $rows.Add($record) | Out-Null
        }
        catch {
            Write-Warning "Skipping malformed holding row in '$file' (line ${lineNo}): $($_.Exception.Message)"
        }
    }
    , $rows.ToArray()
}

function Write-LedgerHoldings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$YearDir,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Rows
    )

    $file = Get-LedgerHoldingsPath -YearDir $YearDir
    $list = @($Rows | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        return
    }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $fmt = { param($v) if ($null -eq $v) { '' } else { ([decimal]$v).ToString($inv) } }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($script:LedgerHoldingsColumns -join "`t") | Out-Null
    foreach ($r in ($list | Sort-Object Account, Name)) {
        $values = @(
            $r.Account, $r.Name, "$($r.Isin)", (& $fmt $r.Quantity), (& $fmt $r.Price), $r.Currency,
            (& $fmt $r.FxRate), "$($r.PriceDate)", "$($r.Source)", (& $fmt $r.BookValue), (& $fmt $r.Cost)
        )
        $lines.Add($values -join "`t") | Out-Null
    }
    Set-LedgerFileContent -Path $file -Value $lines
}

function Test-LedgerIsin {
    # Validates an ISIN (ISO 6166): 2-letter country code, 9 alphanumerics and a
    # Luhn check digit computed over the digits with letters expanded (A=10..Z=35).
    param ([string]$Isin)
    $code = "$Isin".Trim().ToUpperInvariant()
    if ($code -notmatch '^[A-Z]{2}[A-Z0-9]{9}[0-9]$') { return $false }
    $digits = -join ($code.ToCharArray() | ForEach-Object {
        if ($_ -ge [char]'A') { [int]$_ - 55 } else { [string]$_ }
    })
    $sum = 0
    $double = $false
    for ($i = $digits.Length - 1; $i -ge 0; $i--) {
        $d = [int][string]$digits[$i]
        if ($double) { $d *= 2; if ($d -gt 9) { $d -= 9 } }
        $sum += $d
        $double = -not $double
    }
    ($sum % 10) -eq 0
}

function Assert-LedgerFiscalYearOpen {
    # Throws when the fiscal year's year.txt marks it as Closed.
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$YearDir,
        [Parameter(Mandatory)] [string]$FiscalYear,
        [Parameter(Mandatory)] [string]$Action
    )
    $yearFile = Join-Path $YearDir 'year.txt'
    if (Test-Path $yearFile -PathType Leaf) {
        foreach ($line in (Get-Content $yearFile)) {
            if ($line -match '^Status:\s*Closed') {
                throw "Fiscal year $FiscalYear is Closed. Cannot $Action."
            }
        }
    }
}

function Get-LedgerHoldingValuationRule {
    # K2: financial fixed assets (13xx) are written down on a lasting decline in
    # value; current investments (18xx) follow the lower of cost and market value.
    param ([string]$Account)
    if ($Account -match '^13') { 'FixedAsset' }
    elseif ($Account -match '^18') { 'Current' }
    else { 'Other' }
}

function Get-LedgerHoldingValuation {
    <#
    .SYNOPSIS
    Compares recorded holdings with the ledger for a fiscal year.

    .DESCRIPTION
    Returns an object with:
    - Holdings    : holdings in the account range, each with Difference and
                    BelowBookValue (only when the holding has a BookValue) and
                    Reversible (the write-down that may be reversed, capped at
                    Cost; only when the holding has both BookValue and Cost).
    - Accounts    : one row per account that has holdings, comparing the summed
                    market value with the account's closing balance (including
                    value adjustment accounts in the same ten-group without
                    holdings, e.g. 1359 for 1350), and the
                    summed holding BookValue (when every holding has one).
                    AccountBalance is the account's own balance and HoldingsCost
                    the summed Cost (when every holding has one).
    - MarketValue : total market value of the holdings in the range ($null when
                    there are none).
    - HasHoldings : whether any holdings exist in the range.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [string]$FiscalYear,
        [int]$FromAccount = 0,
        [int]$ToAccount = [int]::MaxValue
    )

    $yearDir = Join-Path $JournalPath $FiscalYear
    $all = Read-LedgerHoldings -YearDir $yearDir
    $holdings = @($all | Where-Object { [int]$_.Account -ge $FromAccount -and [int]$_.Account -le $ToAccount })

    $holdingRows = foreach ($h in $holdings) {
        $diff = if ($null -ne $h.BookValue) { $h.MarketValue - $h.BookValue } else { $null }
        $row = $h.PSObject.Copy()
        $row | Add-Member -NotePropertyName Difference -NotePropertyValue $diff
        $row | Add-Member -NotePropertyName BelowBookValue -NotePropertyValue $(if ($null -ne $diff) { $diff -lt 0 } else { $null })
        $row | Add-Member -NotePropertyName Rule -NotePropertyValue (Get-LedgerHoldingValuationRule $h.Account)
        # A write-down may be reversed (återföring) up to the acquisition cost when
        # the market value has recovered above the book value.
        $reversible = if ($null -ne $h.Cost -and $null -ne $h.BookValue) {
            $cap = [Math]::Min([decimal]$h.MarketValue, [decimal]$h.Cost)
            [Math]::Max([decimal]0, [Math]::Round($cap - $h.BookValue, 2))
        } else { $null }
        $row | Add-Member -NotePropertyName Reversible -NotePropertyValue $reversible
        $row
    }

    $accountRows = @()
    if ($holdings.Count -gt 0) {
        $balances = @{}
        foreach ($row in @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)) {
            $balances[[string]$row.AccountNumber] = [decimal]$row.Balance
        }
        $holdingAccounts = @($holdings | ForEach-Object { $_.Account } | Select-Object -Unique)
        $accountRows = foreach ($group in ($holdings | Group-Object Account | Sort-Object Name)) {
            $acc = $group.Name
            $market = [decimal](($group.Group | Measure-Object -Property MarketValue -Sum).Sum)
            # Book value includes value adjustment accounts in the same ten-group
            # that carry no holdings themselves (e.g. 1359 write-downs for 1350).
            # They are attributed to the group's first holding account only.
            $prefix = $acc.Substring(0, $acc.Length - 1)
            $groupHoldingAccounts = @($holdingAccounts | Where-Object { $_.Length -eq $acc.Length -and $_.StartsWith($prefix) } | Sort-Object)
            $ownsAdjustments = $groupHoldingAccounts[0] -eq $acc
            $ledger = [decimal]0
            foreach ($key in $balances.Keys) {
                if ($key -eq $acc -or ($ownsAdjustments -and $key.Length -eq $acc.Length -and $key.StartsWith($prefix) -and $key -notin $holdingAccounts)) {
                    $ledger += $balances[$key]
                }
            }
            $withBook = @($group.Group | Where-Object { $null -ne $_.BookValue })
            $holdingsBook = if ($withBook.Count -eq $group.Count) {
                [decimal](($withBook | Measure-Object -Property BookValue -Sum).Sum)
            } else { $null }
            $withCost = @($group.Group | Where-Object { $null -ne $_.Cost })
            $holdingsCost = if ($withCost.Count -eq $group.Count) {
                [decimal](($withCost | Measure-Object -Property Cost -Sum).Sum)
            } else { $null }
            [PSCustomObject]@{
                Account           = $acc
                MarketValue       = $market
                BookValue         = $ledger
                Difference        = $market - $ledger
                BelowBookValue    = $market -lt $ledger
                HoldingsBookValue = $holdingsBook
                AccountBalance    = if ($balances.ContainsKey($acc)) { $balances[$acc] } else { [decimal]0 }
                HoldingsCost      = $holdingsCost
                Rule              = Get-LedgerHoldingValuationRule $acc
            }
        }
    }

    [PSCustomObject]@{
        Holdings    = @($holdingRows)
        Accounts    = @($accountRows)
        MarketValue = if ($holdings.Count -gt 0) { [decimal](($holdings | Measure-Object -Property MarketValue -Sum).Sum) } else { $null }
        HasHoldings = $holdings.Count -gt 0
    }
}

function Get-LedgerImpairmentHint {
    param ([string]$Rule)
    switch ($Rule) {
        'FixedAsset' { 'assess whether the decline is lasting (nedskrivning, K2)' }
        'Current' { 'lower of cost and market value applies - write down (lägsta värdets princip)' }
        default { 'assess the need for a write-down' }
    }
}

function Format-LedgerHoldingAmount {
    param ($Value)
    ([decimal]$Value).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-LedgerHoldingValuationFinding {
    # Human-readable findings for holdings/accounts whose market value is below
    # their book value. Shared by Get-LedgerShareholdingNote and Test-LedgerFiscalYear.
    param ([Parameter(Mandatory)] $Valuation)
    foreach ($a in $Valuation.Accounts) {
        if ($a.BelowBookValue) {
            "Account $($a.Account): market value $(Format-LedgerHoldingAmount $a.MarketValue) is below book value $(Format-LedgerHoldingAmount $a.BookValue) - $(Get-LedgerImpairmentHint $a.Rule)"
        }
    }
    foreach ($h in $Valuation.Holdings) {
        if ($h.BelowBookValue) {
            "Holding '$($h.Name)' ($($h.Account)): market value $(Format-LedgerHoldingAmount $h.MarketValue) is below book value $(Format-LedgerHoldingAmount $h.BookValue) - $(Get-LedgerImpairmentHint $h.Rule)"
        }
    }
}
