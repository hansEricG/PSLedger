# Internal schema migration steps. Each function migrates a journal one schema
# version forward and is invoked by Update-LedgerJournal via the migration
# registry in JournalSchema.ps1. These functions do the work unconditionally;
# -WhatIf/-Confirm handling lives in Update-LedgerJournal.

function Invoke-LedgerOpeningBalanceMigration {
    <#
    .SYNOPSIS
    Schema v1 -> v2: move opening balances from ver0001.txt to ib.txt metadata.

    .DESCRIPTION
    Older journals stored the opening balance (ingående balans) as the first
    verification (ver0001.txt with the description 'Ingående balans'). This step
    extracts that verification into ib.txt, deletes it, and renumbers the
    remaining verifications (and any attachment directories) down by one so they
    become ver0001..ver(N-1). Fiscal years that already have an ib.txt, or whose
    ver0001 is a normal verification, are left untouched (idempotent).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )

    $yearDirs = Get-ChildItem -Path $JournalPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}_\d{4}-\d{2}$' } |
        Sort-Object Name

    foreach ($yearDir in $yearDirs) {
        $dir = $yearDir.FullName
        $fyName = $yearDir.Name

        # Skip already-migrated years.
        $ibFile = Get-LedgerOpeningBalancePath -YearDir $dir
        if (Test-Path $ibFile -PathType Leaf) { continue }

        $ver1 = Join-Path $dir 'ver0001.txt'
        if (-not (Test-Path $ver1 -PathType Leaf)) { continue }

        # Only migrate when ver0001 is the opening balance verification.
        $lines = Get-Content $ver1
        $isOpening = $false
        foreach ($line in $lines) {
            if ($line -match '^Description:\s*(.+)$') {
                $isOpening = ($Matches[1].Trim() -eq 'Ingående balans')
                break
            }
        }
        if (-not $isOpening) { continue }

        $ibRows = foreach ($line in $lines) {
            if ($line -match '^(\d+)\t([^\t]+)') {
                [PSCustomObject]@{ Account = $Matches[1]; Amount = [decimal]$Matches[2] }
            }
        }
        $ibRows = @($ibRows)

        # Write ib.txt, then remove the opening balance verification.
        Write-LedgerOpeningBalance -YearDir $dir -Rows $ibRows
        Remove-Item -Path $ver1 -Force

        # The opening balance never carries attachments; remove a stray dir if any.
        $ibAttachDir = Join-Path $dir 'ver0001'
        if (Test-Path $ibAttachDir -PathType Container) {
            Write-Warning "Removing attachment directory for the opening balance verification: $ibAttachDir"
            Remove-Item -Path $ibAttachDir -Recurse -Force
        }

        # Renumber remaining verifications (and attachment dirs) down by one.
        # Process in ascending order so each target slot is already vacated.
        $verFiles = Get-ChildItem -Path $dir -Filter 'ver*.txt' -File |
            Where-Object { $_.BaseName -match '^ver(\d+)$' } |
            Sort-Object { [int]($_.BaseName -replace '^ver', '') }

        $renumbered = 0
        foreach ($vf in $verFiles) {
            $num = [int]($vf.BaseName -replace '^ver', '')
            $newNum = $num - 1
            $newBase = 'ver' + $newNum.ToString('0000')

            Rename-Item -Path $vf.FullName -NewName ($newBase + '.txt')

            $oldAttach = Join-Path $dir $vf.BaseName
            if (Test-Path $oldAttach -PathType Container) {
                Rename-Item -Path $oldAttach -NewName $newBase
            }
            $renumbered++
        }

        [PSCustomObject]@{
            FiscalYear              = $fyName
            OpeningBalanceRows      = $ibRows.Count
            RenumberedVerifications = $renumbered
        }
    }
}
