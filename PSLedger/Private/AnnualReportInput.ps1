# Helpers for per-fiscal-year annual report input stored as report.txt in a
# fiscal year directory. This holds the year-specific narrative and decision
# data that cannot be derived from the bookkeeping itself (significant events,
# proposed dividend, average number of employees, securities market value and
# the signing place/date). It mirrors the plain-text, one-optional-file-per-year
# ethos of ib.txt (the opening balance metadata).
#
# The file format is line based and UTF-8:
#   * "# ..."          - a comment (ignored on read).
#   * "Key: value"     - a scalar field on a single line.
#   * "## Key"         - starts a multi-line text block; every following line
#                        belongs to the block until the next "## " header or EOF.
# Scalars are always written before any block so a value that happens to contain
# a "Word:" prefix inside a block is never mistaken for a new scalar field.

# The canonical file name for annual report input inside a fiscal year directory.
$script:LedgerReportInputFileName = 'report.txt'

function Get-LedgerReportInputPath {
    <#
    .SYNOPSIS
    Returns the full path to the report.txt input file for a fiscal year.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear
    )

    Join-Path (Join-Path $JournalPath $FiscalYear) $script:LedgerReportInputFileName
}

function Read-LedgerReportInput {
    <#
    .SYNOPSIS
    Reads a report.txt annual report input file into an ordered dictionary.

    .DESCRIPTION
    Parses the plain-text report.txt format (scalars as "Key: value" and
    multi-line "## Key" blocks) into an ordered dictionary of field name to
    value. Multi-line block values keep their internal newlines (joined with
    "`n") with trailing blank lines trimmed. Returns an empty ordered
    dictionary when the file does not exist.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $fields = [ordered]@{}
    if (-not (Test-Path $Path)) {
        return $fields
    }

    $currentSection = $null
    $sectionLines = $null

    $flush = {
        if ($null -ne $currentSection) {
            # Trim trailing blank lines from the collected block.
            $end = $sectionLines.Count - 1
            while ($end -ge 0 -and [string]::IsNullOrWhiteSpace($sectionLines[$end])) {
                $end--
            }
            $text = if ($end -ge 0) { ($sectionLines[0..$end] -join "`n") } else { '' }
            $fields[$currentSection] = $text
        }
    }

    foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
        if ($line -match '^##\s+(.+?)\s*$') {
            & $flush
            $currentSection = $Matches[1]
            $sectionLines = [System.Collections.Generic.List[string]]::new()
            continue
        }

        if ($null -ne $currentSection) {
            $sectionLines.Add($line)
            continue
        }

        if ($line -match '^\s*#') {
            continue
        }
        if ($line -match '^([A-Za-z][A-Za-z0-9_]*):\s?(.*)$') {
            $fields[$Matches[1]] = $Matches[2]
        }
    }

    & $flush
    return $fields
}

function Write-LedgerReportInput {
    <#
    .SYNOPSIS
    Writes an ordered dictionary of annual report input fields to report.txt.

    .DESCRIPTION
    Serialises the supplied fields to the plain-text report.txt format as UTF-8.
    A field whose value contains a newline is written as a multi-line "## Key"
    block; every other field is written as a single "Key: value" scalar line.
    Scalars are written first, then blocks, so the file round-trips cleanly.
    Fields with a $null or empty value are omitted.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Fields
    )

    $scalars = [System.Collections.Generic.List[string]]::new()
    $blocks = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $Fields.Keys) {
        $value = $Fields[$key]
        if ($null -eq $value -or [string]::IsNullOrEmpty([string]$value)) {
            continue
        }
        $text = [string]$value
        if ($text -match '\r?\n') {
            $normalised = $text -replace '\r?\n', "`n"
            $blocks.Add('')
            $blocks.Add("## $key")
            foreach ($blockLine in ($normalised -split "`n")) {
                $blocks.Add($blockLine)
            }
        }
        else {
            $scalars.Add("${key}: $text")
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# PSLedger annual report input')
    foreach ($s in $scalars) { $lines.Add($s) }
    foreach ($b in $blocks) { $lines.Add($b) }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Set-LedgerFileContent -Path $Path -Value $lines
}
