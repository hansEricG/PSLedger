# Helpers that keep values written to the plain-text files on a single line.
#
# The files have no quoting or escape syntax (see docs/File-format.md), so a tab
# or a line break inside a value would split a record or a header line. Free
# text (names, descriptions, references) is normalised; identifiers, which are
# used for lookups and file names, are rejected instead of silently changed.

function ConvertTo-LedgerTextField {
    <#
    .SYNOPSIS
    Replaces tabs and line breaks with a single space and trims the value.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value
    )
    if ($null -eq $Value) { return '' }
    return ([string]$Value -replace '[\t\r\n]+', ' ').Trim()
}

function Assert-LedgerKeyField {
    <#
    .SYNOPSIS
    Throws if an identifier contains a tab or a line break.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )
    if ($Value -match '[\t\r\n]') {
        throw "$Name must not contain tabs or line breaks."
    }
}
