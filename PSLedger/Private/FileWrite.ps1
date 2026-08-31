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

    $dir = Split-Path -Parent $Path
    if (-not $dir) { $dir = '.' }

    $tempPath = Join-Path $dir ('.tmp_' + [guid]::NewGuid().ToString('N'))

    try {
        # Set-Content writes UTF-8 (no BOM in PowerShell 7) with the same line
        # handling the callers previously relied on.
        Set-Content -Path $tempPath -Value $Value -Encoding UTF8
        Move-Item -Path $tempPath -Destination $Path -Force
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}
