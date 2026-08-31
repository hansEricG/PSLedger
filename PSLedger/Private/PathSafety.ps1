# Helpers for safely turning caller-supplied names into paths.
#
# Commands that accept a file or template *name* and join it onto an internal
# directory (attachments, documents, recurring templates) must ensure the name
# is a plain leaf. Otherwise a value such as '..\..\journal.txt' would let a
# delete or write escape the intended directory (path traversal).

function Assert-LedgerSafeLeafName {
    <#
    .SYNOPSIS
    Validates that a caller-supplied name is a plain file/leaf name and returns it.

    .DESCRIPTION
    Throws if the name is empty, contains a path separator, is drive- or
    root-qualified, or is a relative-directory reference ('.' or '..'). On
    success the original name is returned so callers can write
    "$Name = Assert-LedgerSafeLeafName -Name $Name".
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name,

        # Noun used in the error message (e.g. 'attachment', 'document').
        [Parameter()]
        [string]$Kind = 'file'
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Invalid $Kind name: the name must not be empty."
    }

    if ($Name.IndexOfAny([char[]]('/', '\')) -ge 0 -or
        [System.IO.Path]::IsPathRooted($Name) -or
        $Name -eq '.' -or $Name -eq '..' -or
        [System.IO.Path]::GetFileName($Name) -ne $Name) {
        throw "Invalid $Kind name '$Name': only a plain file name is allowed (no path separators, drive qualifiers or '..')."
    }

    return $Name
}
