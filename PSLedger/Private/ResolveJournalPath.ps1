function Resolve-LedgerJournalPath {
    <#
    .SYNOPSIS
    Resolves the journal path from a parameter value or the current journal state.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [ValidateSet('None', 'Read', 'Write')]
        [string]$SchemaCheck = 'Read'
    )

    $resolved = if ($JournalPath) {
        $JournalPath
    }
    elseif ($script:CurrentJournalPath) {
        $script:CurrentJournalPath
    }
    else {
        throw "No journal specified. Use -JournalPath or set a current journal with Set-LedgerCurrentJournal."
    }

    if ($SchemaCheck -ne 'None') {
        Assert-LedgerJournalSchema -Path $resolved -Write:($SchemaCheck -eq 'Write')
    }

    return $resolved
}
