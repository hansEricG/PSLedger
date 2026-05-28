<#
.SYNOPSIS
Lists recurring entry templates in the journal.

.DESCRIPTION
Reads all recurring entry templates from the journal's 'recurring/' directory
and returns them as objects with their metadata and row definitions.

.PARAMETER JournalPath
Path to the journal (.ledger directory).

.PARAMETER Name
Optional name filter. If specified, returns only the template with that name.

.EXAMPLE
Get-LedgerRecurringEntry -JournalPath .\ab.ledger

Lists all recurring entry templates.

.EXAMPLE
Get-LedgerRecurringEntry -JournalPath .\ab.ledger -Name 'Hyra'

Returns the specific recurring entry template named 'Hyra'.
#>
function Get-LedgerRecurringEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [string]$Name
    )

    $recurringDir = Join-Path $JournalPath 'recurring'
    if (-not (Test-Path $recurringDir)) { return }

    $files = if ($Name) {
        $filePath = Join-Path $recurringDir "$Name.txt"
        if (Test-Path $filePath) { @(Get-Item $filePath) } else { @() }
    }
    else {
        @(Get-ChildItem -Path $recurringDir -Filter '*.txt')
    }

    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName -Encoding UTF8
        $meta = @{}
        $rows = @()
        $inRows = $false

        foreach ($line in $content) {
            if ($line -eq 'Rows:') {
                $inRows = $true
                continue
            }
            if ($inRows) {
                $parts = $line -split "`t"
                if ($parts.Count -ge 2) {
                    $rows += @{ Account = $parts[0]; Amount = [decimal]$parts[1] }
                }
            }
            else {
                $parts = $line -split "`t", 2
                if ($parts.Count -ge 2) {
                    $meta[$parts[0].TrimEnd(':')] = $parts[1]
                }
            }
        }

        [PSCustomObject]@{
            Name          = $meta['Name']
            Description   = $meta['Description']
            Schedule      = $meta['Schedule']
            DayOfMonth    = [int]$meta['DayOfMonth']
            StartDate     = if ($meta['StartDate']) { [datetime]::ParseExact($meta['StartDate'], 'yyyy-MM-dd', $null) } else { $null }
            EndDate       = if ($meta['EndDate']) { [datetime]::ParseExact($meta['EndDate'], 'yyyy-MM-dd', $null) } else { $null }
            LastGenerated = if ($meta['LastGenerated']) { [datetime]::ParseExact($meta['LastGenerated'], 'yyyy-MM-dd', $null) } else { $null }
            Rows          = $rows
            FilePath      = $file.FullName
        }
    }
}
