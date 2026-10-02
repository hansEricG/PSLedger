# Tamper detection (varaktighet) for verifications and their attachments.
#
# Each fiscal year directory may hold an append-only integrity.txt: a hash chain
# with one record per sealed verification, sealed attachment and removed
# attachment. A record stores the SHA-256 of the item and a chain hash over the
# previous record's chain hash and the record's own fields, so changing, removing
# or re-ordering a record breaks every chain hash after it. See
# docs/File-format.md for the format.

$script:LedgerIntegrityFileName = 'integrity.txt'
$script:LedgerIntegrityGenesis = '0' * 64
$script:LedgerIntegrityKinds = @('Verification', 'Attachment', 'AttachmentRemoved')

function Get-LedgerSha256Hex {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-LedgerContentHash {
    <#
    .SYNOPSIS
    SHA-256 of a file, with CRLF normalised to LF for text files.

    .DESCRIPTION
    Git (core.autocrlf / text=auto) converts line endings of files it considers
    text: those without a NUL byte in the first 8000 bytes. The same rule is used
    here so a journal checked out on Windows and on Linux gives the same hashes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $probe = [Math]::Min($bytes.Length, 8000)
    $isText = $probe -eq 0 -or [Array]::IndexOf($bytes, [byte]0, 0, $probe) -lt 0
    if ($isText -and [Array]::IndexOf($bytes, [byte]13) -ge 0) {
        # Latin-1 maps every byte to one char, so the round trip preserves all
        # other bytes exactly.
        $latin1 = [System.Text.Encoding]::Latin1
        $bytes = $latin1.GetBytes($latin1.GetString($bytes).Replace("`r`n", "`n"))
    }
    return Get-LedgerSha256Hex -Bytes $bytes
}

function Get-LedgerIntegrityChainHash {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string]$Previous,
        [Parameter(Mandatory)] [string]$Kind,
        [Parameter(Mandatory)] [string]$Key,
        [Parameter(Mandatory)] [string]$Sealed,
        [Parameter(Mandatory)] [string]$Hash
    )
    $text = "$Previous`t$Kind`t$Key`t$Sealed`t$Hash"
    return Get-LedgerSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($text))
}

function Get-LedgerIntegrityPath {
    [CmdletBinding()]
    [OutputType([string])]
    param ([Parameter(Mandatory)] [string]$YearDir)
    return Join-Path $YearDir $script:LedgerIntegrityFileName
}

function Read-LedgerIntegrityChain {
    <#
    .SYNOPSIS
    Reads integrity.txt. Returns $null when the year has no chain.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$YearDir)

    $path = Get-LedgerIntegrityPath -YearDir $YearDir
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }

    $records = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.UTF8Encoding]::new($false))) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';')) { continue }
        $parts = $line -split "`t"
        $wellFormed = $parts.Count -eq 5 -and
            $script:LedgerIntegrityKinds -ccontains $parts[0] -and
            $parts[1] -ne '' -and
            $parts[3] -cmatch '^[0-9a-f]{64}$' -and
            $parts[4] -cmatch '^[0-9a-f]{64}$'
        $records.Add([pscustomobject]@{
                LineNumber = $lineNumber
                WellFormed = $wellFormed
                Kind       = if ($wellFormed) { $parts[0] } else { $null }
                Key        = if ($wellFormed) { $parts[1] } else { $null }
                Sealed     = if ($wellFormed) { $parts[2] } else { $null }
                Hash       = if ($wellFormed) { $parts[3] } else { $null }
                ChainHash  = if ($wellFormed) { $parts[4] } else { $null }
                Line       = $line
            })
    }
    return , $records
}

function Get-LedgerIntegrityHead {
    [CmdletBinding()]
    [OutputType([string])]
    param ([Parameter()] [AllowNull()] [object]$Chain)
    $head = $script:LedgerIntegrityGenesis
    foreach ($r in @($Chain)) {
        if ($r -and $r.WellFormed) { $head = $r.ChainHash }
    }
    return $head
}

function Get-LedgerIntegrityState {
    <#
    .SYNOPSIS
    Folds a chain into the sealed verifications and the live sealed attachments.
    #>
    [CmdletBinding()]
    param ([Parameter()] [AllowNull()] [object]$Chain)

    $verifications = [ordered]@{}
    $attachments = [ordered]@{}
    foreach ($r in @($Chain)) {
        if (-not $r -or -not $r.WellFormed) { continue }
        switch ($r.Kind) {
            'Verification' { if (-not $verifications.Contains($r.Key)) { $verifications[$r.Key] = $r.Hash } }
            'Attachment' { $attachments[$r.Key] = $r.Hash }
            'AttachmentRemoved' { $attachments.Remove($r.Key) }
        }
    }
    return [pscustomobject]@{ Verifications = $verifications; Attachments = $attachments }
}

function Get-LedgerYearContent {
    <#
    .SYNOPSIS
    Lists the verification files and attachments of a fiscal year directory.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$YearDir)

    $verifications = @(Get-ChildItem -LiteralPath $YearDir -File -Filter 'ver*.txt' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^ver(\d+)\.txt$' } |
            ForEach-Object { [pscustomobject]@{ Number = [int]$Matches[1]; Key = [string][int]$Matches[1]; Path = $_.FullName } } |
            Sort-Object Number)

    $attachments = @(Get-ChildItem -LiteralPath $YearDir -Directory -Filter 'ver*' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^ver(\d+)$' } |
            ForEach-Object {
                $number = [int]$Matches[1]
                Get-ChildItem -LiteralPath $_.FullName -File | Sort-Object Name | ForEach-Object {
                    [pscustomobject]@{ Number = $number; Key = "$number/$($_.Name)"; Path = $_.FullName }
                }
            } |
            Sort-Object Number, Key)

    return [pscustomobject]@{ Verifications = $verifications; Attachments = $attachments }
}

