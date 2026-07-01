<#
.SYNOPSIS
Imports verifications from a SIE 4 file into a journal.

.DESCRIPTION
Reads a SIE 4 file (typically a SIE 4E export from another system or a SIE 4I
file from a supplier) and adds its verifications to the target journal. The
file is validated with Test-LedgerSie first; any errors abort the import before
any file is written. Accounts referenced in the SIE file must already exist in
the chart of accounts unless -CreateMissingAccounts is specified.

If -FiscalYear is not specified, the fiscal year is determined from the #RAR 0
record in the SIE file. If that fiscal year does not already exist in the
journal it is created automatically.

To avoid duplicating entries, the import is refused if the target fiscal year
already contains verifications; import into a new or empty fiscal year, or use
-Force to override.

When the fiscal year is auto-created from #RAR 0, the import is also refused if
it would leave a gap in the journal's fiscal year series (i.e. it is not
contiguous with the existing years). Import the missing year(s) first, or use
-Force to override.

Opening balances (#IB records for the current year, year index 0) are imported
as the fiscal year's opening balance metadata (ib.txt), not as a verification, so
imported #VER records keep their source numbering (ver0001..verN). If the opening
balances do not sum to zero by a small rounding difference (within
-RoundingTolerance), the difference is posted to -RoundingAccount; a larger
difference aborts the import.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12') to import into.
If omitted, the fiscal year is derived from the SIE file's #RAR 0 record
and created automatically if it does not exist.

.PARAMETER Path
Path to the SIE file to import.

.PARAMETER CreateMissingAccounts
If specified, accounts referenced in #TRANS rows that are not yet in the
chart of accounts are added automatically using the names from the SIE file's
#KONTO records. This also allows the rounding account to be created if needed.

.PARAMETER RoundingAccount
The account used to absorb a small rounding difference (öresdifferens) in the
opening balances (#IB) so the opening balance entry balances. Defaults to BAS
account '3740' (Öres- och kronutjämning).

.PARAMETER RoundingTolerance
The maximum absolute opening-balance difference (in the journal's currency) that
is treated as rounding and posted to -RoundingAccount. Differences larger than
this abort the import. Defaults to 1.00.

.PARAMETER Force
By default the import is refused if the target fiscal year already contains
verifications (to prevent accidentally importing the same SIE file twice) or if
auto-creating the fiscal year would leave a gap in the fiscal year series.
Specify -Force to bypass these guards and import anyway.

.EXAMPLE
Import-LedgerSie -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Path .\fromfortnox.se

Imports verifications from a SIE file into an existing fiscal year.

.EXAMPLE
Import-LedgerSie -JournalPath .\NyFirma.ledger -FiscalYear '2024-01_2024-12' -Path .\export.se -CreateMissingAccounts

Imports into a journal whose chart of accounts is incomplete, adding any
referenced accounts on the fly.
#>
function Import-LedgerSie {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$FiscalYear,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [switch]$CreateMissingAccounts,

        [string]$RoundingAccount = '3740',

        [decimal]$RoundingTolerance = 1.00,

        [switch]$Force
    )
    begin {
        $ExplicitFiscalYear = $FiscalYear
    }
    process {
        $FiscalYear = $ExplicitFiscalYear
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

        if (-not (Test-Path $JournalPath -PathType Container)) {
            throw "Journal not found: $JournalPath"
        }

        $validation = Test-LedgerSie -Path $Path
        if (-not $validation.IsValid) {
            $msg = "SIE file is invalid: " + ($validation.Errors -join '; ')
            throw $msg
        }

        $text = Read-SieText -Path $Path
        $records = ConvertFrom-SieText -Text $text

        # Resolve fiscal year: use parameter, fall back to #RAR 0, then latest existing
        if (-not $FiscalYear) {
            $rarRecord = $records | Where-Object { $_.Tag -eq 'RAR' -and $_.Fields.Count -ge 3 -and $_.Fields[0] -eq '0' } | Select-Object -First 1
            if ($rarRecord) {
                $rarStart = [datetime]::ParseExact($rarRecord.Fields[1], 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
                $rarEnd = [datetime]::ParseExact($rarRecord.Fields[2], 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
                $FiscalYear = '{0}_{1}' -f $rarStart.ToString('yyyy-MM'), $rarEnd.ToString('yyyy-MM')

                # Create fiscal year if it does not exist
                $YearDir = Join-Path $JournalPath $FiscalYear
                if (-not (Test-Path $YearDir -PathType Container)) {
                    # Guard against creating a gap in the fiscal year series.
                    if (-not $Force) {
                        $existingYears = @(Get-LedgerFiscalYear -JournalPath $JournalPath)
                        if ($existingYears.Count -gt 0) {
                            $gapStart = $null
                            $gapEnd = $null
                            $closestBefore = $existingYears |
                                Where-Object { [datetime]$_.EndDate -lt $rarStart } |
                                Sort-Object { [datetime]$_.EndDate } | Select-Object -Last 1
                            $closestAfter = $existingYears |
                                Where-Object { [datetime]$_.StartDate -gt $rarEnd } |
                                Sort-Object { [datetime]$_.StartDate } | Select-Object -First 1

                            if ($closestBefore -and ([datetime]$closestBefore.EndDate).AddDays(1) -lt $rarStart) {
                                $gapStart = ([datetime]$closestBefore.EndDate).AddDays(1)
                                $gapEnd = $rarStart.AddDays(-1)
                            }
                            elseif ($closestAfter -and $rarEnd.AddDays(1) -lt [datetime]$closestAfter.StartDate) {
                                $gapStart = $rarEnd.AddDays(1)
                                $gapEnd = ([datetime]$closestAfter.StartDate).AddDays(-1)
                            }

                            if ($gapStart) {
                                throw "Importing fiscal year $FiscalYear would create a gap in the fiscal year series (missing $($gapStart.ToString('yyyy-MM-dd')) to $($gapEnd.ToString('yyyy-MM-dd'))). Import the missing fiscal year(s) first, or use -Force to import anyway."
                            }
                        }
                    }
                    New-LedgerFiscalYear -JournalPath $JournalPath -StartDate $rarStart -EndDate $rarEnd
                }
            } else {
                $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear '' -JournalPath $JournalPath
            }
        }

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        $YearFile = Join-Path $YearDir 'year.txt'
        if (Test-Path $YearFile) {
            foreach ($Line in (Get-Content $YearFile)) {
                if ($Line -match '^Status:\s*Closed') {
                    throw "Fiscal year $FiscalYear is Closed. Cannot import entries."
                }
            }
        }

        # Guard against duplicate imports: only import into an empty fiscal year.
        if (-not $Force) {
            $ExistingVer = Get-ChildItem -Path $YearDir -Filter 'ver*.txt' -File -ErrorAction SilentlyContinue
            $ExistingIb = Get-LedgerOpeningBalancePath -YearDir $YearDir
            if ($ExistingVer -or (Test-Path $ExistingIb -PathType Leaf)) {
                throw "Fiscal year $FiscalYear already contains verifications or an opening balance. Import only into an empty fiscal year to avoid duplicating entries. Use -Force to import anyway."
            }
        }

        $sieAccountOrder = New-Object System.Collections.Generic.List[string]
        $sieAccounts = @{}
        $sieDimensions = @{}
        $sieObjects = New-Object System.Collections.Generic.List[object]
        foreach ($rec in $records) {
            if ($rec.Tag -eq 'KONTO' -and $rec.Fields.Count -ge 1) {
                $name = if ($rec.Fields.Count -ge 2) { $rec.Fields[1] } else { '' }
                if (-not $sieAccounts.ContainsKey($rec.Fields[0])) {
                    $sieAccountOrder.Add($rec.Fields[0]) | Out-Null
                }
                $sieAccounts[$rec.Fields[0]] = $name
            }
            elseif ($rec.Tag -eq 'DIM' -and $rec.Fields.Count -ge 2) {
                $sieDimensions[[int]$rec.Fields[0]] = $rec.Fields[1]
            }
            elseif ($rec.Tag -eq 'OBJEKT' -and $rec.Fields.Count -ge 3) {
                $sieObjects.Add([PSCustomObject]@{
                    DimensionNumber = [int]$rec.Fields[0]
                    ObjectNumber    = $rec.Fields[1]
                    Name            = $rec.Fields[2]
                }) | Out-Null
            }
        }

        # Import dimensions and objects
        foreach ($dimNum in ($sieDimensions.Keys | Sort-Object)) {
            $existDim = Get-LedgerDimension -JournalPath $JournalPath -DimensionNumber $dimNum
            if (-not $existDim) {
                Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber $dimNum -Name $sieDimensions[$dimNum]
            }
        }
        foreach ($obj in $sieObjects) {
            $existObj = Get-LedgerObject -JournalPath $JournalPath -DimensionNumber $obj.DimensionNumber -ObjectNumber $obj.ObjectNumber
            if (-not $existObj) {
                Add-LedgerObject -JournalPath $JournalPath -DimensionNumber $obj.DimensionNumber -ObjectNumber $obj.ObjectNumber -Name $obj.Name
            }
        }

        $existing = @{}
        foreach ($a in (Get-LedgerAccount -JournalPath $JournalPath)) {
            $existing[$a.AccountNumber] = $true
        }

        # Collect opening balances (#IB for year index 0) so they can be imported
        # as an opening balance verification (ingående balans).
        $ibRows = New-Object System.Collections.Generic.List[object]
        foreach ($rec in $records) {
            if ($rec.Tag -ne 'IB') { continue }
            if ($rec.Fields.Count -lt 3) { continue }
            if ($rec.Fields[0] -ne '0') { continue }
            $ibAmountText = $rec.Fields[2] -replace ',', '.'
            $ibAmount = [decimal]::Parse($ibAmountText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture)
            if ($ibAmount -eq 0) { continue }
            $ibRows.Add([PSCustomObject]@{ Account = $rec.Fields[1]; Amount = $ibAmount }) | Out-Null
        }

        $referenced = @{}
        foreach ($rec in $records) {
            if ($rec.Tag -ne 'VER') { continue }
            foreach ($t in $rec.Transactions) {
                if ($t.Fields.Count -ge 1) { $referenced[$t.Fields[0]] = $true }
            }
        }
        foreach ($r in $ibRows) { $referenced[$r.Account] = $true }

        # Walk accounts in SIE file order so the imported chart preserves order.
        $orderedReferenced = New-Object System.Collections.Generic.List[string]
        foreach ($acct in $sieAccountOrder) {
            if ($referenced.ContainsKey($acct)) { $orderedReferenced.Add($acct) | Out-Null }
        }
        foreach ($acct in $referenced.Keys) {
            if (-not $sieAccounts.ContainsKey($acct)) { $orderedReferenced.Add($acct) | Out-Null }
        }

        foreach ($acct in $orderedReferenced) {
            if (-not $existing.ContainsKey($acct)) {
                if ($CreateMissingAccounts) {
                    $name = if ($sieAccounts.ContainsKey($acct)) { $sieAccounts[$acct] } else { "Imported $acct" }
                    Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $acct -AccountName $name
                    $existing[$acct] = $true
                }
                else {
                    throw "Account $acct in SIE file does not exist in chart of accounts. Use -CreateMissingAccounts to add it automatically."
                }
            }
        }

        # Import opening balances as metadata (ib.txt), not as a verification, so
        # imported #VER records keep their source numbering (ver0001..verN).
        $ibRounding = [decimal]0
        if ($ibRows.Count -gt 0) {
            # Sum as decimal (Measure-Object -Sum returns a double and introduces
            # floating-point noise on otherwise exact 2-decimal amounts).
            $ibSum = [decimal]0
            foreach ($r in $ibRows) { $ibSum += $r.Amount }
            $ibDiff = [Math]::Round($ibSum, 2)

            if ($ibDiff -ne 0) {
                if ([Math]::Abs($ibDiff) -gt $RoundingTolerance) {
                    throw "Opening balances (#IB) do not balance. Sum of rows: $ibDiff (must be 0, tolerance ±$RoundingTolerance). Correct the source file or raise -RoundingTolerance."
                }

                # Small rounding difference (öresdifferens): post it to the rounding account.
                if (-not $existing.ContainsKey($RoundingAccount)) {
                    if ($CreateMissingAccounts) {
                        $roundingName = if ($sieAccounts.ContainsKey($RoundingAccount)) { $sieAccounts[$RoundingAccount] } else { 'Öres- och kronutjämning' }
                        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $RoundingAccount -AccountName $roundingName
                        $existing[$RoundingAccount] = $true
                    }
                    else {
                        throw "Opening balances (#IB) differ by $ibDiff and rounding account $RoundingAccount does not exist in the chart of accounts. Add it, choose another -RoundingAccount, or use -CreateMissingAccounts."
                    }
                }

                $ibRounding = -$ibDiff
                $ibRows.Add([PSCustomObject]@{ Account = $RoundingAccount; Amount = $ibRounding }) | Out-Null
            }

            Write-LedgerOpeningBalance -YearDir $YearDir -Rows $ibRows
        }

        $imported = 0
        foreach ($rec in $records) {
            if ($rec.Tag -ne 'VER') { continue }
            if ($rec.Fields.Count -lt 3) { continue }

            $verDate = $rec.Fields[2]
            $verDesc = if ($rec.Fields.Count -ge 4 -and $rec.Fields[3] -ne '') { $rec.Fields[3] } else { '(No description)' }
            $date = [datetime]::ParseExact($verDate, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)

            $rows = foreach ($t in $rec.Transactions) {
                $amountText = $t.Fields[1] -replace ',', '.'
                $amount = [decimal]::Parse($amountText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture)
                $rowHash = @{ Account = $t.Fields[0]; Amount = $amount }
                # Parse object list from TRANS (pairs: dimNum objId)
                if ($t.Objects -and $t.Objects.Count -ge 2) {
                    $objHash = @{}
                    for ($oi = 0; $oi -lt $t.Objects.Count; $oi += 2) {
                        if ($oi + 1 -lt $t.Objects.Count) {
                            $objHash[[int]$t.Objects[$oi]] = $t.Objects[$oi + 1]
                        }
                    }
                    if ($objHash.Count -gt 0) { $rowHash['Objects'] = $objHash }
                }
                $rowHash
            }

            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date $date -Description $verDesc -Rows @($rows)
            $imported++
        }

        [PSCustomObject]@{
            Path                   = $Path
            ImportedEntries        = $imported
            ImportedOpeningBalance = ($ibRows.Count -gt 0)
            OpeningBalanceRounding = $ibRounding
            ImportedAccounts       = if ($CreateMissingAccounts) { ($referenced.Keys | Where-Object { $sieAccounts.ContainsKey($_) }).Count } else { 0 }
        }
    }
}

