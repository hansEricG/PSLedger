<#
.SYNOPSIS
Migrates a journal on disk to the schema version this PSLedger supports.

.DESCRIPTION
PSLedger records an on-disk schema version in each journal's journal.txt. When
the storage format changes in a way that requires a migration, the supported
version is bumped and writing commands refuse to operate on older journals.

Update-LedgerJournal brings a journal up to date by applying every pending
migration step in order, then stamping the journal with the current schema
version so writing commands work again. It is safe to run on an already
up-to-date journal (nothing happens) and safe to run repeatedly (each migration
step is idempotent).

The individual migration steps are:
- v1 -> v2: move opening balances (ingående balans) from a ver0001.txt
  verification into ib.txt metadata and renumber the remaining verifications so
  they match the source accounting system.

Supports -WhatIf and -Confirm.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.EXAMPLE
Update-LedgerJournal -JournalPath .\MinFirma.ledger

Applies all pending schema migrations to the journal.

.EXAMPLE
Update-LedgerJournal -JournalPath .\MinFirma.ledger -WhatIf

Shows which migration steps would run without changing anything.
#>
function Update-LedgerJournal {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck None

        if (-not (Test-Path $JournalPath -PathType Container)) {
            throw "Journal not found: $JournalPath"
        }

        $version = Get-LedgerJournalSchemaVersion -Path $JournalPath
        if ($null -eq $version) {
            throw "Invalid journal - journal.txt not found in: $JournalPath"
        }

        $current = $script:CurrentSchemaVersion
        if ($version -gt $current) {
            throw "Journal '$JournalPath' uses schema version $version which is newer than this PSLedger supports (version $current). Upgrade the PSLedger module to work with this journal."
        }

        for ($v = $version; $v -lt $current; $v++) {
            $migration = $script:LedgerSchemaMigrations[$v]
            $description = if ($migration) { $migration.Description } else { "schema v$v to v$($v + 1)" }

            if (-not $PSCmdlet.ShouldProcess($JournalPath, "Migrate schema version $v -> $($v + 1): $description")) {
                # Stop at the first declined/-WhatIf step; later steps depend on
                # earlier ones and must not run against an un-migrated journal.
                break
            }

            if ($migration -and $migration.Action) {
                & $migration.Action -JournalPath $JournalPath
            }

            Set-LedgerJournalSchemaVersion -Path $JournalPath -Version ($v + 1)
        }
    }
}
