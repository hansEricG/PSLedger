# Private helpers
. $PSScriptRoot\Private\SieEncoding.ps1
. $PSScriptRoot\Private\SieReader.ps1
. $PSScriptRoot\Private\SieWriter.ps1
. $PSScriptRoot\Private\VatBasMapping.ps1
. $PSScriptRoot\Private\ObjectTagFormat.ps1
. $PSScriptRoot\Private\ExtensionLoader.ps1
. $PSScriptRoot\Private\ResolveJournalPath.ps1
. $PSScriptRoot\Private\ResolveFiscalYear.ps1
. $PSScriptRoot\Private\OpeningBalance.ps1
. $PSScriptRoot\Private\JournalSchema.ps1
. $PSScriptRoot\Private\JournalMetadata.ps1
. $PSScriptRoot\Private\AnnualReportInput.ps1
. $PSScriptRoot\Private\AnnualReportFormat.ps1
. $PSScriptRoot\Private\AnnualReportNotes.ps1
. $PSScriptRoot\Private\AnnualReportRender.ps1
. $PSScriptRoot\Private\AnnualReportModel.ps1
. $PSScriptRoot\Private\InvoiceStore.ps1
. $PSScriptRoot\Private\SupplierInvoiceStore.ps1
. $PSScriptRoot\Private\OcrReference.ps1
. $PSScriptRoot\Private\InvoiceCharge.ps1
. $PSScriptRoot\Private\PdfWriter.ps1
. $PSScriptRoot\Private\Migrations.ps1

# Module-level state
$script:CurrentJournalPath = $null
$script:CurrentFiscalYear = $null

# Public functions
. $PSScriptRoot\Public\New-LedgerJournal.ps1
. $PSScriptRoot\Public\Get-LedgerJournal.ps1
. $PSScriptRoot\Public\Set-LedgerJournal.ps1
. $PSScriptRoot\Public\Add-LedgerAccount.ps1
. $PSScriptRoot\Public\Get-LedgerAccount.ps1
. $PSScriptRoot\Public\New-LedgerFiscalYear.ps1
. $PSScriptRoot\Public\Add-LedgerEntry.ps1
. $PSScriptRoot\Public\New-LedgerEntryRow.ps1
. $PSScriptRoot\Public\Get-LedgerEntry.ps1
. $PSScriptRoot\Public\Get-LedgerBalance.ps1
. $PSScriptRoot\Public\Get-LedgerFiscalYear.ps1
. $PSScriptRoot\Public\Close-LedgerFiscalYear.ps1
. $PSScriptRoot\Public\Test-LedgerFiscalYear.ps1
. $PSScriptRoot\Public\Import-LedgerChart.ps1
. $PSScriptRoot\Public\Get-LedgerIncomeStatement.ps1
. $PSScriptRoot\Public\Get-LedgerBalanceSheet.ps1
. $PSScriptRoot\Public\Copy-LedgerOpeningBalance.ps1
. $PSScriptRoot\Public\Update-LedgerJournal.ps1
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
. $PSScriptRoot\Public\Add-LedgerDepreciation.ps1
. $PSScriptRoot\Public\Get-LedgerTaxEstimate.ps1
. $PSScriptRoot\Public\Add-LedgerTaxEntry.ps1
. $PSScriptRoot\Public\Add-LedgerAppropriation.ps1
. $PSScriptRoot\Public\Get-LedgerAnnualReport.ps1
. $PSScriptRoot\Public\Export-LedgerAnnualReport.ps1
. $PSScriptRoot\Public\Set-LedgerReportInput.ps1
. $PSScriptRoot\Public\Get-LedgerReportInput.ps1
. $PSScriptRoot\Public\Get-LedgerMultiYearOverview.ps1
. $PSScriptRoot\Public\Get-LedgerEquityReconciliation.ps1
. $PSScriptRoot\Public\Get-LedgerProfitDisposition.ps1
. $PSScriptRoot\Public\Get-LedgerFixedAssetNote.ps1
. $PSScriptRoot\Public\Get-LedgerShareholdingNote.ps1
. $PSScriptRoot\Public\Get-LedgerEmployeeNote.ps1
. $PSScriptRoot\Public\Get-LedgerAccountingPrinciples.ps1
. $PSScriptRoot\Public\Get-LedgerCompanyProfile.ps1
. $PSScriptRoot\Public\New-LedgerRecurringEntry.ps1
. $PSScriptRoot\Public\Get-LedgerRecurringEntry.ps1
. $PSScriptRoot\Public\Remove-LedgerRecurringEntry.ps1
. $PSScriptRoot\Public\Invoke-LedgerRecurringEntry.ps1
. $PSScriptRoot\Public\Get-LedgerExtension.ps1
. $PSScriptRoot\Public\Set-LedgerCurrentJournal.ps1
. $PSScriptRoot\Public\Clear-LedgerCurrentJournal.ps1
. $PSScriptRoot\Public\Get-LedgerCurrentJournal.ps1
. $PSScriptRoot\Public\Set-LedgerCurrentFiscalYear.ps1
. $PSScriptRoot\Public\Clear-LedgerCurrentFiscalYear.ps1
. $PSScriptRoot\Public\Get-LedgerCurrentFiscalYear.ps1
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
. $PSScriptRoot\Public\Backup-LedgerJournal.ps1
. $PSScriptRoot\Public\Restore-LedgerJournal.ps1
. $PSScriptRoot\Public\Add-LedgerCustomer.ps1
. $PSScriptRoot\Public\Get-LedgerCustomer.ps1
. $PSScriptRoot\Public\Set-LedgerCustomer.ps1
. $PSScriptRoot\Public\New-LedgerInvoice.ps1
. $PSScriptRoot\Public\Get-LedgerInvoice.ps1
. $PSScriptRoot\Public\Invoke-LedgerInvoicePosting.ps1
. $PSScriptRoot\Public\Add-LedgerInvoicePayment.ps1
. $PSScriptRoot\Public\Export-LedgerInvoice.ps1
. $PSScriptRoot\Public\Get-LedgerAccountsReceivable.ps1
. $PSScriptRoot\Public\Add-LedgerCreditInvoice.ps1
. $PSScriptRoot\Public\Add-LedgerInvoiceReminder.ps1
. $PSScriptRoot\Public\Add-LedgerInvoiceFee.ps1
. $PSScriptRoot\Public\Add-LedgerInvoiceInterest.ps1
. $PSScriptRoot\Public\Add-LedgerSupplier.ps1
. $PSScriptRoot\Public\Get-LedgerSupplier.ps1
. $PSScriptRoot\Public\Set-LedgerSupplier.ps1
. $PSScriptRoot\Public\New-LedgerSupplierInvoice.ps1
. $PSScriptRoot\Public\Get-LedgerSupplierInvoice.ps1
. $PSScriptRoot\Public\Invoke-LedgerSupplierInvoicePosting.ps1
. $PSScriptRoot\Public\Add-LedgerSupplierPayment.ps1
. $PSScriptRoot\Public\Get-LedgerAccountsPayable.ps1

