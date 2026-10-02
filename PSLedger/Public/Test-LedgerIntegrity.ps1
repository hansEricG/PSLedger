<#
.SYNOPSIS
Checks that no sealed verification or attachment has been changed (tamper detection).

.DESCRIPTION
Every verification and attachment written by PSLedger is sealed in the fiscal
year's integrity.txt, a hash chain where each record holds the SHA-256 of the item
and a chain hash over the previous record. Test-LedgerIntegrity recomputes the
chain and the hashes and returns one result per fiscal year. Nothing is modified.

The result's Status is:
- Valid    - the chain is intact and matches every verification and attachment.
- Invalid  - at least one issue was found (see Issues).
- Unsealed - the year has verifications but no chain yet (a journal created
             before tamper detection). Seal it with Protect-LedgerFiscalYear.

Each issue has Kind (Verification, Attachment or Chain), Key (the verification
number, or number/file name), Problem and Detail. Problems:
- Modified    - the item differs from the sealed hash.
- Missing     - a sealed item has been deleted. Attachments removed with
                Remove-LedgerAttachment are logged in the chain and not reported.
- Unsealed    - an item exists that the chain does not cover, e.g. a file added by
                hand or by another program.
- ChainBroken - a chain record has been edited, removed or re-ordered.
- Malformed   - a chain line cannot be read.
- Duplicate   - a verification is sealed more than once.
- HashMismatch - the final chain hash differs from -ExpectedHash.

Anyone who can edit the files can also rebuild the whole chain, which this check
cannot detect on its own. Save the ChainHash somewhere else (Close-LedgerFiscalYear
returns it) and pass it as -ExpectedHash to detect that as well.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year to check. If omitted, every fiscal year is checked.
Accepts pipeline input from fiscal year objects.

.PARAMETER ExpectedHash
A chain hash saved earlier (for example when the year was closed). An issue is
reported if the year's current final chain hash differs. Requires -FiscalYear.

.EXAMPLE
Test-LedgerIntegrity -JournalPath .\MinFirma.ledger

Checks every fiscal year of Min Firma AB and returns one result per year.