function Write-LedgerIntegrityRecord {
    <#
    .SYNOPSIS
    Appends records (Kind, Key, Hash) to the chain, creating the file if needed.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$YearDir,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Record,

        [Parameter()]
        [AllowNull()]
        [object]$Chain
    )
    if ($Record.Count -eq 0) { return }

    $path = Get-LedgerIntegrityPath -YearDir $YearDir
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Set-LedgerFileContent -Path $path -Value @(
            '; PSLedger integrity chain'
            "; Kind`tKey`tSealed`tHash`tChainHash"
        )
        $Chain = $null
    }
    elseif ($null -eq $Chain) {
        $Chain = Read-LedgerIntegrityChain -YearDir $YearDir
    }

    $previous = Get-LedgerIntegrityHead -Chain $Chain
    $sealed = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    $nl = [Environment]::NewLine
    $sb = [System.Text.StringBuilder]::new()

    # The chain is append-only, so it is appended rather than rewritten. If the
    # last line lacks its line break (an interrupted append) start a new line.
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -gt 0 -and $bytes[-1] -ne 10) { [void]$sb.Append($nl) }

    foreach ($r in $Record) {
        $chainHash = Get-LedgerIntegrityChainHash -Previous $previous -Kind $r.Kind -Key $r.Key -Sealed $sealed -Hash $r.Hash
        [void]$sb.Append("$($r.Kind)`t$($r.Key)`t$sealed`t$($r.Hash)`t$chainHash$nl")
        $previous = $chainHash
    }
    [System.IO.File]::AppendAllText($path, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
}

function Protect-LedgerYearContent {
    <#
    .SYNOPSIS
    Seals every verification and attachment in a year that the chain lacks.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)] [string]$YearDir)

    $chain = Read-LedgerIntegrityChain -YearDir $YearDir
    $state = Get-LedgerIntegrityState -Chain $chain
    $content = Get-LedgerYearContent -YearDir $YearDir

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($v in $content.Verifications) {
        if (-not $state.Verifications.Contains($v.Key)) {
            $records.Add([pscustomobject]@{ Kind = 'Verification'; Key = $v.Key; Hash = (Get-LedgerContentHash -Path $v.Path) })
        }
        foreach ($a in @($content.Attachments | Where-Object Number -EQ $v.Number)) {
            if (-not $state.Attachments.Contains($a.Key)) {
                $records.Add([pscustomobject]@{ Kind = 'Attachment'; Key = $a.Key; Hash = (Get-LedgerContentHash -Path $a.Path) })
            }
        }
    }
    Write-LedgerIntegrityRecord -YearDir $YearDir -Record $records.ToArray() -Chain $chain
    return $records.Count
}

function Register-LedgerIntegrityItem {
    <#
    .SYNOPSIS
    Seals a newly written verification or attachment.

    .DESCRIPTION
    When the year has no chain yet (a journal created before tamper detection),
    everything already in the year is sealed first, which includes the new item.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$YearDir,
        [Parameter(Mandatory)] [ValidateSet('Verification', 'Attachment')] [string]$Kind,
        [Parameter(Mandatory)] [string]$Key,
        [Parameter(Mandatory)] [string]$Path
    )
    if (-not (Test-Path -LiteralPath (Get-LedgerIntegrityPath -YearDir $YearDir) -PathType Leaf)) {
        [void](Protect-LedgerYearContent -YearDir $YearDir)
        return
    }
    $record = [pscustomobject]@{ Kind = $Kind; Key = $Key; Hash = (Get-LedgerContentHash -Path $Path) }
    Write-LedgerIntegrityRecord -YearDir $YearDir -Record @($record)
}

function Test-LedgerIntegrityAttachmentSealed {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)] [string]$YearDir,
        [Parameter(Mandatory)] [string]$Key
    )
    $chain = Read-LedgerIntegrityChain -YearDir $YearDir
    if ($null -eq $chain) { return $false }
    return (Get-LedgerIntegrityState -Chain $chain).Attachments.Contains($Key)
}

function Remove-LedgerIntegrityTail {
    <#
    .SYNOPSIS
    Drops the last chain record if it seals the given item (rollback of a failed write).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$YearDir,
        [Parameter(Mandatory)] [string]$Kind,
        [Parameter(Mandatory)] [string]$Key
    )
    $chain = Read-LedgerIntegrityChain -YearDir $YearDir
    if ($null -eq $chain -or $chain.Count -eq 0) { return }
    $last = $chain[$chain.Count - 1]
    if (-not $last.WellFormed -or $last.Kind -ne $Kind -or $last.Key -ne $Key) { return }

    $path = Get-LedgerIntegrityPath -YearDir $YearDir
    $lines = [System.IO.File]::ReadAllLines($path, [System.Text.UTF8Encoding]::new($false))
    $kept = for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -ne $last.LineNumber - 1) { $lines[$i] }
    }
    Set-LedgerFileContent -Path $path -Value @($kept)
}
