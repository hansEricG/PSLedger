# Helpers for parsing and formatting object tags on verification rows.
# Format: {1:cs01,2:proj-a}  — dimension:object pairs separated by comma
# inside braces.

function Format-ObjectTag {
    [CmdletBinding()]
    param (
        [hashtable]$Objects
    )

    if (-not $Objects -or $Objects.Count -eq 0) { return '' }

    $parts = foreach ($key in ($Objects.Keys | Sort-Object)) {
        "$key`:$($Objects[$key])"
    }
    '{' + ($parts -join ',') + '}'
}

function ConvertFrom-ObjectTag {
    [CmdletBinding()]
    param (
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Tag
    )

    if (-not $Tag -or $Tag -eq '') { return $null }

    $inner = $Tag.TrimStart('{').TrimEnd('}')
    if (-not $inner) { return $null }

    $result = @{}
    foreach ($pair in ($inner -split ',')) {
        $parts = $pair -split ':', 2
        if ($parts.Count -eq 2) {
            $result[[int]$parts[0]] = $parts[1]
        }
    }

    if ($result.Count -eq 0) { return $null }
    $result
}
