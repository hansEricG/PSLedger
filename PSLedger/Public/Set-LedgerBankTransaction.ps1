<#
.SYNOPSIS
Resolves a bank transaction by hand: posts it, links it or ignores it.

.DESCRIPTION
Handles a bank transaction that Invoke-LedgerBankMatching could not match.
Choose one of:

- -Account: post the transaction against a counter account (for example a
  bank fee to 6570 or a tax payment to 1630), optionally with VAT split out
  with -VatRate and -VatAccount.
- -InvoiceNumber: register an incoming payment on a customer invoice.
- -SupplierInvoiceNumber: register an outgoing payment on a supplier invoice.
- -VerificationNumber: link the transaction to a verification already in the
  ledger, without posting anything.
- -Ignore: mark the transaction as handled outside PSLedger (for example a
  transaction dated before the journal's first fiscal year).
- -Reset: return a matched or ignored transaction to 'Unmatched'. Any
  verification it created is left in place; reverse it with
  Add-LedgerReversal if needed.

Only unmatched transactions can be posted, linked or ignored.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER TransactionId
The id of the bank transaction (see Get-LedgerBankTransaction). Accepts
pipeline input by property name.

.PARAMETER Account
Posts the transaction against this counter account.

.PARAMETER Description
The verification description when posting with -Account. Defaults to the
transaction's counterparty, text and reference.

.PARAMETER VatRate
With -Account: the VAT rate included in the amount, e.g. 0.25. The gross
amount is split into a net part on -Account and VAT on -VatAccount.

.PARAMETER VatAccount
With -VatRate: the VAT account, e.g. '2640' (Ingående moms) for purchases.

.PARAMETER InvoiceNumber
Registers the transaction as a payment of this customer invoice.

.PARAMETER SupplierInvoiceNumber
Registers the transaction as a payment of this supplier invoice.

.PARAMETER VerificationNumber
Links the transaction to this existing verification.

.PARAMETER FiscalYear
The fiscal year of -VerificationNumber, or the fiscal year to post into with
-Account. Defaults to the fiscal year containing the transaction date.

.PARAMETER Ignore
Marks the transaction as ignored.

.PARAMETER Reset
Returns the transaction to 'Unmatched'.

.PARAMETER PassThru
If specified, returns the updated transaction. By default the command produces
no output.

.EXAMPLE
Set-LedgerBankTransaction -JournalPath .\MinFirma.ledger -TransactionId 12 -Account 6570

Posts bank transaction 12 (a bank fee) against 6570 (Bankkostnader).

.EXAMPLE
Set-LedgerBankTransaction -TransactionId 15 -Account 5410 -VatRate 0.25 -VatAccount 2640 -Description 'Kontorsmaterial Clas Ohlson'

Posts a card purchase of office supplies with 25 % input VAT split out.

.EXAMPLE
Set-LedgerBankTransaction -TransactionId 18 -InvoiceNumber 7

Registers a customer payment that arrived without OCR reference against
invoice 7.
#>
function Set-LedgerBankTransaction {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Ignore', Justification = 'Selects a parameter set')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Reset', Justification = 'Selects a parameter set')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Account')]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [int]$TransactionId,

        [Parameter(Mandatory, ParameterSetName = 'Account')]
        [string]$Account,

        [Parameter(ParameterSetName = 'Account')]
        [string]$Description,

        [Parameter(ParameterSetName = 'Account')]
        [decimal]$VatRate = 0,

        [Parameter(ParameterSetName = 'Account')]
        [string]$VatAccount,

        [Parameter(Mandatory, ParameterSetName = 'Invoice')]
        [int]$InvoiceNumber,

        [Parameter(Mandatory, ParameterSetName = 'SupplierInvoice')]
        [int]$SupplierInvoiceNumber,

        [Parameter(Mandatory, ParameterSetName = 'Verification')]
        [int]$VerificationNumber,

        [Parameter(ParameterSetName = 'Account')]
        [Parameter(ParameterSetName = 'Verification')]
        [string]$FiscalYear,

        [Parameter(Mandatory, ParameterSetName = 'Ignore')]
        [switch]$Ignore,

        [Parameter(Mandatory, ParameterSetName = 'Reset')]
        [switch]$Reset,

        [Parameter()]
        [switch]$PassThru
    )
    begin {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
    }
    process {
        $found = Find-LedgerBankTransaction -JournalPath $JournalPath -TransactionId $TransactionId
        $statement = $found.Statement
        $t = $found.Transaction
        $target = "Bank transaction $TransactionId ($($t.Date.ToString('yyyy-MM-dd')), $($t.Amount))"

        if ($PSCmdlet.ParameterSetName -eq 'Reset') {
            if ($t.Status -eq 'Unmatched') { return }
            if (-not $PSCmdlet.ShouldProcess($target, 'Reset to Unmatched')) { return }
            Set-LedgerBankTransactionState -Statement $statement -Transaction $t -Status Unmatched
            if ($PassThru) { ConvertTo-LedgerBankTransactionOutput -Transaction $t }
            return
        }

        if ($t.Status -ne 'Unmatched') {
            throw "Bank transaction $TransactionId is already $($t.Status.ToLowerInvariant()). Use -Reset first to change it."
        }

        switch ($PSCmdlet.ParameterSetName) {
            'Ignore' {
                if (-not $PSCmdlet.ShouldProcess($target, 'Ignore')) { return }
                Set-LedgerBankTransactionState -Statement $statement -Transaction $t -Status Ignored -MatchType 'Ignored'
            }
            'Verification' {
                if (-not $FiscalYear) {
                    $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $t.Date
                    if (-not $FiscalYear) {
                        throw "No fiscal year covers the transaction date $($t.Date.ToString('yyyy-MM-dd')). Specify -FiscalYear."
                    }
                }
                $movement = Get-LedgerBankAccountMovements -JournalPath $JournalPath -FiscalYear $FiscalYear -BankAccount $t.BankAccount |
                    Where-Object VerificationNumber -eq $VerificationNumber
                if (-not $movement) {
                    throw "Verification $VerificationNumber in $FiscalYear does not exist or has no row on account $($t.BankAccount)."
                }
                if ($movement.Amount -ne $t.Amount) {
                    Write-Warning "Verification $VerificationNumber has $($movement.Amount) on account $($t.BankAccount), but the bank transaction is $($t.Amount)."
                }
                $linked = Get-LedgerBankLinkedVerifications -Statements @(Get-LedgerBankStatementData -JournalPath $JournalPath)
                if ($linked.Contains("$($t.BankAccount)|$FiscalYear|$VerificationNumber")) {
                    Write-Warning "Verification $VerificationNumber in $FiscalYear is already linked to another bank transaction."
                }
                if (-not $PSCmdlet.ShouldProcess($target, "Link to verification $VerificationNumber in $FiscalYear")) { return }
                Set-LedgerBankTransactionState -Statement $statement -Transaction $t -Status Matched -MatchType 'Entry' `
                    -MatchRef "$FiscalYear/$VerificationNumber" -FiscalYear $FiscalYear -VerificationNumber $VerificationNumber
            }
            'Invoice' {
                if (-not $PSCmdlet.ShouldProcess($target, "Register payment of customer invoice $InvoiceNumber")) { return }
                $result = Invoke-LedgerBankInvoicePayment -JournalPath $JournalPath -Transaction $t -InvoiceNumber $InvoiceNumber
                Set-LedgerBankTransactionState -Statement $statement -Transaction $t -Status Matched -MatchType 'CustomerInvoice' `
                    -MatchRef ([string]$InvoiceNumber) -FiscalYear $result.FiscalYear -VerificationNumber $result.VerificationNumber
            }
            'SupplierInvoice' {
                if (-not $PSCmdlet.ShouldProcess($target, "Register payment of supplier invoice $SupplierInvoiceNumber")) { return }
                $result = Invoke-LedgerBankSupplierPayment -JournalPath $JournalPath -Transaction $t -InvoiceNumber $SupplierInvoiceNumber
                Set-LedgerBankTransactionState -Statement $statement -Transaction $t -Status Matched -MatchType 'SupplierInvoice' `
                    -MatchRef ([string]$SupplierInvoiceNumber) -FiscalYear $result.FiscalYear -VerificationNumber $result.VerificationNumber
            }
            'Account' {
                if (-not $PSCmdlet.ShouldProcess($target, "Post against account $Account")) { return }
                $entryParams = @{
                    JournalPath = $JournalPath
                    Transaction = $t
                    Account     = $Account
                    Description = $Description
                    VatRate     = $VatRate
                    VatAccount  = $VatAccount
                    FiscalYear  = $FiscalYear
                }
                $result = Invoke-LedgerBankAccountEntry @entryParams
                Set-LedgerBankTransactionState -Statement $statement -Transaction $t -Status Matched -MatchType 'Manual' `
                    -MatchRef $Account -FiscalYear $result.FiscalYear -VerificationNumber $result.VerificationNumber
            }
        }

        if ($PassThru) { ConvertTo-LedgerBankTransactionOutput -Transaction $t }
    }
}