# Export built-in public functions
$script:BuiltInFunctions = @(
    'New-LedgerJournal', 'Get-LedgerJournal', 'Set-LedgerJournal', 'Add-LedgerAccount', 'Get-LedgerAccount',
    'New-LedgerFiscalYear', 'Add-LedgerEntry', 'New-LedgerEntryRow', 'Get-LedgerEntry', 'Get-LedgerBalance',
    'Get-LedgerFiscalYear', 'Close-LedgerFiscalYear', 'Test-LedgerFiscalYear', 'Import-LedgerChart',
    'Get-LedgerIncomeStatement', 'Get-LedgerBalanceSheet', 'Copy-LedgerOpeningBalance',
    'Update-LedgerJournal',
    'Add-LedgerReversal', 'Test-LedgerSie', 'Export-LedgerSie', 'Import-LedgerSie',
    'Get-LedgerLedger', 'Get-LedgerVatReport', 'Add-LedgerDimension', 'Get-LedgerDimension',
    'Add-LedgerObject', 'Get-LedgerObject', 'Add-LedgerAccrual', 'Add-LedgerDepreciation',
    'Get-LedgerTaxEstimate', 'Add-LedgerTaxEntry', 'Add-LedgerAppropriation',
    'Get-LedgerAnnualReport', 'Export-LedgerAnnualReport',
    'Set-LedgerReportInput', 'Get-LedgerReportInput',
    'Get-LedgerMultiYearOverview',
    'Get-LedgerEquityReconciliation',
    'Get-LedgerProfitDisposition',
    'Get-LedgerFixedAssetNote',
    'Get-LedgerShareholdingNote', 'Get-LedgerEmployeeNote',
    'Get-LedgerAccountingPrinciples',
    'Get-LedgerCompanyProfile',
    'New-LedgerRecurringEntry', 'Get-LedgerRecurringEntry',
    'Remove-LedgerRecurringEntry', 'Invoke-LedgerRecurringEntry',
    'Get-LedgerExtension', 'Set-LedgerCurrentJournal', 'Clear-LedgerCurrentJournal',
    'Get-LedgerCurrentJournal',
    'Set-LedgerCurrentFiscalYear', 'Clear-LedgerCurrentFiscalYear',
    'Get-LedgerCurrentFiscalYear',
    'Get-LedgerFirstFiscalYear', 'Get-LedgerLatestFiscalYear',
    'Get-LedgerLatestOpenFiscalYear', 'Get-LedgerNextFiscalYear',
    'Add-LedgerAttachment', 'Get-LedgerAttachment', 'Remove-LedgerAttachment',
    'Add-LedgerDocument', 'Get-LedgerDocument', 'Remove-LedgerDocument',
    'Backup-LedgerJournal', 'Restore-LedgerJournal',
    'Add-LedgerCustomer', 'Get-LedgerCustomer', 'Set-LedgerCustomer',
    'New-LedgerInvoice', 'Get-LedgerInvoice', 'Invoke-LedgerInvoicePosting',
    'Add-LedgerInvoicePayment', 'Export-LedgerInvoice',
    'Get-LedgerAccountsReceivable', 'Add-LedgerCreditInvoice',
    'Add-LedgerInvoiceReminder',
    'Add-LedgerInvoiceFee', 'Add-LedgerInvoiceInterest',
    'Add-LedgerSupplier', 'Get-LedgerSupplier', 'Set-LedgerSupplier',
    'New-LedgerSupplierInvoice', 'Get-LedgerSupplierInvoice',
    'Invoke-LedgerSupplierInvoicePosting', 'Add-LedgerSupplierPayment',
    'Get-LedgerAccountsPayable'
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
