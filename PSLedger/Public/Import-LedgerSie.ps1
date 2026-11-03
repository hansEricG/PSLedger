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

The whole file is validated before anything is written, and the import runs
under the journal write lock. Before writing the opening balance and the
verifications, the import saves a plan in <year>/import.txt that reserves the
verification numbers. If the import is interrupted, run the same command with
the same file again: verifications already written are checked and kept, and
the rest are added with their reserved numbers. A changed SIE file stops the
recovery. The plan is removed when the import completes.

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
    [CmdletBinding(SupportsShouldProcess)]
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

        $sourceHash = Get-LedgerSha256Hex -Bytes ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).ProviderPath))
        $text = Read-SieText -Path $Path
        $records = ConvertFrom-SieText -Text $text
        $invariant = [System.Globalization.CultureInfo]::InvariantCulture

        $journalLock = $null
        $planReady = $false
        try {
            $journalLock = Enter-LedgerJournalLock -JournalPath $JournalPath
            Assert-LedgerJournalSchema -Path $JournalPath -Write

            # Everything is validated before the first write, so an invalid file
            # leaves the journal untouched.
            $createYear = $false
            $yearStart = $null
            $yearEnd = $null
            if (-not $FiscalYear) {
                $rarRecord = $records | Where-Object { $_.Tag -eq 'RAR' -and $_.Fields.Count -ge 3 -and $_.Fields[0] -eq '0' } | Select-Object -First 1
                if ($rarRecord) {
                    $yearStart = [datetime]::ParseExact($rarRecord.Fields[1], 'yyyyMMdd', $invariant)
                    $yearEnd = [datetime]::ParseExact($rarRecord.Fields[2], 'yyyyMMdd', $invariant)
                    $FiscalYear = '{0}_{1}' -f $yearStart.ToString('yyyy-MM'), $yearEnd.ToString('yyyy-MM')
                    $createYear = -not (Test-Path (Join-Path $JournalPath $FiscalYear) -PathType Container)
                    if ($createYear -and -not $Force) {
                        # Guard against creating a gap in the fiscal year series.
                        $existingYears = @(Get-LedgerFiscalYear -JournalPath $JournalPath)
                        if ($existingYears.Count -gt 0) {
                            $gapStart = $null
                            $gapEnd = $null
                            $closestBefore = $existingYears |
                                Where-Object { [datetime]$_.EndDate -lt $yearStart } |
                                Sort-Object { [datetime]$_.EndDate } | Select-Object -Last 1
                            $closestAfter = $existingYears |
                                Where-Object { [datetime]$_.StartDate -gt $yearEnd } |
                                Sort-Object { [datetime]$_.StartDate } | Select-Object -First 1

                            if ($closestBefore -and ([datetime]$closestBefore.EndDate).AddDays(1) -lt $yearStart) {
                                $gapStart = ([datetime]$closestBefore.EndDate).AddDays(1)
                                $gapEnd = $yearStart.AddDays(-1)
                            }
                            elseif ($closestAfter -and $yearEnd.AddDays(1) -lt [datetime]$closestAfter.StartDate) {
                                $gapStart = $yearEnd.AddDays(1)
                                $gapEnd = ([datetime]$closestAfter.StartDate).AddDays(-1)
                            }

                            if ($gapStart) {
                                throw "Importing fiscal year $FiscalYear would create a gap in the fiscal year series (missing $($gapStart.ToString('yyyy-MM-dd')) to $($gapEnd.ToString('yyyy-MM-dd'))). Import the missing fiscal year(s) first, or use -Force to import anyway."
                            }
                        }
                    }
                } else {
                    $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear '' -JournalPath $JournalPath
                }
            }

            $YearDir = Join-Path $JournalPath $FiscalYear
            if (-not $createYear) {
                if (-not (Test-Path $YearDir -PathType Container)) {
                    throw "Fiscal year not found: $FiscalYear"
                }
                $yearInfo = Get-LedgerFiscalYear -JournalPath $JournalPath | Where-Object Name -eq $FiscalYear | Select-Object -First 1
                if ($yearInfo -and $yearInfo.Status -eq 'Closed') {
                    throw "Fiscal year $FiscalYear is Closed. Cannot import entries."
                }
                if ($yearInfo -and $yearInfo.StartDate -and $yearInfo.EndDate) {
                    $yearStart = [datetime]$yearInfo.StartDate
                    $yearEnd = [datetime]$yearInfo.EndDate
                }
            }

            $planPath = Get-LedgerSieImportPath -JournalPath $JournalPath -FiscalYear $FiscalYear
            $plan = if (-not $createYear -and (Test-Path -LiteralPath $planPath)) { Read-LedgerSieImport -Path $planPath } else { $null }
            $ibFile = Get-LedgerOpeningBalancePath -YearDir $YearDir

            # Guard against duplicate imports: only import into an empty fiscal year.
            # An unfinished import of this file is completed instead.
            if (-not $Force -and -not $plan -and -not $createYear) {
                $ExistingVer = Get-ChildItem -Path $YearDir -Filter 'ver*.txt' -File -ErrorAction SilentlyContinue
                if ($ExistingVer -or (Test-Path $ibFile -PathType Leaf)) {
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

            $journalDimensions = @{}
            foreach ($dimension in @(Get-LedgerDimension -JournalPath $JournalPath)) {
                $journalDimensions[[int]$dimension.DimensionNumber] = $true
            }
            $knownObjects = @{}
            foreach ($obj in $sieObjects) {
                if (-not $journalDimensions.ContainsKey($obj.DimensionNumber) -and -not $sieDimensions.ContainsKey($obj.DimensionNumber)) {
                    throw "Object '$($obj.ObjectNumber)' in SIE file belongs to dimension $($obj.DimensionNumber), which is neither in the journal nor in the file."
                }
                $knownObjects["$($obj.DimensionNumber)`t$($obj.ObjectNumber)"] = $true
            }

            $existing = @{}
            foreach ($a in (Get-LedgerAccount -JournalPath $JournalPath)) {
                $existing[$a.AccountNumber] = $true
            }

            # Collect opening balances (#IB for year index 0).
            $ibRows = New-Object System.Collections.Generic.List[object]
            foreach ($rec in $records) {
                if ($rec.Tag -ne 'IB') { continue }
                if ($rec.Fields.Count -lt 3) { continue }
                if ($rec.Fields[0] -ne '0') { continue }
                $ibAmountText = $rec.Fields[2] -replace ',', '.'
                $ibAmount = [decimal]::Parse($ibAmountText, [System.Globalization.NumberStyles]::Float, $invariant)
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

            $accountsToAdd = New-Object System.Collections.Generic.List[object]
            foreach ($acct in $orderedReferenced) {
                if (-not $existing.ContainsKey($acct)) {
                    if (-not $CreateMissingAccounts) {
                        throw "Account $acct in SIE file does not exist in chart of accounts. Use -CreateMissingAccounts to add it automatically."
                    }
                    $name = if ($sieAccounts.ContainsKey($acct)) { $sieAccounts[$acct] } else { "Imported $acct" }
                    $accountsToAdd.Add([pscustomobject]@{ Number = $acct; Name = $name }) | Out-Null
                    $existing[$acct] = $true
                }
            }

            # Opening balances are imported as metadata (ib.txt), not as a verification,
            # so imported #VER records keep their source numbering (ver0001..verN).
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
                        if (-not $CreateMissingAccounts) {
                            throw "Opening balances (#IB) differ by $ibDiff and rounding account $RoundingAccount does not exist in the chart of accounts. Add it, choose another -RoundingAccount, or use -CreateMissingAccounts."
                        }
                        $roundingName = if ($sieAccounts.ContainsKey($RoundingAccount)) { $sieAccounts[$RoundingAccount] } else { 'Öres- och kronutjämning' }
                        $accountsToAdd.Add([pscustomobject]@{ Number = $RoundingAccount; Name = $roundingName }) | Out-Null
                        $existing[$RoundingAccount] = $true
                    }

                    $ibRounding = -$ibDiff
                    $ibRows.Add([PSCustomObject]@{ Account = $RoundingAccount; Amount = $ibRounding }) | Out-Null
                }
            }
            $ibLines = @(Get-LedgerOpeningBalanceLines -Rows $ibRows)
            $ibHash = if ($ibLines.Count) { Get-LedgerTextLinesHash -Lines $ibLines } else { $null }

            $entries = New-Object System.Collections.Generic.List[object]
            foreach ($rec in $records) {
                if ($rec.Tag -ne 'VER') { continue }
                if ($rec.Fields.Count -lt 3) { continue }

                $verDesc = if ($rec.Fields.Count -ge 4 -and $rec.Fields[3] -ne '') { $rec.Fields[3] } else { '(No description)' }
                $date = [datetime]::ParseExact($rec.Fields[2], 'yyyyMMdd', $invariant)
                if ($yearStart -and $yearEnd -and ($date -lt $yearStart -or $date -gt $yearEnd)) {
                    throw "Verification dated $($date.ToString('yyyy-MM-dd')) ('$verDesc') is outside fiscal year $FiscalYear ($($yearStart.ToString('yyyy-MM-dd')) to $($yearEnd.ToString('yyyy-MM-dd')))."
                }

                $rows = foreach ($t in $rec.Transactions) {
                    $amountText = $t.Fields[1] -replace ',', '.'
                    $amount = [decimal]::Parse($amountText, [System.Globalization.NumberStyles]::Float, $invariant)
                    $rowHash = @{ Account = $t.Fields[0]; Amount = $amount }
                    # Parse object list from TRANS (pairs: dimNum objId)
                    if ($t.Objects -and $t.Objects.Count -ge 2) {
                        $objHash = @{}
                        for ($oi = 0; $oi -lt $t.Objects.Count; $oi += 2) {
                            if ($oi + 1 -lt $t.Objects.Count) {
                                $objHash[[int]$t.Objects[$oi]] = $t.Objects[$oi + 1]
                            }
                        }
                        foreach ($dimNum in $objHash.Keys) {
                            if (-not $journalDimensions.ContainsKey($dimNum) -and -not $sieDimensions.ContainsKey($dimNum)) {
                                throw "Dimension $dimNum does not exist."
                            }
                            if (-not $knownObjects.ContainsKey("$dimNum`t$($objHash[$dimNum])") -and
                                -not (Get-LedgerObject -JournalPath $JournalPath -DimensionNumber $dimNum -ObjectNumber $objHash[$dimNum])) {
                                throw "Object '$($objHash[$dimNum])' does not exist in dimension $dimNum."
                            }
                        }
                        if ($objHash.Count -gt 0) { $rowHash['Objects'] = $objHash }
                    }
                    $rowHash
                }
                Assert-LedgerEntryAmounts -Rows @($rows)
                $entries.Add([pscustomobject]@{ Date = $date; Description = $verDesc; Rows = @($rows) }) | Out-Null
            }

            if (-not $PSCmdlet.ShouldProcess($Path, 'Import SIE file')) {
                return
            }

            if ($createYear) {
                New-LedgerFiscalYear -JournalPath $JournalPath -StartDate $yearStart -EndDate $yearEnd
            }
            foreach ($dimNum in ($sieDimensions.Keys | Sort-Object)) {
                if (-not $journalDimensions.ContainsKey($dimNum)) {
                    Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber $dimNum -Name $sieDimensions[$dimNum]
                }
            }
            foreach ($obj in $sieObjects) {
                $existObj = Get-LedgerObject -JournalPath $JournalPath -DimensionNumber $obj.DimensionNumber -ObjectNumber $obj.ObjectNumber
                if (-not $existObj) {
                    Add-LedgerObject -JournalPath $JournalPath -DimensionNumber $obj.DimensionNumber -ObjectNumber $obj.ObjectNumber -Name $obj.Name
                }
            }
            foreach ($account in $accountsToAdd) {
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $account.Number -AccountName $account.Name
            }

            # The plan binds the import to this file and reserves its verification numbers.
            $operationId = if ($plan) { $plan.OperationId } else { [guid]::NewGuid() }
            foreach ($entry in $entries) {
                $lines = @(Get-LedgerVerificationLines -JournalPath $JournalPath -FiscalYear $FiscalYear `
                        -Date $entry.Date -Description (ConvertTo-LedgerTextField $entry.Description) -Rows $entry.Rows -OperationId $operationId)
                $entry | Add-Member -NotePropertyName Hash -NotePropertyValue (Get-LedgerTextLinesHash -Lines $lines)
            }
            $verificationsHash = Get-LedgerTextLinesHash -Lines @($entries | ForEach-Object Hash)

            if ($plan) {
                if ($plan.SourceHash -ne $sourceHash -or $plan.VerificationsHash -ne $verificationsHash -or
                    $plan.VerificationCount -ne $entries.Count -or [string]$plan.OpeningBalanceHash -ne [string]$ibHash) {
                    throw "Fiscal year $FiscalYear has an unfinished SIE import of another file or other options; the SIE file or the journal has changed since its import plan was saved. Recovery stopped. Repeat Import-LedgerSie with the original file and options."
                }
            }
            else {
                $priorIbHash = $null
                if ($ibHash -and (Test-Path -LiteralPath $ibFile -PathType Leaf)) {
                    $currentIbHash = Get-LedgerContentHash -Path $ibFile
                    if ($currentIbHash -ne $ibHash) { $priorIbHash = $currentIbHash }
                }
                $plan = [pscustomobject]@{
                    OperationId             = $operationId
                    FiscalYear              = $FiscalYear
                    SourceHash              = $sourceHash
                    FirstVerification       = Get-LedgerNextVerificationNumber -JournalPath $JournalPath -FiscalYear $FiscalYear
                    VerificationCount       = $entries.Count
                    VerificationsHash       = $verificationsHash
                    OpeningBalanceHash      = $ibHash
                    PriorOpeningBalanceHash = $priorIbHash
                }
                Save-LedgerSieImport -Path $planPath -Operation $plan
            }
            $planReady = $true

            $lastNumber = $plan.FirstVerification + $plan.VerificationCount - 1
            $check = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
            # An interruption can leave the planned ib.txt written but not yet sealed.
            $plannedIbWritten = $ibHash -and (Test-Path -LiteralPath $ibFile -PathType Leaf) -and
                (Get-LedgerContentHash -Path $ibFile) -eq $ibHash
            $issues = @($check.Issues | Where-Object {
                    -not ($_.Kind -eq 'Verification' -and $_.Problem -eq 'Unsealed' -and
                        [int]$_.Key -ge $plan.FirstVerification -and [int]$_.Key -le $lastNumber) -and
                    -not ($plannedIbWritten -and $_.Kind -eq 'Metadata' -and $_.Key -eq 'ib.txt')
                })
            if ($issues.Count) {
                throw "SIE import cannot continue because of integrity issues. Run Test-LedgerIntegrity and resolve them first: $($issues.Detail -join ' ')"
            }

            if ($ibHash) {
                $currentIbHash = if (Test-Path -LiteralPath $ibFile -PathType Leaf) { Get-LedgerContentHash -Path $ibFile } else { $null }
                if ($currentIbHash -ne $ibHash) {
                    if ($currentIbHash -and $currentIbHash -ne $plan.PriorOpeningBalanceHash) {
                        throw "Opening balance '$ibFile' has changed since the SIE import plan was saved. Recovery stopped without rewriting it."
                    }
                    Write-LedgerOpeningBalance -YearDir $YearDir -Rows $ibRows
                }
                Register-LedgerYearMetadata -YearDir $YearDir -Name 'ib.txt'
            }

            $state = Get-LedgerIntegrityState -Chain (Read-LedgerIntegrityChain -YearDir $YearDir)
            for ($index = 0; $index -lt $entries.Count; $index++) {
                $entry = $entries[$index]
                $number = $plan.FirstVerification + $index
                $verificationPath = Join-Path $YearDir ('ver' + $number.ToString('0000') + '.txt')
                if (Test-Path -LiteralPath $verificationPath) {
                    Assert-LedgerInvoicePostingVerification -Path $verificationPath -Label 'SIE import' -Operation ([pscustomobject]@{
                            OperationId = $plan.OperationId; VerificationHash = $entry.Hash
                        })
                    if (-not $state.Verifications.Contains("$number")) {
                        Register-LedgerIntegrityItem -YearDir $YearDir -Kind Verification -Key "$number" -Path $verificationPath
                    }
                }
                else {
                    Write-LedgerVerification -JournalPath $JournalPath -FiscalYear $FiscalYear -Date $entry.Date `
                        -Description $entry.Description -Rows $entry.Rows -OperationId $plan.OperationId `
                        -ReservedNumber $number -Confirm:$false
                }
            }

            # The plan only marks an unfinished import; a completed one needs no reservation.
            Remove-Item -LiteralPath $planPath -Force
        }
        catch {
            if (-not $planReady) { throw }
            throw [System.InvalidOperationException]::new(
                "SIE import of '$Path' into fiscal year $FiscalYear was interrupted. Repeat Import-LedgerSie with the same file and options to complete it safely. $($_.Exception.Message)",
                $_.Exception)
        }
        finally { Exit-LedgerJournalLock -Lock $journalLock }

        [PSCustomObject]@{
            Path                   = $Path
            ImportedEntries        = $entries.Count
            ImportedOpeningBalance = ($ibRows.Count -gt 0)
            OpeningBalanceRounding = $ibRounding
            ImportedAccounts       = if ($CreateMissingAccounts) { ($referenced.Keys | Where-Object { $sieAccounts.ContainsKey($_) }).Count } else { 0 }
        }
    }
}