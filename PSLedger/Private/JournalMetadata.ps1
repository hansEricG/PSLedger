# Helpers for arbitrary company metadata stored as "Key: Value" lines in a
# journal's journal.txt. Well-known fields (Name, OrgNumber) have dedicated
# parameters and are handled explicitly; everything else is free-form metadata.

# Fields that have first-class parameters / handling and must not be set through
# the generic -Metadata channel.
$script:LedgerReservedJournalKeys = @('Name', 'OrgNumber', 'SchemaVersion')

function Test-LedgerMetadataKey {
    <#
    .SYNOPSIS
    Validates a journal metadata key, throwing if it is reserved or malformed.

    .DESCRIPTION
    Metadata is persisted as "Key: Value" lines, so keys must be simple
    identifiers (start with a letter; letters, digits and underscores only) to
    keep the plain-text format unambiguous. Reserved keys are rejected with a
    hint to use the dedicated parameter instead.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Key
    )

    if ($Key -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        throw "Invalid metadata key '$Key'. Keys must start with a letter and contain only letters, digits and underscores."
    }

    if ($script:LedgerReservedJournalKeys -contains $Key) {
        throw "'$Key' is a reserved journal field. Use the -$Key parameter instead of -Metadata."
    }
}

function Format-LedgerMetadataValue {
    <#
    .SYNOPSIS
    Normalises a metadata value so it occupies a single journal.txt line.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    # Collapse any newlines so each field stays on a single line.
    return ($Value -replace '\r?\n', ' ')
}
