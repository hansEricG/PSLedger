<#
.SYNOPSIS
Matches unmatched bank transactions and posts them to the ledger.

.DESCRIPTION
Works through the unmatched transactions imported with
Import-LedgerBankStatement and resolves every transaction it can match with
certainty. Saved customer and supplier payment plans are resumed first, before applying
the following matching rules to transactions without plans:

1. Entry - an existing verification with the same amount on the bank account
   within -DateTolerance days that is not yet linked to another bank
   transaction. The transaction is linked to it and nothing new is posted, so
   payments already booked by hand are never booked twice.
2. CustomerInvoice (incoming payments) - an open customer invoice whose OCR
   reference appears in the payment reference or text, or whose invoice
   number appears there and whose remaining amount equals the payment. The
   payment uses the same recoverable writer as Add-LedgerInvoicePayment.
3. SupplierInvoice (outgoing payments) - an open supplier invoice whose
   payment reference or own invoice number appears in the payment, or whose
   supplier name appears in the counterparty or text and whose remaining
   amount equals the payment. The payment uses the same recoverable writer as
   Add-LedgerSupplierPayment.
4. Rule - the first bank rule (see Add-LedgerBankRule) whose pattern matches
   the counterparty, text or reference. The transaction is posted against the
   rule's account, with VAT split out if the rule has a VAT rate. Rules that
   point at the transaction's own bank account are skipped.

Transfers between own accounts: a verification is linked once per bank
account, so a transfer booked between 1930 and 1940 is linked from both
accounts' statements. When a rule posts a transfer to another imported bank
account (e.g. 1940 or the tax account 1630), the matching transaction on that
account (opposite amount within -DateTolerance days) is linked to the same
verification, so the transfer is never booked twice.

A transaction is only matched to an invoice when exactly one invoice
qualifies. Transactions that cannot be matched remain 'Unmatched' and are
listed with Get-LedgerBankTransaction -Status Unmatched; resolve them with
Set-LedgerBankTransaction. Use -WhatIf to preview the matches without posting.

Customer and supplier payments retain the bank transaction's identity and input hash in
their immutable payment plan. Rerun this command after interruption to finish
both payment and bank link, even when the invoice has already become Paid.
Conflicting inputs or links stop recovery. Resetting a bank link retains its
payment ownership. Rule/manual account postings also retain immutable plans;
retries use the original plan even if a rule changes or is removed. Transfers
without VAT retain a counterpart claim before updating their bank links.
Equally close candidates require manual -VerificationNumber selection; the
selected transaction is still booked once. A counterpart imported later can
join the same posting. Reset never frees either side for another posting.
An unassociated unfinished invoice payment must still be resumed separately.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Account
Optional. Only match transactions for this bank account (e.g. '1930').

.PARAMETER TransactionId
Optional. Only match these transactions.

.PARAMETER DateTolerance
The number of days an existing verification's date may differ from the bank
date to be linked to it. Defaults to 3.

.PARAMETER NoRules
Skip the bank rules and only match against verifications and invoices.

.EXAMPLE
Invoke-LedgerBankMatching -JournalPath .\MinFirma.ledger

Matches and posts all unmatched transactions and returns one object per
matched transaction.

.EXAMPLE
Invoke-LedgerBankMatching -WhatIf
Get-LedgerBankTransaction -Status Unmatched | Format-Table TransactionId, Date, Amount, Counterparty, Text

