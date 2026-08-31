<#
.SYNOPSIS
Restores a PSLedger journal from a zip backup archive.

.DESCRIPTION
Extracts a backup archive created by Backup-LedgerJournal, recreating the journal
directory inside the destination directory. The archive is expected to contain a
single top-level '<Name>.ledger' folder holding a journal.txt file.

By default the journal is restored into the current directory and the command
refuses to overwrite an existing journal directory. Use -Force to replace an
existing journal, or -DestinationPath to restore somewhere else.

.PARAMETER ArchivePath
The path to a .zip backup archive to restore.

.PARAMETER DestinationPath
The directory into which the journal folder is extracted. Defaults to the current
directory. Created if it does not exist.

.PARAMETER Force
Replace an existing journal directory at the target location. Without this switch
the command throws if the target already exists.

.EXAMPLE
Restore-LedgerJournal -ArchivePath .\backups\MinFirma_2026-07-03_095752.zip

Restores .\MinFirma.ledger from the backup into the current directory.

.EXAMPLE
Restore-LedgerJournal -ArchivePath D:\Backuper\Konsult_2026-01-31_235500.zip -DestinationPath C:\Bokföring -Force

Restores the journal into C:\Bokföring, overwriting an existing Konsult.ledger
directory there.
#>
function Restore-LedgerJournal {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter()]
        [string]$DestinationPath,

        [Parameter()]
        [switch]$Force
    )

    if (-not (Test-Path $ArchivePath -PathType Leaf)) {
        throw "Backup archive not found: $ArchivePath"
    }

    $ArchiveFullPath = (Resolve-Path $ArchivePath).Path

    if (-not $DestinationPath) {
        $DestinationPath = (Get-Location).Path
    }

    # Inspect the archive to find the top-level journal folder and validate it.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Zip = [System.IO.Compression.ZipFile]::OpenRead($ArchiveFullPath)
    try {
        $Roots = @($Zip.Entries |
            ForEach-Object { ($_.FullName -split '[\\/]', 2)[0] } |
            Where-Object { $_ } |
            Select-Object -Unique)

        if ($Roots.Count -ne 1) {
            throw "Invalid backup archive - expected a single top-level journal folder in: $ArchivePath"
        }

        $JournalFolder = $Roots[0]
        $HasJournalFile = $Zip.Entries |
            Where-Object { ($_.FullName -replace '\\', '/') -eq "$JournalFolder/journal.txt" }

        if (-not $HasJournalFile) {
            throw "Invalid backup archive - journal.txt not found in: $ArchivePath"
        }

        # Guard against path traversal (zip-slip): every entry must resolve to a
        # location inside the destination directory. Reject '..' segments, rooted
        # paths, or any entry whose resolved path escapes the destination.
        $DestRoot = [System.IO.Path]::GetFullPath($DestinationPath)
        if (-not $DestRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $DestRoot += [System.IO.Path]::DirectorySeparatorChar
        }
        foreach ($Entry in $Zip.Entries) {
            $EntryName = $Entry.FullName
            if ([System.IO.Path]::IsPathRooted($EntryName) -or
                $EntryName -match '(^|[\\/])\.\.([\\/]|$)') {
                throw "Invalid backup archive - unsafe entry path: $EntryName"
            }
            $Resolved = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($DestRoot, $EntryName))
            if (-not $Resolved.StartsWith($DestRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Invalid backup archive - entry escapes destination: $EntryName"
            }
        }
    }
    finally {
        $Zip.Dispose()
    }

    $TargetPath = Join-Path $DestinationPath $JournalFolder

    if (Test-Path $TargetPath) {
        if (-not $Force) {
            throw "Journal already exists: $TargetPath. Use -Force to overwrite."
        }
        if ($PSCmdlet.ShouldProcess($TargetPath, 'Remove existing journal before restore')) {
            Remove-Item -Path $TargetPath -Recurse -Force
        }
    }

    if (-not (Test-Path $DestinationPath -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($DestinationPath, 'Create destination directory')) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
    }

    if ($PSCmdlet.ShouldProcess($TargetPath, "Restore journal from '$([System.IO.Path]::GetFileName($ArchiveFullPath))'")) {
        Expand-Archive -Path $ArchiveFullPath -DestinationPath $DestinationPath -Force

        if (Test-Path (Join-Path $TargetPath 'journal.txt') -PathType Leaf) {
            Get-LedgerJournal -Path $TargetPath
        }
    }
}