.EXAMPLE
$result = Test-LedgerIntegrity -JournalPath .\Konsult.ledger -FiscalYear '2024-01_2024-12' `
    -ExpectedHash '3f5c0e...'
if (-not $result.IsValid) { $result.Issues | Format-Table }

Checks 2024 against the chain hash saved when the year was closed and lists any
verification (for example 1930 Företagskonto postings) that has been altered.
#>
function Test-LedgerIntegrity {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [ValidatePattern('^[0-9a-fA-F]{64}$')]
        [string]$ExpectedHash
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Read

        if ($ExpectedHash -and -not $FiscalYear) {
            throw '-ExpectedHash requires -FiscalYear.'
        }

        $years = if ($FiscalYear) {
            @(Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath)
        }
        else {
            @(Get-LedgerFiscalYear -JournalPath $JournalPath | ForEach-Object Name)
        }

        foreach ($year in $years) {
            $yearDir = Join-Path $JournalPath $year
            if (-not (Test-Path -LiteralPath $yearDir -PathType Container)) {
                throw "Fiscal year not found: $year"
            }

            $issues = [System.Collections.Generic.List[object]]::new()
            $addIssue = {
                param($Kind, $Key, $Problem, $Detail)
                $issues.Add([pscustomobject]@{ Kind = $Kind; Key = $Key; Problem = $Problem; Detail = $Detail })
            }

            $chain = Read-LedgerIntegrityChain -YearDir $yearDir
            $content = Get-LedgerYearContent -YearDir $yearDir

            if ($null -eq $chain) {
                $status = if ($content.Verifications.Count -gt 0) { 'Unsealed' } else { 'Valid' }
                if ($ExpectedHash) {
                    & $addIssue 'Chain' '' 'HashMismatch' "The year has no integrity chain; expected chain hash $ExpectedHash."
                    $status = 'Invalid'
                }
                [pscustomobject]@{
                    FiscalYear    = $year
                    Status        = $status
                    IsValid       = $status -eq 'Valid'
                    Verifications = 0
                    Attachments   = 0
                    ChainHash     = $null
                    Issues        = $issues.ToArray()
                }
                continue
            }

            # Verify every chain hash against the previous well-formed record.
            $previous = $script:LedgerIntegrityGenesis
            $sealedVerifications = @{}
            foreach ($r in $chain) {
                if (-not $r.WellFormed) {
                    & $addIssue 'Chain' "line $($r.LineNumber)" 'Malformed' "Cannot read integrity.txt line $($r.LineNumber)."
                    continue
                }
                $expected = Get-LedgerIntegrityChainHash -Previous $previous -Kind $r.Kind -Key $r.Key -Sealed $r.Sealed -Hash $r.Hash
                if ($expected -ne $r.ChainHash) {
                    & $addIssue 'Chain' "line $($r.LineNumber)" 'ChainBroken' "The chain hash on integrity.txt line $($r.LineNumber) ($($r.Kind) $($r.Key)) does not match; a record has been edited, removed or re-ordered."
                }
                if ($r.Kind -eq 'Verification') {
                    if ($sealedVerifications.ContainsKey($r.Key)) {
                        & $addIssue 'Verification' $r.Key 'Duplicate' "Verification $($r.Key) is sealed more than once."
                    }
                    $sealedVerifications[$r.Key] = $true
                }
                $previous = $r.ChainHash
            }

            $state = Get-LedgerIntegrityState -Chain $chain
            $files = @{}
            foreach ($v in $content.Verifications) { $files["V:$($v.Key)"] = $v.Path }
            foreach ($a in $content.Attachments) { $files["A:$($a.Key)"] = $a.Path }

            foreach ($key in $state.Verifications.Keys) {
                $path = $files["V:$key"]
                if (-not $path) {
                    & $addIssue 'Verification' $key 'Missing' "Sealed verification $key has been deleted."
                }
                elseif ((Get-LedgerContentHash -Path $path) -ne $state.Verifications[$key]) {
                    & $addIssue 'Verification' $key 'Modified' "Verification $key has been changed since it was sealed."
                }
            }
            foreach ($key in $state.Attachments.Keys) {
                $path = $files["A:$key"]
                if (-not $path) {
                    & $addIssue 'Attachment' $key 'Missing' "Sealed attachment $key has been deleted without Remove-LedgerAttachment."
                }
                elseif ((Get-LedgerContentHash -Path $path) -ne $state.Attachments[$key]) {
                    & $addIssue 'Attachment' $key 'Modified' "Attachment $key has been changed since it was sealed."
                }
            }
            foreach ($v in $content.Verifications) {
                if (-not $state.Verifications.Contains($v.Key)) {
                    & $addIssue 'Verification' $v.Key 'Unsealed' "Verification $($v.Key) is not in the integrity chain. Run Protect-LedgerFiscalYear if it is legitimate."
                }
            }
            foreach ($a in $content.Attachments) {
                if (-not $state.Attachments.Contains($a.Key)) {
                    & $addIssue 'Attachment' $a.Key 'Unsealed' "Attachment $($a.Key) is not in the integrity chain. Run Protect-LedgerFiscalYear if it is legitimate."
                }
            }

            $head = Get-LedgerIntegrityHead -Chain $chain
            if ($ExpectedHash -and $head -ne $ExpectedHash.ToLowerInvariant()) {
                & $addIssue 'Chain' '' 'HashMismatch' "The final chain hash is $head, expected $($ExpectedHash.ToLowerInvariant())."
            }

            $status = if ($issues.Count -gt 0) { 'Invalid' } else { 'Valid' }
            [pscustomobject]@{
                FiscalYear    = $year
                Status        = $status
                IsValid       = $status -eq 'Valid'
                Verifications = $state.Verifications.Count
                Attachments   = $state.Attachments.Count
                ChainHash     = $head
                Issues        = $issues.ToArray()
            }
        }
    }
}
