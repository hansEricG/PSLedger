<#
.SYNOPSIS
Verifies an archive package created by Export-LedgerArchive.

.DESCRIPTION
Checks a package (zip file or directory) against its checksums.txt and, when the
package recorded a chain hash, checks the archived fiscal year's integrity chain
against that hash with Test-LedgerIntegrity.

A zip file is extracted to a temporary directory, which is removed afterwards.

The result has Status 'Valid' or 'Invalid', and Issues with Path, Problem and Detail.
Problem is one of:
- Missing   - a file listed in checksums.txt is not in the package.
- Modified  - a file's SHA-256 differs from checksums.txt.
- Unlisted  - a file in the package is not listed in checksums.txt.
- Malformed - checksums.txt or manifest.txt is missing or a line cannot be read.
- Integrity - the archived fiscal year fails Test-LedgerIntegrity (Detail has the
              verification or attachment and the problem).

.PARAMETER Path
The archive package: a .zip file or the package directory (the one containing
checksums.txt). Accepts pipeline input, for example from Export-LedgerArchive.

.EXAMPLE
Test-LedgerArchive -Path .\archive\MinFirma_2024-01_2024-12_archive.zip

Verifies Min Firma AB's archive of 2024.

.EXAMPLE
Get-ChildItem E:\Arkiv -Filter '*_archive.zip' | Test-LedgerArchive |
    Where-Object { -not $_.IsValid } | Select-Object -ExpandProperty Issues

Checks every archived year of Konsult AB on an external disk and lists the problems.
#>
function Test-LedgerArchive {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path
    )
    process {
        $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not (Test-Path -LiteralPath $full)) {
            throw "Archive not found: $Path"
        }

        $temp = $null
        try {
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                $temp = Join-Path ([System.IO.Path]::GetTempPath()) "psledger_archive_$([guid]::NewGuid().ToString('N'))"
                [System.IO.Compression.ZipFile]::ExtractToDirectory($full, $temp)
                $root = $temp
                $children = @(Get-ChildItem -LiteralPath $temp -Force)
                if (-not (Test-Path -LiteralPath (Join-Path $temp $script:LedgerArchiveChecksumFile)) -and
                    $children.Count -eq 1 -and $children[0].PSIsContainer) {
                    $root = $children[0].FullName
                }
            }
            else {
                $root = $full
            }

            $issues = [System.Collections.Generic.List[object]]::new()
            $addIssue = {
                param($p, $problem, $detail)
                $issues.Add([pscustomobject]@{ Path = $p; Problem = $problem; Detail = $detail })
            }

            $listed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $checksumPath = Join-Path $root $script:LedgerArchiveChecksumFile
            if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
                & $addIssue $script:LedgerArchiveChecksumFile 'Malformed' 'checksums.txt is missing; this is not an archive package.'
            }
            else {
                $lineNumber = 0
                foreach ($line in [System.IO.File]::ReadAllLines($checksumPath)) {
                    $lineNumber++
                    if (-not $line) { continue }
                    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') {
                        & $addIssue $script:LedgerArchiveChecksumFile 'Malformed' "Cannot read checksums.txt line $lineNumber."
                        continue
                    }
                    $hash = $Matches[1]
                    $rel = $Matches[2]
                    [void]$listed.Add($rel)
                    $file = Join-Path $root $rel
                    if ($rel -match '(^|/)\.\.(/|$)' -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
                        & $addIssue $rel 'Missing' "$rel is listed in checksums.txt but not in the package."
                    }
                    elseif ((Get-LedgerArchiveFileHash -Path $file) -ne $hash) {
                        & $addIssue $rel 'Modified' "$rel differs from its checksum."
                    }
                }
                foreach ($rel in (Get-LedgerArchiveRelativeFile -Root $root)) {
                    if ($rel -ne $script:LedgerArchiveChecksumFile -and -not $listed.Contains($rel)) {
                        & $addIssue $rel 'Unlisted' "$rel is not listed in checksums.txt."
                    }
                }
            }

            $manifest = @{}
            $manifestPath = Join-Path $root $script:LedgerArchiveManifestFile
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                $manifest = Read-LedgerArchiveManifest -Path $manifestPath
            }
            if (-not $manifest.FiscalYear) {
                & $addIssue $script:LedgerArchiveManifestFile 'Malformed' 'manifest.txt is missing or has no FiscalYear.'
            }

            $integrityStatus = $null
            $archJournal = Join-Path $root 'journal'
            if ($manifest.FiscalYear -and (Test-Path -LiteralPath (Join-Path $archJournal $manifest.FiscalYear) -PathType Container)) {
                $params = @{ JournalPath = $archJournal; FiscalYear = $manifest.FiscalYear }
                if ($manifest.ChainHash) { $params.ExpectedHash = $manifest.ChainHash }
                $integrity = Test-LedgerIntegrity @params -WarningAction SilentlyContinue
                $integrityStatus = $integrity.Status
                foreach ($i in $integrity.Issues) {
                    & $addIssue "journal/$($manifest.FiscalYear)" 'Integrity' "$($i.Kind) $($i.Key): $($i.Problem). $($i.Detail)"
                }
            }

            $status = if ($issues.Count -eq 0) { 'Valid' } else { 'Invalid' }
            [pscustomobject]@{
                Path            = $full
                Journal         = $manifest.Journal
                FiscalYear      = $manifest.FiscalYear
                Preliminary     = $manifest.Preliminary -eq 'True'
                Created         = $manifest.Created
                Status          = $status
                IsValid         = $status -eq 'Valid'
                Files           = $listed.Count
                IntegrityStatus = $integrityStatus
                ChainHash       = $manifest.ChainHash
                Issues          = $issues.ToArray()
            }
        }
        finally {
            if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Recurse -Force }
        }
    }
}
