<#
.SYNOPSIS
Migrates a journal's opening balances from verification files to ib.txt metadata.

.DESCRIPTION
Older journals stored the opening balance (ingående balans) as the first
verification (ver0001.txt with the description 'Ingående balans'). Current
PSLedger stores it as metadata in ib.txt instead, so verification numbering
matches the source accounting system.

This cmdlet converts every fiscal year in a journal in place: it extracts the
'Ingående balans' verification into ib.txt, deletes that verification, and
renumbers the remaining verifications (and any attachment directories) down by
one so they become ver0001..ver(N-1). Fiscal years that already have an ib.txt,
or whose ver0001 is a normal verification, are left untouched, so the operation
is safe to run repeatedly (idempotent).

Supports -WhatIf and -Confirm.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.EXAMPLE
Convert-LedgerOpeningBalance -JournalPath .\MinFirma.ledger

Migrates every fiscal year in the journal to the ib.txt opening balance format.

.EXAMPLE
Convert-LedgerOpeningBalance -JournalPath .\MinFirma.ledger -WhatIf

Shows which fiscal years would be migrated without changing anything.
#>
function Convert-LedgerOpeningBalance {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

        if (-not (Test-Path $JournalPath -PathType Container)) {
            throw "Journal not found: $JournalPath"
        }

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

            if (-not $PSCmdlet.ShouldProcess($fyName, "Convert 'Ingående balans' to ib.txt and renumber verifications")) {
                continue
            }

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
                FiscalYear                = $fyName
                OpeningBalanceRows        = $ibRows.Count
                RenumberedVerifications   = $renumbered
            }
        }
    }
}
