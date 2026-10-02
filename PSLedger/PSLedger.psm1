# Private helpers
. $PSScriptRoot\Private\SieEncoding.ps1
. $PSScriptRoot\Private\SieReader.ps1
. $PSScriptRoot\Private\SieWriter.ps1
. $PSScriptRoot\Private\VatBasMapping.ps1
. $PSScriptRoot\Private\SruMapping.ps1
. $PSScriptRoot\Private\ObjectTagFormat.ps1
. $PSScriptRoot\Private\ExtensionLoader.ps1
. $PSScriptRoot\Private\ResolveJournalPath.ps1
. $PSScriptRoot\Private\ResolveFiscalYear.ps1
. $PSScriptRoot\Private\PathSafety.ps1
. $PSScriptRoot\Private\FileWrite.ps1
. $PSScriptRoot\Private\TextField.ps1
. $PSScriptRoot\Private\Integrity.ps1
. $PSScriptRoot\Private\Archive.ps1
. $PSScriptRoot\Private\OpeningBalance.ps1
. $PSScriptRoot\Private\Holdings.ps1
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
. $PSScriptRoot\Private\PayslipStore.ps1
. $PSScriptRoot\Private\BankStore.ps1
. $PSScriptRoot\Private\BankImport.ps1
. $PSScriptRoot\Private\BankMatching.ps1
. $PSScriptRoot\Private\TimeStore.ps1
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
. $PSScriptRoot\Public\Test-LedgerIntegrity.ps1
. $PSScriptRoot\Public\Protect-LedgerFiscalYear.ps1
. $PSScriptRoot\Public\Import-LedgerChart.ps1
. $PSScriptRoot\Public\Get-LedgerIncomeStatement.ps1
. $PSScriptRoot\Public\Get-LedgerBalanceSheet.ps1
. $PSScriptRoot\Public\Copy-LedgerOpeningBalance.ps1
. $PSScriptRoot\Public\Update-LedgerJournal.ps1
. $PSScriptRoot\Public\Add-LedgerReversal.ps1
. $PSScriptRoot\Public\Test-LedgerSie.ps1
. $PSScriptRoot\Public\Export-LedgerSie.ps1
. $PSScriptRoot\Public\Export-LedgerArchive.ps1
. $PSScriptRoot\Public\Test-LedgerArchive.ps1
. $PSScriptRoot\Public\Import-LedgerSie.ps1
. $PSScriptRoot\Public\Get-LedgerGeneralLedger.ps1
. $PSScriptRoot\Public\Get-LedgerVatReport.ps1
. $PSScriptRoot\Public\Export-LedgerVatDeclaration.ps1
. $PSScriptRoot\Public\Export-LedgerIncomeTaxReturn.ps1
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
. $PSScriptRoot\Public\Set-LedgerHolding.ps1
. $PSScriptRoot\Public\Get-LedgerHolding.ps1
. $PSScriptRoot\Public\Remove-LedgerHolding.ps1
. $PSScriptRoot\Public\Copy-LedgerHolding.ps1
. $PSScriptRoot\Public\Add-LedgerImpairment.ps1
. $PSScriptRoot\Public\Get-LedgerMultiYearOverview.ps1
. $PSScriptRoot\Public\Get-LedgerEquityReconciliation.ps1
. $PSScriptRoot\Public\Get-LedgerProfitDisposition.ps1
. $PSScriptRoot\Public\Add-LedgerProfitDisposition.ps1
. $PSScriptRoot\Public\Get-LedgerFixedAssetNote.ps1
. $PSScriptRoot\Public\Get-LedgerShareholdingNote.ps1
. $PSScriptRoot\Public\Get-LedgerEmployeeNote.ps1
. $PSScriptRoot\Public\Get-LedgerAccountingPrinciple.ps1
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
. $PSScriptRoot\Public\Add-LedgerEmployee.ps1
. $PSScriptRoot\Public\Get-LedgerEmployee.ps1
. $PSScriptRoot\Public\Set-LedgerEmployee.ps1
. $PSScriptRoot\Public\New-LedgerPayslip.ps1
. $PSScriptRoot\Public\Get-LedgerPayslip.ps1
. $PSScriptRoot\Public\Invoke-LedgerPayrollPosting.ps1
. $PSScriptRoot\Public\Add-LedgerPayrollTaxPayment.ps1
. $PSScriptRoot\Public\Add-LedgerVacationLiability.ps1
. $PSScriptRoot\Public\Export-LedgerPayslip.ps1
. $PSScriptRoot\Public\Export-LedgerEmployerDeclaration.ps1
. $PSScriptRoot\Public\Import-LedgerBankStatement.ps1
. $PSScriptRoot\Public\Get-LedgerBankStatement.ps1
. $PSScriptRoot\Public\Get-LedgerBankTransaction.ps1
. $PSScriptRoot\Public\Invoke-LedgerBankMatching.ps1
. $PSScriptRoot\Public\Set-LedgerBankTransaction.ps1
. $PSScriptRoot\Public\Get-LedgerBankReconciliation.ps1
. $PSScriptRoot\Public\Add-LedgerBankRule.ps1
. $PSScriptRoot\Public\Get-LedgerBankRule.ps1
. $PSScriptRoot\Public\Remove-LedgerBankRule.ps1
. $PSScriptRoot\Public\Add-LedgerTimeResource.ps1
. $PSScriptRoot\Public\Get-LedgerTimeResource.ps1
. $PSScriptRoot\Public\Set-LedgerTimeResource.ps1
. $PSScriptRoot\Public\Add-LedgerProject.ps1
. $PSScriptRoot\Public\Get-LedgerProject.ps1
. $PSScriptRoot\Public\Set-LedgerProject.ps1
. $PSScriptRoot\Public\Add-LedgerTimeEntry.ps1
. $PSScriptRoot\Public\Get-LedgerTimeEntry.ps1
. $PSScriptRoot\Public\Set-LedgerTimeEntry.ps1
. $PSScriptRoot\Public\Remove-LedgerTimeEntry.ps1
. $PSScriptRoot\Public\Import-LedgerTimeEntry.ps1
. $PSScriptRoot\Public\Get-LedgerTimeReport.ps1
. $PSScriptRoot\Public\New-LedgerTimeInvoice.ps1

