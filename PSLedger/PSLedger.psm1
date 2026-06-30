# Private helpers
. $PSScriptRoot\Private\SieEncoding.ps1
. $PSScriptRoot\Private\SieReader.ps1
. $PSScriptRoot\Private\SieWriter.ps1
. $PSScriptRoot\Private\VatBasMapping.ps1
. $PSScriptRoot\Private\ObjectTagFormat.ps1
. $PSScriptRoot\Private\ExtensionLoader.ps1
. $PSScriptRoot\Private\ResolveJournalPath.ps1
. $PSScriptRoot\Private\ResolveFiscalYear.ps1

# Module-level state
$script:CurrentJournalPath = $null

# Public functions
. $PSScriptRoot\Public\New-LedgerJournal.ps1
. $PSScriptRoot\Public\Get-LedgerJournal.ps1
. $PSScriptRoot\Public\Add-LedgerAccount.ps1
. $PSScriptRoot\Public\Get-LedgerAccount.ps1
. $PSScriptRoot\Public\New-LedgerFiscalYear.ps1
. $PSScriptRoot\Public\Add-LedgerEntry.ps1
. $PSScriptRoot\Public\Get-LedgerEntry.ps1
. $PSScriptRoot\Public\Get-LedgerBalance.ps1
. $PSScriptRoot\Public\Get-LedgerFiscalYear.ps1
. $PSScriptRoot\Public\Close-LedgerFiscalYear.ps1
. $PSScriptRoot\Public\Import-LedgerChart.ps1
. $PSScriptRoot\Public\Get-LedgerIncomeStatement.ps1
. $PSScriptRoot\Public\Get-LedgerBalanceSheet.ps1
. $PSScriptRoot\Public\Copy-LedgerOpeningBalance.ps1
. $PSScriptRoot\Public\Add-LedgerReversal.ps1
. $PSScriptRoot\Public\Test-LedgerSie.ps1
. $PSScriptRoot\Public\Export-LedgerSie.ps1
. $PSScriptRoot\Public\Import-LedgerSie.ps1
. $PSScriptRoot\Public\Get-LedgerLedger.ps1
. $PSScriptRoot\Public\Get-LedgerVatReport.ps1
. $PSScriptRoot\Public\Add-LedgerDimension.ps1
. $PSScriptRoot\Public\Get-LedgerDimension.ps1
. $PSScriptRoot\Public\Add-LedgerObject.ps1
. $PSScriptRoot\Public\Get-LedgerObject.ps1
. $PSScriptRoot\Public\Add-LedgerAccrual.ps1
. $PSScriptRoot\Public\New-LedgerRecurringEntry.ps1
. $PSScriptRoot\Public\Get-LedgerRecurringEntry.ps1
. $PSScriptRoot\Public\Remove-LedgerRecurringEntry.ps1
. $PSScriptRoot\Public\Invoke-LedgerRecurringEntry.ps1
. $PSScriptRoot\Public\Get-LedgerExtension.ps1
. $PSScriptRoot\Public\Set-LedgerCurrentJournal.ps1
. $PSScriptRoot\Public\Clear-LedgerCurrentJournal.ps1
. $PSScriptRoot\Public\Get-LedgerCurrentJournal.ps1
. $PSScriptRoot\Public\Get-LedgerFirstFiscalYear.ps1
. $PSScriptRoot\Public\Get-LedgerLatestFiscalYear.ps1
. $PSScriptRoot\Public\Get-LedgerLatestOpenFiscalYear.ps1
. $PSScriptRoot\Public\Get-LedgerNextFiscalYear.ps1
. $PSScriptRoot\Public\Add-LedgerAttachment.ps1
. $PSScriptRoot\Public\Get-LedgerAttachment.ps1
. $PSScriptRoot\Public\Remove-LedgerAttachment.ps1
. $PSScriptRoot\Public\Add-LedgerDocument.ps1
. $PSScriptRoot\Public\Get-LedgerDocument.ps1
. $PSScriptRoot\Public\Remove-LedgerDocument.ps1

