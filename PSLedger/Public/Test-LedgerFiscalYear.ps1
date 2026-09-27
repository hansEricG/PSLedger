<#
.SYNOPSIS
Runs year-end readiness checks (bokslutskontroll) on a fiscal year.

.DESCRIPTION
Validates that a fiscal year is ready to be closed and returns one result object
per check with Check, Status ('Pass', 'Fail', 'Warning' or 'Info') and Detail
properties. Nothing is modified. The checks are:

- VerificationsBalance  - every verification's rows sum to zero (Fail).
- VerificationNumbering  - verification numbers are contiguous from 1, no gaps (Fail).
- NoEmptyVerifications  - every verification has at least two rows (Fail).
- LedgerBalances  - all closing balances across every account sum to zero (Fail).
- OpeningBalanceBalances  - the opening balance (ib.txt) itself sums to zero (Warning).
- OpeningBalanceMatchesPrevious  - the opening balance reconciles with the previous
  fiscal year's closing balance sheet, including its carried net result (Warning;
  Info when there is no previous fiscal year).
- HoldingsValuation  - no account or holding recorded with Set-LedgerHolding has a
  market value below its book value (Warning). For 13xx accounts the decline must
  be assessed as lasting or not; for 18xx accounts the lower of cost and market
  value applies. Info when there is no holdings.txt.
- HoldingsReconcile  - the summed BookValue of an account's holdings (when all have
  one) matches the ledger balance, the summed Cost (when all have one) matches the
  account's own balance (e.g. 1350 without 1359), and every PriceDate is the
  balance date (Warning; Info when there is no holdings.txt).
- HoldingsReversal  - no earlier write-down may be reversed: a holding with both
  BookValue and Cost whose market value has recovered above its book value is
  flagged for återföring (Warning; Info when no holding records a Cost).

VAT reconciliation is not yet included. Use `Where-Object { $_.Status -eq 'Fail' }`
to gate an automated close on the hard checks.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.EXAMPLE
Test-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Returns one object per check describing the year-end readiness of 2024.

.EXAMPLE
$failures = Test-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' |
    Where-Object { $_.Status -eq 'Fail' }
