$script:LedgerJournalLocks = [System.Collections.Generic.Dictionary[string, System.IO.FileStream]]::new(
    $(if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }))

function Enter-LedgerJournalLock {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [ValidateRange(0, 30)] [int]$TimeoutSeconds = 30
    )

    if ($WhatIfPreference) { return $null }
    $fullPath = [System.IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($JournalPath))
    if (-not [System.IO.Directory]::Exists($fullPath)) {
        return $null # Let the caller report the missing journal.
    }
    $lockPath = Join-Path $fullPath '.write.lock'
    if ($script:LedgerJournalLocks.ContainsKey($lockPath)) {
        return $null # The outer operation owns the handle in this runspace.
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try {
            $stream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $script:LedgerJournalLocks.Add($lockPath, $stream)
            return [pscustomobject]@{ Path = $lockPath; Stream = $stream }
        }
        catch [System.IO.IOException] {
            # Sharing violation on Windows, EWOULDBLOCK/EAGAIN on Unix.
            $code = $_.Exception.HResult -band 0xffff
            if ($code -notin 32, 11, 35) { throw }
            if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                throw [System.TimeoutException]::new(
                    "Journal '$fullPath' is busy. Could not acquire its write lock within $TimeoutSeconds seconds. Retry after the other writer finishes; do not delete .write.lock.",
                    $_.Exception)
            }
            Start-Sleep -Milliseconds 100
        }
    }
}

function Exit-LedgerJournalLock {
    [CmdletBinding()]
    param ([AllowNull()] [object]$Lock)

    if ($null -eq $Lock) { return }
    try { $Lock.Stream.Dispose() }
    finally { [void]$script:LedgerJournalLocks.Remove($Lock.Path) }
    # Keep the file: deleting it would allow Unix writers to lock different inodes.
}
