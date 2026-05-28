# Helpers for reading and writing SIE files in CP437 (PC-8) encoding.
# SIE 4 standard requires PC-8 (IBM CP437). Internally we work with
# regular .NET strings; only I/O goes through this layer.

function Get-SieEncoding {
    [CmdletBinding()]
    param()
    [System.Text.Encoding]::GetEncoding(437)
}

function Read-SieText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Resolve relative paths against PowerShell's $PWD (not .NET's process CWD)
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "SIE file not found: $Path"
    }

    [System.IO.File]::ReadAllText($Path, (Get-SieEncoding))
}

function Write-SieText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    # Resolve relative paths against PowerShell's $PWD (not .NET's process CWD)
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    [System.IO.File]::WriteAllText($Path, $Text, (Get-SieEncoding))
}
