<#
.SYNOPSIS
Sets the current PSLedger journal for the session.

.DESCRIPTION
Sets a session-level default journal path so that other PSLedger commands can be
called without specifying -JournalPath every time. Also loads any extensions
found in the journal's Extensions directory.

.PARAMETER Path
The path to an existing journal directory (must contain journal.txt).

.EXAMPLE
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

Sets MinFirma as the current journal. Subsequent commands like Add-LedgerEntry
can be called without -JournalPath.

.EXAMPLE
Set-LedgerCurrentJournal -Path C:\Bokföring\AB-Konsult.ledger
Get-LedgerBalance -FiscalYear '2024-01_2024-12'

Sets the journal and runs a balance query without specifying the path again.
#>
function Set-LedgerCurrentJournal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = Resolve-Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        throw "Journal path not found: $Path"
    }
    $resolvedPath = $resolvedPath.Path

    $journalFile = Join-Path $resolvedPath 'journal.txt'
    if (-not (Test-Path $journalFile)) {
        throw "Invalid journal — journal.txt not found in: $resolvedPath"
    }

    # Remove previous journal extensions if switching journals
    if ($script:CurrentJournalPath) {
        Remove-LedgerJournalExtensions
    }

    $script:CurrentJournalPath = $resolvedPath

    # Load per-journal extensions
    $journalExtPath = Join-Path $resolvedPath 'Extensions'
    if (Test-Path $journalExtPath -PathType Container) {
        $files = Get-ChildItem -Path $journalExtPath -Filter '*.ps1' -File | Sort-Object Name
        foreach ($file in $files) {
            Import-LedgerExtensionRuntime -Path $file.FullName -Source 'Journal'
        }
    }
}