if (-not $failures) { Close-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' }

Closes the year only when no hard check fails.
#>
function Test-LedgerFiscalYear {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        function New-CheckResult {
            param ([string]$Check, [string]$Status, [string]$Detail)
            [PSCustomObject]@{
                FiscalYear = $FiscalYear
                Check      = $Check
                Status     = $Status
                Detail     = $Detail
            }
        }

        $Entries = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear)

        # --- VerificationsBalance ---
        $Unbalanced = foreach ($Entry in $Entries) {
            $Sum = ($Entry.Rows | Measure-Object -Property Amount -Sum).Sum
            if ([Math]::Round([decimal]$Sum, 2) -ne 0) {
                'ver{0:0000} (sum {1})' -f $Entry.VerificationNumber, ([Math]::Round([decimal]$Sum, 2))
            }
        }
        $Unbalanced = @($Unbalanced)
        if ($Unbalanced.Count -gt 0) {
            New-CheckResult 'VerificationsBalance' 'Fail' ("Unbalanced verifications: " + ($Unbalanced -join ', '))
        }
        else {
            New-CheckResult 'VerificationsBalance' 'Pass' "All $($Entries.Count) verification(s) balance."
        }

        # --- VerificationNumbering ---
        $Numbers = @($Entries | ForEach-Object { $_.VerificationNumber } | Sort-Object)
        if ($Numbers.Count -eq 0) {
            New-CheckResult 'VerificationNumbering' 'Info' 'No verifications in this fiscal year.'
        }
        else {
            $Max = ($Numbers | Measure-Object -Maximum).Maximum
            $Present = @{}
            foreach ($n in $Numbers) { $Present[$n] = $true }
            $Missing = for ($i = 1; $i -le $Max; $i++) { if (-not $Present.ContainsKey($i)) { $i } }
            $Missing = @($Missing)
            if ($Missing.Count -gt 0) {
                $MissingNames = $Missing | ForEach-Object { 'ver{0:0000}' -f $_ }
                New-CheckResult 'VerificationNumbering' 'Fail' ("Missing verification number(s): " + ($MissingNames -join ', '))
            }
            else {
                New-CheckResult 'VerificationNumbering' 'Pass' "Verifications numbered 1..$Max with no gaps."
            }
        }

        # --- NoEmptyVerifications ---
        $Empty = foreach ($Entry in $Entries) {
            if (@($Entry.Rows).Count -lt 2) {
                'ver{0:0000}' -f $Entry.VerificationNumber
            }
        }
        $Empty = @($Empty)
        if ($Empty.Count -gt 0) {
            New-CheckResult 'NoEmptyVerifications' 'Fail' ("Verifications with fewer than two rows: " + ($Empty -join ', '))
        }
        else {
            New-CheckResult 'NoEmptyVerifications' 'Pass' 'All verifications have at least two rows.'
        }

        # --- LedgerBalances ---
        $Balance = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)
        $Total = ($Balance | Measure-Object -Property Balance -Sum).Sum
        $Total = [Math]::Round([decimal]$Total, 2)
        if ($Total -ne 0) {
            New-CheckResult 'LedgerBalances' 'Fail' "Closing balances do not net to zero (sum $Total)."
        }
        else {
            New-CheckResult 'LedgerBalances' 'Pass' 'All closing balances net to zero.'
        }

        # --- OpeningBalanceBalances ---
        # Read-LedgerOpeningBalance already returns an array (comma-protected), so
        # assign directly without @() which would double-wrap it.
        $Opening = Read-LedgerOpeningBalance -YearDir $YearDir
        if (@($Opening).Count -eq 0) {
            New-CheckResult 'OpeningBalanceBalances' 'Info' 'No opening balance (ib.txt) for this fiscal year.'
        }
        else {
            $OpeningSum = ($Opening | Measure-Object -Property Amount -Sum).Sum
            $OpeningSum = [Math]::Round([decimal]$OpeningSum, 2)
            if ($OpeningSum -ne 0) {
                New-CheckResult 'OpeningBalanceBalances' 'Warning' "Opening balance does not net to zero (sum $OpeningSum)."
            }
            else {
                New-CheckResult 'OpeningBalanceBalances' 'Pass' 'Opening balance nets to zero.'
            }
        }

        # --- OpeningBalanceMatchesPrevious ---
        $AllYears = @(Get-LedgerFiscalYear -JournalPath $JournalPath | Sort-Object StartDate)
        $Names = @($AllYears | ForEach-Object { $_.Name })
        $Index = $Names.IndexOf($FiscalYear)
        if ($Index -lt 1) {
            New-CheckResult 'OpeningBalanceMatchesPrevious' 'Info' 'No previous fiscal year to reconcile against.'
        }
        else {
            $PrevName = $Names[$Index - 1]
            $PrevBalance = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $PrevName)

            # Expected opening = previous closing balance-sheet accounts (1xxx/2xxx),
            # plus the previous year's net result carried to the equity result
            # account (this mirrors Copy-LedgerOpeningBalance; the account depends on
            # CompanyType, AB -> 2099 / EF -> 2019, and the result term is zero once
            # it is booked).
            $Expected = @{}
            foreach ($Row in $PrevBalance) {
                if ($Row.AccountNumber -match '^[12]') {
                    $Expected[$Row.AccountNumber] = [Math]::Round([decimal]$Row.Balance, 2)
                }
            }
            $PrevResult = ($PrevBalance | Where-Object { $_.AccountNumber -match '^[3-8]' } |
                Measure-Object -Property Balance -Sum).Sum
            $PrevResult = [Math]::Round([decimal]$PrevResult, 2)
            if ($PrevResult -ne 0) {
                $ResultAccount = Resolve-LedgerResultCarryAccount -JournalPath $JournalPath
                $CurrentResult = if ($Expected.ContainsKey($ResultAccount)) { $Expected[$ResultAccount] } else { [decimal]0 }
                $Expected[$ResultAccount] = [Math]::Round($CurrentResult + $PrevResult, 2)
            }

            $OpeningMap = @{}
            foreach ($Row in $Opening) {
                $OpeningMap[$Row.Account] = [Math]::Round([decimal]$Row.Amount, 2)
            }

            $Accounts = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($k in $Expected.Keys) { [void]$Accounts.Add($k) }
            foreach ($k in $OpeningMap.Keys) { [void]$Accounts.Add($k) }

            $Mismatches = foreach ($Acc in ($Accounts | Sort-Object)) {
                $Exp = if ($Expected.ContainsKey($Acc)) { $Expected[$Acc] } else { [decimal]0 }
                $Got = if ($OpeningMap.ContainsKey($Acc)) { $OpeningMap[$Acc] } else { [decimal]0 }
                if ($Exp -ne $Got) {
                    "$Acc (expected $Exp, got $Got)"
                }
            }
            $Mismatches = @($Mismatches)
            if ($Mismatches.Count -gt 0) {
                New-CheckResult 'OpeningBalanceMatchesPrevious' 'Warning' ("Opening balance does not match $PrevName closing: " + ($Mismatches -join '; '))
            }
            else {
                New-CheckResult 'OpeningBalanceMatchesPrevious' 'Pass' "Opening balance reconciles with $PrevName closing."
            }
        }

        # --- HoldingsValuation / HoldingsReconcile ---
        $Valuation = Get-LedgerHoldingValuation -JournalPath $JournalPath -FiscalYear $FiscalYear
        if (-not $Valuation.HasHoldings) {
            New-CheckResult 'HoldingsValuation' 'Info' 'No holdings (holdings.txt) for this fiscal year.'
            New-CheckResult 'HoldingsReconcile' 'Info' 'No holdings (holdings.txt) for this fiscal year.'
            New-CheckResult 'HoldingsReversal' 'Info' 'No holdings (holdings.txt) for this fiscal year.'
        }
        else {
            $Findings = @(Get-LedgerHoldingValuationFinding -Valuation $Valuation)
            if ($Findings.Count -gt 0) {
                New-CheckResult 'HoldingsValuation' 'Warning' ($Findings -join '; ')
            }
            else {
                New-CheckResult 'HoldingsValuation' 'Pass' 'No holding has a market value below its book value.'
            }

            $YearInfo = $AllYears | Where-Object { $_.Name -eq $FiscalYear } | Select-Object -First 1
            $BalanceDate = if ($YearInfo -and $YearInfo.EndDate) { ([datetime]$YearInfo.EndDate).ToString('yyyy-MM-dd') } else { $null }

            $Issues = @(
                foreach ($Acc in $Valuation.Accounts) {
                    if ($null -ne $Acc.HoldingsBookValue -and [Math]::Round($Acc.HoldingsBookValue, 2) -ne [Math]::Round($Acc.BookValue, 2)) {
                        "Account $($Acc.Account): holdings book value $($Acc.HoldingsBookValue) does not match the ledger balance $($Acc.BookValue)"
                    }
                    if ($null -ne $Acc.HoldingsCost -and [Math]::Round($Acc.HoldingsCost, 2) -ne [Math]::Round($Acc.AccountBalance, 2)) {
                        "Account $($Acc.Account): holdings cost $($Acc.HoldingsCost) does not match the account balance $($Acc.AccountBalance)"
                    }
                }
                foreach ($H in $Valuation.Holdings) {
                    if ($BalanceDate -and $H.PriceDate -and $H.PriceDate -ne $BalanceDate) {
                        "Holding '$($H.Name)' ($($H.Account)): price date $($H.PriceDate) is not the balance date $BalanceDate"
                    }
                }
            )
            if ($Issues.Count -gt 0) {
                New-CheckResult 'HoldingsReconcile' 'Warning' ($Issues -join '; ')
            }
            else {
                New-CheckResult 'HoldingsReconcile' 'Pass' 'Holdings reconcile with the ledger.'
            }

            $WithCost = @($Valuation.Holdings | Where-Object { $null -ne $_.Reversible })
            $Reversals = @($WithCost | Where-Object { $_.Reversible -gt 0 } | ForEach-Object {
                    "Holding '$($_.Name)' ($($_.Account)): market value $(Format-LedgerHoldingAmount $_.MarketValue) exceeds book value $(Format-LedgerHoldingAmount $_.BookValue) - up to $(Format-LedgerHoldingAmount $_.Reversible) of an earlier write-down may be reversed (återföring, Add-LedgerImpairment -Reverse)"
                })
            if ($WithCost.Count -eq 0) {
                New-CheckResult 'HoldingsReversal' 'Info' 'No holding records a Cost (anskaffningsvärde).'
            }
            elseif ($Reversals.Count -gt 0) {
                New-CheckResult 'HoldingsReversal' 'Warning' ($Reversals -join '; ')
            }
            else {
                New-CheckResult 'HoldingsReversal' 'Pass' 'No write-down to reverse.'
            }
        }
    }
}
