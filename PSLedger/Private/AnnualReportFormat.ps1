# Shared formatting helpers for the annual report (årsredovisning): fiscal year
# column labels and Swedish-formatted amounts. Kept separate so the report
# building, multi-year overview and export commands render figures identically.

function Format-LedgerYearLabel {
    <#
    .SYNOPSIS
    Produces a human-readable label for a fiscal year identifier.

    .DESCRIPTION
    A fiscal year that starts and ends in the same calendar year (e.g.
    '2024-01_2024-12') is labelled with that year ('2024'). A broken fiscal year
    that spans two calendar years (e.g. '2024-09_2025-08') is labelled with both
    ('2024/2025'), mirroring how such years are shown in a printed årsredovisning.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FiscalYear
    )

    if ($FiscalYear -match '^(\d{4})-\d{2}_(\d{4})-\d{2}$') {
        $start = $Matches[1]
        $end = $Matches[2]
        if ($start -eq $end) { return $end }
        return "$start/$end"
    }
    return $FiscalYear
}

function Format-LedgerAmount {
    <#
    .SYNOPSIS
    Formats a numeric amount using Swedish conventions (space thousands
    separator, comma decimal).

    .DESCRIPTION
    Returns an empty string for $null. Otherwise formats the value with the
    requested number of decimals in the sv-SE culture. Used so every part of the
    annual report renders amounts consistently.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [AllowNull()]
        $Value,

        [Parameter()]
        [int]$Decimals = 2
    )

    if ($null -eq $Value) { return '' }
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('sv-SE')
    ([decimal]$Value).ToString("N$Decimals", $culture)
}