Previews what would be matched in the current journal, then lists what needs
to be handled by hand.
#>
function Invoke-LedgerBankMatching {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter()]
        [string]$Account,

        [Parameter()]
        [int[]]$TransactionId,

        [Parameter()]
        [ValidateRange(0, 365)]
        [int]$DateTolerance = 3,

        [Parameter()]
        [switch]$NoRules
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
    $journalLock = $null
    try {
        $journalLock = Enter-LedgerJournalLock -JournalPath $JournalPath
        Assert-LedgerJournalSchema -Path $JournalPath -Write
        $statements = @(Get-LedgerBankStatementData -JournalPath $JournalPath)
        $duplicates = @($statements.Transactions | Group-Object TransactionId | Where-Object Count -gt 1)
        if ($duplicates.Count) { throw "Bank transaction identities are duplicated: $($duplicates.Name -join ', '). Matching stopped." }
        $operations = @(Get-LedgerInvoicePaymentOperation -JournalPath $JournalPath)
        $postings = @(Get-LedgerBankPostingOperation -JournalPath $JournalPath)
        $bankOperations = @($operations | Where-Object { $_.PSObject.Properties['BankTransactionId'] })
        if (-not $bankOperations.Count) { Assert-LedgerNoPendingInvoicePayment -JournalPath $JournalPath }
        $linked = Get-LedgerBankLinkedVerifications -Statements $statements
        foreach ($operation in $bankOperations) {
            [void]$linked.Add("$($operation.PaymentAccount)|$($operation.FiscalYear)|$($operation.VerificationNumber)")
        }
        foreach ($posting in $postings) {
            [void]$linked.Add("$($posting.BankAccount)|$($posting.FiscalYear)|$($posting.VerificationNumber)")
            if ($posting.VatRate -eq 0) { [void]$linked.Add("$($posting.Account)|$($posting.FiscalYear)|$($posting.VerificationNumber)") }
        }
        $invoices = @(Get-LedgerInvoice -JournalPath $JournalPath)
        $supplierInvoices = @(Get-LedgerSupplierInvoice -JournalPath $JournalPath)
        $supplierNames = @{}
        foreach ($s in @(Get-LedgerSupplier -JournalPath $JournalPath)) { $supplierNames[$s.SupplierNumber] = $s.Name }
        $rules = if ($NoRules) { @() } else { @(Read-LedgerBankRules -JournalPath $JournalPath) }
        $fiscalYears = @(Get-LedgerFiscalYear -JournalPath $JournalPath)
        $movementCache = @{}

        $work = foreach ($statement in $statements) {
            if ($Account -and $statement.BankAccount -ne $Account) { continue }
            foreach ($t in $statement.Transactions) {
                if ($TransactionId -and $t.TransactionId -notin $TransactionId) { continue }
                [pscustomobject]@{ Statement = $statement; Transaction = $t }
            }
        }
        foreach ($item in @($work | Sort-Object @{ Expression = {
                    if ($_.Transaction.TransactionId -in $bankOperations.BankTransactionId) { 0 }
                    elseif ($_.Transaction.TransactionId -in $postings.TransactionId) { 1 }
                    else { 2 }
                } },
                @{ Expression = { $_.Transaction.TransactionId } })) {
            $fresh = Find-LedgerBankTransaction -JournalPath $JournalPath -TransactionId $item.Transaction.TransactionId
            $statement = $fresh.Statement
            $t = $fresh.Transaction
            $postings = @(Get-LedgerBankPostingOperation -JournalPath $JournalPath)
            $posting = Get-LedgerBankPostingOwner -Operations $postings -TransactionId $t.TransactionId
            if ($posting) {
                Assert-LedgerNoPendingInvoicePayment -JournalPath $JournalPath
                if (Get-LedgerBankInvoicePaymentOperation -Transaction $t -Operations $operations) { throw "Bank transaction $($t.TransactionId) has conflicting payment and posting plans." }
                Assert-LedgerBankPostingSource -Transaction $t -Operation $posting -Counterpart:($posting.TransactionId -ne $t.TransactionId)
                if ($PSCmdlet.ShouldProcess("Bank transaction $($t.TransactionId)", 'Resume saved bank posting')) {
                    (Complete-LedgerBankPosting -JournalPath $JournalPath -Operation $posting).Changed
                    $movementCache.Clear()
                }
                continue
            }
            if ($t.Status -ne 'Unmatched') { continue }
            $operation = Get-LedgerBankInvoicePaymentOperation -Transaction $t -Operations $operations
            $exceptId = if ($operation) { $operation.OperationId } else { [guid]::Empty }
            Assert-LedgerNoPendingInvoicePayment -JournalPath $JournalPath -ExceptPaymentId $exceptId
            $possibleTransfers = @($postings | Where-Object {
                $_.VatRate -eq 0 -and -not $_.Counterpart -and $_.Account -eq $t.BankAccount -and $_.Amount -eq -$t.Amount -and
                    [Math]::Abs(($_.Date - $t.Date).TotalDays) -le $_.DateTolerance
            })
            if (-not $operation -and $possibleTransfers.Count) {
                if ($possibleTransfers.Count -ne 1 -or $possibleTransfers[0].ManualCounterpart) {
                    Write-Warning "Bank transaction $($t.TransactionId) requires manual counterpart selection with -VerificationNumber and -FiscalYear."
                }
                elseif ($PSCmdlet.ShouldProcess("Bank transaction $($t.TransactionId)", 'Complete saved transfer')) {
                    (Complete-LedgerBankPosting -JournalPath $JournalPath -Operation $possibleTransfers[0]).Changed
                    $movementCache.Clear()
                }
                continue
            }

            $year = $fiscalYears | Where-Object { $t.Date -ge $_.StartDate -and $t.Date -le $_.EndDate } | Select-Object -First 1
            if (-not $year) {
                Write-Warning "Bank transaction $($t.TransactionId) ($($t.Date.ToString('yyyy-MM-dd'))): no fiscal year covers the date; skipped."
                continue
            }

            $cacheKey = "$($year.Name)|$($t.BankAccount)"
            if (-not $movementCache.ContainsKey($cacheKey)) {
                $movementCache[$cacheKey] = @(Get-LedgerBankAccountMovements -JournalPath $JournalPath -FiscalYear $year.Name -BankAccount $t.BankAccount)
            }

            $match = $null
            $entry = Find-LedgerBankEntryMatch -Transaction $t -Movements $movementCache[$cacheKey] -Linked $linked -DateTolerance $DateTolerance
            if ($operation) {
                Assert-LedgerBankPaymentLink -Transaction $t -Operation $operation
                $match = @{ Type = "$($operation.InvoiceType)Invoice"; Ref = "$($operation.InvoiceNumber)"; Action = 'Resume saved invoice payment match' }
            }
            elseif ($entry) {
                $match = @{ Type = 'Entry'; Ref = "$($entry.FiscalYear)/$($entry.VerificationNumber)"; Action = "Link to existing verification $($entry.VerificationNumber) in $($entry.FiscalYear)" }
            }
            elseif ($inv = Find-LedgerBankInvoiceMatch -Transaction $t -Invoices $invoices) {
                $match = @{ Type = 'CustomerInvoice'; Ref = [string]$inv.InvoiceNumber; Action = "Register payment of customer invoice $($inv.InvoiceNumber)" }
            }
            elseif ($sup = Find-LedgerBankSupplierInvoiceMatch -Transaction $t -Invoices $supplierInvoices -SupplierNames $supplierNames) {
                $match = @{ Type = 'SupplierInvoice'; Ref = [string]$sup.InvoiceNumber; Action = "Register payment of supplier invoice $($sup.InvoiceNumber)" }
            }
            elseif ($rule = Find-LedgerBankRuleMatch -Transaction $t -Rules @($rules | Where-Object Account -ne $t.BankAccount)) {
                $match = @{ Type = 'Rule'; Ref = $rule.Pattern; Action = "Post against account $($rule.Account) (rule '$($rule.Pattern)')" }
            }

            if (-not $match) {
                Write-Verbose "Bank transaction $($t.TransactionId) ($($t.Date.ToString('yyyy-MM-dd')), $($t.Amount)): no match."
                continue
            }

            $target = "Bank transaction $($t.TransactionId) ($($t.Date.ToString('yyyy-MM-dd')), $($t.Amount))"
            if (-not $PSCmdlet.ShouldProcess($target, $match.Action)) { continue }

            try {
                $result = switch ($match.Type) {
                    'Entry' { [PSCustomObject]@{ FiscalYear = $entry.FiscalYear; VerificationNumber = $entry.VerificationNumber } }
                    'CustomerInvoice' { Invoke-LedgerBankInvoicePayment -JournalPath $JournalPath -Transaction $t -Statement $statement -InvoiceNumber ([int]$match.Ref) }
                    'SupplierInvoice' { Invoke-LedgerBankSupplierPayment -JournalPath $JournalPath -Transaction $t -Statement $statement -InvoiceNumber ([int]$match.Ref) }
                    'Rule' {
                        Invoke-LedgerBankAccountEntry -JournalPath $JournalPath -Transaction $t -Account $rule.Account `
                            -Description $rule.Description -VatRate $rule.VatRate -VatAccount $rule.VatAccount -FiscalYear $year.Name `
                            -MatchType Rule -MatchRef $rule.Pattern -DateTolerance $DateTolerance
                    }
                }
            }
            catch {
                if ($match.Type -in 'CustomerInvoice', 'SupplierInvoice', 'Rule') { throw }
                Write-Warning "Bank transaction $($t.TransactionId): $($_.Exception.Message)"
                continue
            }

            if ($match.Type -eq 'Entry') {
                Set-LedgerBankTransactionState -Statement $statement -Transaction $t -Status Matched `
                    -MatchType $match.Type -MatchRef $match.Ref -FiscalYear $result.FiscalYear -VerificationNumber $result.VerificationNumber
            }
            [void]$linked.Add("$($t.BankAccount)|$($result.FiscalYear)|$($result.VerificationNumber)")

            # A new verification changes the movements on the bank accounts.
            if ($match.Type -ne 'Entry') { $movementCache.Clear() }

            # Keep the invoice lists current so a later payment in the same run
            # sees the reduced remaining amount.
            if ($match.Type -eq 'CustomerInvoice') {
                $invoices = @(Get-LedgerInvoice -JournalPath $JournalPath)
            }
            elseif ($match.Type -eq 'SupplierInvoice') {
                $supplierInvoices = @(Get-LedgerSupplierInvoice -JournalPath $JournalPath)
            }

            if ($match.Type -eq 'Rule') {
                $result.Changed
                if (-not $rule.VatRate) { [void]$linked.Add("$($rule.Account)|$($result.FiscalYear)|$($result.VerificationNumber)") }
            }
            else { ConvertTo-LedgerBankTransactionOutput -Transaction $t }
        }
    }
    finally { Exit-LedgerJournalLock -Lock $journalLock }
}
