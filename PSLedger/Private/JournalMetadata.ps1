# Helpers for arbitrary company metadata stored as "Key: Value" lines in a
# journal's journal.txt. Well-known fields (Name, OrgNumber) have dedicated
# parameters and are handled explicitly; everything else is free-form metadata.

# Fields that have first-class parameters / handling and must not be set through
# the generic -Metadata channel.
$script:LedgerReservedJournalKeys = @('Name', 'OrgNumber', 'SchemaVersion', 'CompanyType')

# Allowed values for the CompanyType journal field (Swedish company forms):
# AB = aktiebolag, EF = enskild firma, HB = handelsbolag, KB = kommanditbolag.
$script:LedgerCompanyTypes = @('AB', 'EF', 'HB', 'KB')

# Default equity account the net result is booked to at year-end, per company
# form. Forms without an entry require an explicit -EquityAccount at closing.
$script:LedgerDefaultEquityAccounts = @{
    AB = '2099'
    EF = '2019'
}

function Test-LedgerCompanyType {
    <#
    .SYNOPSIS
    Validates a journal company type against the allowed set, throwing if invalid.

    .DESCRIPTION
    CompanyType is a first-class journal field that drives year-end defaults (for
    example which equity account the net result is booked to). Only the fixed set
    of supported Swedish company forms is accepted.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$CompanyType
    )

    if ($script:LedgerCompanyTypes -notcontains $CompanyType) {
        throw "Invalid company type '$CompanyType'. Allowed values: $($script:LedgerCompanyTypes -join ', ')."
    }
}

function Resolve-LedgerEquityAccount {
    <#
    .SYNOPSIS
    Returns the default equity account a year-end result is booked to, based on
    the journal's CompanyType.

    .DESCRIPTION
    Reads the journal's CompanyType and maps it to the equity account the net
    result is transferred to (see $script:LedgerDefaultEquityAccounts). Throws a
    helpful error when the company form has no default (HB, KB) or the journal has
    no CompanyType, prompting the caller to pass an explicit equity account.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )

    $journal = Get-LedgerJournal -Path $JournalPath
    $companyType = $journal.CompanyType

    if ($companyType -and $script:LedgerDefaultEquityAccounts.ContainsKey($companyType)) {
        return $script:LedgerDefaultEquityAccounts[$companyType]
    }

    if ($companyType) {
        throw "Cannot determine a default equity account for company type '$companyType'. Specify -EquityAccount."
    }

    throw "Cannot determine the equity account: the journal has no CompanyType. Set one with Set-LedgerJournal -CompanyType, or specify -EquityAccount."
}

function Resolve-LedgerResultCarryAccount {
    <#
    .SYNOPSIS
    Returns the equity account a not-yet-booked year-end result is carried into
    when copying opening balances, based on the journal's CompanyType.

    .DESCRIPTION
    Like Resolve-LedgerEquityAccount but never throws: when the CompanyType maps to
    a default equity account (AB -> 2099, EF -> 2019) that account is used;
    otherwise (HB, KB or a journal without a CompanyType) it falls back to 2099
    (Årets resultat, aktiebolag) to preserve backward-compatible behaviour.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )

    $journal = Get-LedgerJournal -Path $JournalPath
    $companyType = $journal.CompanyType

    if ($companyType -and $script:LedgerDefaultEquityAccounts.ContainsKey($companyType)) {
        return $script:LedgerDefaultEquityAccounts[$companyType]
    }

    return '2099'
}

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
