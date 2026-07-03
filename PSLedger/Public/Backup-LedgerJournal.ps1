<#
.SYNOPSIS
Creates a timestamped zip backup of a PSLedger journal.

.DESCRIPTION
Compresses an entire journal directory (.ledger) into a single timestamped zip
archive named '<JournalName>_yyyy-MM-dd_HHmmss.zip'. Backups are written to a
destination directory (by default a 'backups' folder next to the journal) which
is created if it does not exist.

By default the five most recent backups of the same journal are retained and any
older ones are removed. Use -KeepCount to change the retention count, or
-KeepCount 0 to keep every backup.

The journal schema version is not enforced, so a backup can always be taken —
for example just before running Update-LedgerJournal.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, the current session
journal (set via Set-LedgerCurrentJournal) is used.

.PARAMETER DestinationPath
The directory where the backup archive is written. Defaults to a 'backups'
folder located next to the journal directory. Created if it does not exist.

.PARAMETER KeepCount
How many of the most recent backups of this journal to keep. Older backups are
removed after the new one is created. Defaults to 5. Use 0 to keep all backups.

.EXAMPLE
Backup-LedgerJournal -JournalPath .\MinFirma.ledger

Creates .\backups\MinFirma_2026-07-03_095752.zip and keeps the five most recent
backups.

.EXAMPLE
Set-LedgerCurrentJournal -Path .\Konsult.ledger
Backup-LedgerJournal -DestinationPath D:\Backuper -KeepCount 10

Backs up the current session journal to D:\Backuper and retains the ten most
recent archives.
#>
function Backup-LedgerJournal {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$DestinationPath,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$KeepCount = 5
    )

    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck None

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }
    if (-not (Test-Path (Join-Path $JournalPath 'journal.txt') -PathType Leaf)) {
        throw "Invalid journal - journal.txt not found in: $JournalPath"
    }

    $JournalDir = (Resolve-Path $JournalPath).Path.TrimEnd('\', '/')
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($JournalDir)

    if (-not $DestinationPath) {
        $DestinationPath = Join-Path (Split-Path $JournalDir -Parent) 'backups'
    }

    if (-not (Test-Path $DestinationPath -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($DestinationPath, 'Create backup directory')) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
    }

    $Timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $ArchiveName = "${BaseName}_${Timestamp}.zip"
    $ArchivePath = Join-Path $DestinationPath $ArchiveName

    if ($PSCmdlet.ShouldProcess($ArchivePath, "Back up journal '$BaseName'")) {
        Compress-Archive -Path $JournalDir -DestinationPath $ArchivePath -Force
    }

    if ($KeepCount -gt 0 -and (Test-Path $DestinationPath -PathType Container)) {
        $Existing = @(Get-ChildItem -Path $DestinationPath -Filter "${BaseName}_*.zip" -File |
            Sort-Object Name -Descending)

        if ($Existing.Count -gt $KeepCount) {
            $ToRemove = $Existing | Select-Object -Skip $KeepCount
            foreach ($Old in $ToRemove) {
                if ($PSCmdlet.ShouldProcess($Old.FullName, 'Remove old backup')) {
                    Remove-Item -Path $Old.FullName -Force
                }
            }
        }
    }

    if (Test-Path $ArchivePath -PathType Leaf) {
        Get-Item -Path $ArchivePath
    }
}
