# On-disk schema (data format) version for journals. This is deliberately
# separate from the module (semver) version: it is only bumped when the
# on-disk format changes in a way that requires migrating existing journals.
$script:CurrentSchemaVersion = 2

# Maps the schema version a journal is *currently* at to the migration that
# brings it one step forward. 'Description' is shown in -WhatIf/progress output;
# 'Action' is the name of the internal migration function (see Migrations.ps1).
# A regular hashtable is used (not [ordered]) so integer indexing does a key
# lookup rather than positional access; Update-LedgerJournal applies steps in
# ascending version order regardless of storage order.
$script:LedgerSchemaMigrations = @{
    1 = @{
        Description = 'Store opening balance as ib.txt metadata'
        Action      = 'Invoke-LedgerOpeningBalanceMigration'
    }
}

# Tracks paths a schema warning has already been shown for, so read commands
# warn once per session instead of on every call.
$script:SchemaWarnedPaths = @{}

function Get-LedgerJournalSchemaVersion {
    <#
    .SYNOPSIS
    Returns the on-disk schema version recorded in a journal's journal.txt.

    .DESCRIPTION
    Reads the 'SchemaVersion' field from journal.txt. Journals created before
    schema versioning was introduced have no such field and are treated as
    version 1. Returns $null if the path is not a journal (journal.txt missing).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $journalFile = Join-Path $Path 'journal.txt'
    if (-not (Test-Path $journalFile)) {
        return $null
    }

    foreach ($line in Get-Content $journalFile) {
        if ($line -match '^SchemaVersion:\s*(\d+)\s*$') {
            return [int]$Matches[1]
        }
    }

    # No SchemaVersion field => legacy journal predating schema versioning.
    return 1
}

function Set-LedgerJournalSchemaVersion {
    <#
    .SYNOPSIS
    Writes (or updates) the SchemaVersion field in a journal's journal.txt.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [int]$Version
    )

    $journalFile = Join-Path $Path 'journal.txt'
    if (-not (Test-Path $journalFile)) {
        throw "Invalid journal - journal.txt not found in: $Path"
    }

    $lines = @(Get-Content $journalFile)
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^SchemaVersion:\s*\d+\s*$') {
            $lines[$i] = "SchemaVersion: $Version"
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        $lines += "SchemaVersion: $Version"
    }

    $lines | Set-Content -Path $journalFile -Encoding UTF8
}

function Get-LedgerSchemaMigrationDescriptions {
    <#
    .SYNOPSIS
    Returns the descriptions of the migration steps needed to bring a journal
    from one schema version up to another.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][int]$From,
        [Parameter(Mandatory)][int]$To
    )

    $descriptions = @()
    for ($v = $From; $v -lt $To; $v++) {
        if ($script:LedgerSchemaMigrations.Contains($v)) {
            $descriptions += $script:LedgerSchemaMigrations[$v].Description
        }
    }
    return $descriptions
}

function Assert-LedgerJournalSchema {
    <#
    .SYNOPSIS
    Checks a journal's on-disk schema version against the version this module
    supports.

    .DESCRIPTION
    If the journal's schema is older than this module supports, the operation
    cannot safely proceed without migrating the journal first. Writing commands
    (-Write) throw so no data is written to an out-of-date journal; reading
    commands emit a one-time warning per journal so reports still work but the
    user is told to migrate. A journal newer than this module is also refused
    for writes and warned for reads, with a prompt to upgrade the module.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Write
    )

    $version = Get-LedgerJournalSchemaVersion -Path $Path
    if ($null -eq $version) {
        # Not a journal (yet) - nothing to check.
        return
    }

    $current = $script:CurrentSchemaVersion
    if ($version -eq $current) {
        return
    }

    if ($version -lt $current) {
        $message = "Journal '$Path' uses schema version $version but this PSLedger supports version $current. Migrate it with: Update-LedgerJournal -JournalPath '$Path'"
    }
    else {
        $message = "Journal '$Path' uses schema version $version which is newer than this PSLedger supports (version $current). Upgrade the PSLedger module to work with this journal."
    }

    if ($Write) {
        throw $message
    }

    if (-not $script:SchemaWarnedPaths.ContainsKey($Path)) {
        $script:SchemaWarnedPaths[$Path] = $true
        Write-Warning $message
    }
}
