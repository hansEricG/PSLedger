function Resolve-LedgerJournalPath {
    <#
    .SYNOPSIS
    Resolves the journal path from a parameter value or the current journal state.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath
    )

    if ($JournalPath) {
        return $JournalPath
    }

    if ($script:CurrentJournalPath) {
        return $script:CurrentJournalPath
    }

    throw "No journal specified. Use -JournalPath or set a current journal with Set-LedgerCurrentJournal."
}
