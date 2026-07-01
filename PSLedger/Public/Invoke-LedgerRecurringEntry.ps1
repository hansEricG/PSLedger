<#
.SYNOPSIS
Generates verifications from recurring entry templates.

.DESCRIPTION
Evaluates all recurring entry templates and generates any missing verifications
up to the specified date (default: today). The function is idempotent — running
it multiple times will not create duplicate entries because it tracks the last
generated date in each template file.

For monthly schedules, generates one verification per month on the configured
DayOfMonth, starting from the later of StartDate or the day after LastGenerated.

.PARAMETER JournalPath
Path to the journal (.ledger directory).

.PARAMETER Through
Generate entries through this date (inclusive). Defaults to today.

.PARAMETER Name
Optional name filter. If specified, only processes the named template.

.EXAMPLE
Invoke-LedgerRecurringEntry -JournalPath .\ab.ledger

Generates all pending recurring entries through today.

.EXAMPLE
Invoke-LedgerRecurringEntry -JournalPath .\ab.ledger -Through '2024-06-30' -Name 'Hyra'

Generates pending entries for the 'Hyra' template through June 30, 2024.
#>
function Invoke-LedgerRecurringEntry {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [datetime]$Through = (Get-Date).Date,

        [string]$Name
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $templates = if ($Name) {
        @(Get-LedgerRecurringEntry -JournalPath $JournalPath -Name $Name)
    }
    else {
        @(Get-LedgerRecurringEntry -JournalPath $JournalPath)
    }

    $generated = 0

    foreach ($tmpl in $templates) {
        if (-not $tmpl) { continue }
        if ($tmpl.Schedule -ne 'monthly') { continue }

        # Determine start point for generation
        $genStart = if ($tmpl.LastGenerated) {
            $tmpl.LastGenerated.AddDays(1)
        }
        else {
            $tmpl.StartDate
        }

        $endLimit = if ($tmpl.EndDate -lt $Through) { $tmpl.EndDate } else { $Through }

        # Generate monthly entries
        $current = [datetime]::new($genStart.Year, $genStart.Month, 1)
        $lastGen = $tmpl.LastGenerated

        while ($current -le $endLimit) {
            $entryDate = [datetime]::new($current.Year, $current.Month, $tmpl.DayOfMonth)

            if ($entryDate -ge $genStart -and $entryDate -le $endLimit) {
                # Find the fiscal year for this date
                $fiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $entryDate

                if ($fiscalYear) {
                    Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $fiscalYear `
                        -Date $entryDate -Description $tmpl.Description -Rows $tmpl.Rows
                    $lastGen = $entryDate
                    $generated++
                }
            }

            $current = $current.AddMonths(1)
        }

        # Update LastGenerated in the template file
        if ($lastGen -and $lastGen -ne $tmpl.LastGenerated) {
            $content = Get-Content -Path $tmpl.FilePath -Encoding UTF8
            $updated = $content | ForEach-Object {
                if ($_ -match '^LastGenerated:') {
                    "LastGenerated:`t$($lastGen.ToString('yyyy-MM-dd'))"
                }
                else { $_ }
            }
            $updated | Set-Content -Path $tmpl.FilePath -Encoding UTF8
        }
    }

    [PSCustomObject]@{
        Generated = $generated
    }
}

function Find-FiscalYearForDate {
    param (
        [string]$JournalPath,
        [datetime]$Date
    )

    $years = @(Get-LedgerFiscalYear -JournalPath $JournalPath)
    foreach ($y in $years) {
        if ($Date -ge $y.StartDate -and $Date -le $y.EndDate) {
            return $y.Name
        }
    }
    return $null
}