# Export built-in public functions
$script:BuiltInFunctions = @(
    'New-LedgerJournal', 'Get-LedgerJournal', 'Set-LedgerJournal', 'Add-LedgerAccount', 'Get-LedgerAccount',
    'New-LedgerFiscalYear', 'Add-LedgerEntry', 'New-LedgerEntryRow', 'Get-LedgerEntry', 'Get-LedgerBalance',
    'Get-LedgerFiscalYear', 'Close-LedgerFiscalYear', 'Test-LedgerFiscalYear', 'Test-LedgerIntegrity', 'Protect-LedgerFiscalYear', 'Import-LedgerChart',
    'Get-LedgerIncomeStatement', 'Get-LedgerBalanceSheet', 'Copy-LedgerOpeningBalance',
    'Update-LedgerJournal',
    'Add-LedgerReversal', 'Test-LedgerSie', 'Export-LedgerSie', 'Import-LedgerSie', 'Export-LedgerArchive', 'Test-LedgerArchive',
    'Get-LedgerGeneralLedger', 'Get-LedgerVatReport', 'Export-LedgerVatDeclaration',
    'Export-LedgerIncomeTaxReturn',
    'Add-LedgerDimension', 'Get-LedgerDimension',
    'Add-LedgerObject', 'Get-LedgerObject', 'Add-LedgerAccrual', 'Add-LedgerDepreciation',
    'Get-LedgerTaxEstimate', 'Add-LedgerTaxEntry', 'Add-LedgerAppropriation',
    'Get-LedgerAnnualReport', 'Export-LedgerAnnualReport',
    'Set-LedgerReportInput', 'Get-LedgerReportInput',
    'Set-LedgerHolding', 'Get-LedgerHolding', 'Remove-LedgerHolding', 'Copy-LedgerHolding',
    'Add-LedgerImpairment',
    'Get-LedgerMultiYearOverview',
    'Get-LedgerEquityReconciliation',
    'Get-LedgerProfitDisposition', 'Add-LedgerProfitDisposition',
    'Get-LedgerFixedAssetNote',
    'Get-LedgerShareholdingNote', 'Get-LedgerEmployeeNote',
    'Get-LedgerAccountingPrinciple',
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
    'Get-LedgerAccountsPayable',
    'Add-LedgerEmployee', 'Get-LedgerEmployee', 'Set-LedgerEmployee',
    'New-LedgerPayslip', 'Get-LedgerPayslip', 'Invoke-LedgerPayrollPosting',
    'Add-LedgerPayrollTaxPayment', 'Add-LedgerVacationLiability',
    'Export-LedgerPayslip', 'Export-LedgerEmployerDeclaration',
    'Import-LedgerBankStatement', 'Get-LedgerBankStatement', 'Get-LedgerBankTransaction',
    'Invoke-LedgerBankMatching', 'Set-LedgerBankTransaction', 'Get-LedgerBankReconciliation',
    'Add-LedgerBankRule', 'Get-LedgerBankRule', 'Remove-LedgerBankRule',
    'Add-LedgerTimeResource', 'Get-LedgerTimeResource', 'Set-LedgerTimeResource',
    'Add-LedgerProject', 'Get-LedgerProject', 'Set-LedgerProject',
    'Add-LedgerTimeEntry', 'Get-LedgerTimeEntry', 'Set-LedgerTimeEntry', 'Remove-LedgerTimeEntry',
    'Import-LedgerTimeEntry', 'Get-LedgerTimeReport', 'New-LedgerTimeInvoice'
)

# Load extensions from the environment (semicolon-separated paths) and the
# user-level directory. Extension functions are created as global functions
# bound to the module scope (so they can call private helpers), because the
# manifest only exports the built-in commands.
$extensionDirs = @()
if ($env:PSLEDGER_EXTENSIONS) {
    foreach ($extPath in $env:PSLEDGER_EXTENSIONS -split ';') {
        $extPath = $extPath.Trim()
        if ($extPath) { $extensionDirs += [PSCustomObject]@{ Path = $extPath; Source = 'Env' } }
    }
}
$userExtPath = if ($env:PSLEDGER_USER_EXTENSIONS) {
    $env:PSLEDGER_USER_EXTENSIONS
} else {
    Join-Path $HOME '.psledger' 'Extensions'
}
$extensionDirs += [PSCustomObject]@{ Path = $userExtPath; Source = 'User' }

foreach ($dir in $extensionDirs) {
    if (Test-Path $dir.Path -PathType Container) {
        foreach ($file in (Get-ChildItem -Path $dir.Path -Filter '*.ps1' -File | Sort-Object Name)) {
            Import-LedgerExtensionRuntime -Path $file.FullName -Source $dir.Source
        }
    }
}

# Remove the global extension functions when the module is removed or re-imported.
$ExecutionContext.SessionState.Module.OnRemove = {
    foreach ($ext in $script:LoadedExtensions) {
        foreach ($funcName in $ext.Functions) {
            Remove-Item "function:global:$funcName" -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function $script:BuiltInFunctions