# Export built-in public functions
$script:BuiltInFunctions = @(
    'New-LedgerJournal', 'Get-LedgerJournal', 'Add-LedgerAccount', 'Get-LedgerAccount',
    'New-LedgerFiscalYear', 'Add-LedgerEntry', 'Get-LedgerEntry', 'Get-LedgerBalance',
    'Get-LedgerFiscalYear', 'Close-LedgerFiscalYear', 'Import-LedgerChart',
    'Get-LedgerIncomeStatement', 'Get-LedgerBalanceSheet', 'Copy-LedgerOpeningBalance',
    'Add-LedgerReversal', 'Test-LedgerSie', 'Export-LedgerSie', 'Import-LedgerSie',
    'Get-LedgerLedger', 'Get-LedgerVatReport', 'Add-LedgerDimension', 'Get-LedgerDimension',
    'Add-LedgerObject', 'Get-LedgerObject', 'Add-LedgerAccrual',
    'New-LedgerRecurringEntry', 'Get-LedgerRecurringEntry',
    'Remove-LedgerRecurringEntry', 'Invoke-LedgerRecurringEntry',
    'Get-LedgerExtension', 'Set-LedgerCurrentJournal', 'Clear-LedgerCurrentJournal',
    'Get-LedgerCurrentJournal',
    'Get-LedgerFirstFiscalYear', 'Get-LedgerLatestFiscalYear',
    'Get-LedgerLatestOpenFiscalYear', 'Get-LedgerNextFiscalYear',
    'Add-LedgerAttachment', 'Get-LedgerAttachment', 'Remove-LedgerAttachment',
    'Add-LedgerDocument', 'Get-LedgerDocument', 'Remove-LedgerDocument'
)

# Load extensions at module scope (env variable — semicolon-separated paths)
$script:ExtensionFunctions = @()

if ($env:PSLEDGER_EXTENSIONS) {
    foreach ($extPath in $env:PSLEDGER_EXTENSIONS -split ';') {
        $extPath = $extPath.Trim()
        if ($extPath -and (Test-Path $extPath -PathType Container)) {
            $files = Get-ChildItem -Path $extPath -Filter '*.ps1' -File | Sort-Object Name
            foreach ($file in $files) {
                $funcsBefore = (Get-ChildItem function:).Name
                try {
                    . $file.FullName
                }
                catch {
                    Write-Warning "PSLedger extension failed to load: $($file.FullName) — $($_.Exception.Message)"
                    continue
                }
                $funcsAfter = (Get-ChildItem function:).Name
                $newFuncs = @($funcsAfter | Where-Object { $_ -notin $funcsBefore })
                $script:ExtensionFunctions += $newFuncs
                Register-LedgerExtension -Name $file.BaseName -Path $file.FullName -Source 'Env' -Functions $newFuncs
            }
        }
    }
}

# Load extensions from user-level directory
$userExtPath = if ($env:PSLEDGER_USER_EXTENSIONS) {
    $env:PSLEDGER_USER_EXTENSIONS
} else {
    Join-Path $HOME '.psledger' 'Extensions'
}
if (Test-Path $userExtPath -PathType Container) {
    $files = Get-ChildItem -Path $userExtPath -Filter '*.ps1' -File | Sort-Object Name
    foreach ($file in $files) {
        $funcsBefore = (Get-ChildItem function:).Name
        try {
            . $file.FullName
        }
        catch {
            Write-Warning "PSLedger extension failed to load: $($file.FullName) — $($_.Exception.Message)"
            continue
        }
        $funcsAfter = (Get-ChildItem function:).Name
        $newFuncs = @($funcsAfter | Where-Object { $_ -notin $funcsBefore })
        $script:ExtensionFunctions += $newFuncs
        Register-LedgerExtension -Name $file.BaseName -Path $file.FullName -Source 'User' -Functions $newFuncs
    }
}

Export-ModuleMember -Function ($script:BuiltInFunctions + $script:ExtensionFunctions)
