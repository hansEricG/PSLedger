# PSScriptAnalyzer settings for PSLedger, used locally and in CI:
#   Invoke-ScriptAnalyzer -Path ./PSLedger -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Source files are UTF-8 without BOM; PowerShell 7 reads them correctly.
        'PSUseBOMForUnicodeEncodedFile'
        # Private helpers that read or write collections use plural nouns
        # (Read-LedgerTimeEntries). Public names are reviewed before 1.0.
        'PSUseSingularNouns'
        # Private New-* helpers only build objects, and the Set-LedgerCurrent*
        # commands only change session state. Write commands are covered by
        # Tests/ShouldProcess.Tests.ps1 instead.
        'PSUseShouldProcessForStateChangingFunctions'
        # False positive: -Debit/-Credit on New-LedgerEntryRow are amounts.
        'PSAvoidUsingPlainTextForPassword'
        # FunctionsToExport becomes an explicit list with publishing (ROADMAP step 5).
        'PSUseToExportFieldsInManifest'
    )
}
