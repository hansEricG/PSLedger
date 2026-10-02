# Atomic file-write helper.
#
# Writing a multi-line ledger record (verification, invoice, payslip, opening
# balance, journal metadata, ...) directly with Set-Content means that an error
# part-way through the write — a full disk, a crash, an I/O error — can leave the
# file truncated and corrupt, destroying the whole record. To make each write
# atomic, the content is first written to a temporary file in the same directory
# and then moved into place. Move-Item within a directory is a rename, so the
# destination path always refers to either the complete old file or the complete
# new file, never a half-written one.

function Set-LedgerFileContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        # The content to write, matching what would be piped to Set-Content:
        # a string, an array of strings (one per line) or $null/empty.
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        $Value
    )

    # .NET resolves relative paths against the process directory, not the
    # PowerShell location, so resolve to a full provider path first.
    $fullPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    $dir = [System.IO.Path]::GetDirectoryName($fullPath)

    $tempPath = Join-Path $dir ('.tmp_' + [guid]::NewGuid().ToString('N'))

    try {
        # Set-Content writes UTF-8 (no BOM in PowerShell 7) with the same line
        # handling the callers previously relied on.
        Set-Content -LiteralPath $tempPath -Value $Value -Encoding UTF8
        # File.Move with overwrite replaces the target in one step (rename(2) on
        # Unix, MoveFileEx with MOVEFILE_REPLACE_EXISTING on Windows). Move-Item
        # -Force deletes the target first, leaving a moment without the file.
        # On Windows a virus scanner, the search indexer or a sync client can hold
        # the target open for a moment, so retry briefly before giving up.
        $attempt = 0
        while ($true) {
            try {
                [System.IO.File]::Move($tempPath, $fullPath, $true)
                break
            }
            catch {
                $ex = if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }
                $transient = ($ex -is [System.UnauthorizedAccessException] -or $ex -is [System.IO.IOException]) -and
                    $ex -isnot [System.IO.FileNotFoundException] -and $ex -isnot [System.IO.DirectoryNotFoundException]
                if (-not $transient -or ++$attempt -ge 5) { throw }
                Start-Sleep -Milliseconds (50 * $attempt)
            }
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Add-LedgerFileLine {
    <#
    .SYNOPSIS
    Appends lines to a register file by rewriting it atomically.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Line
    )

    $existing = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        @(Get-Content -LiteralPath $Path -Encoding UTF8)
    }
    else {
        @()
    }
    Set-LedgerFileContent -Path $Path -Value (@($existing) + $Line)
}
