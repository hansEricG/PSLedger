<#
.SYNOPSIS
Matches unmatched bank transactions and posts them to the ledger.

.DESCRIPTION
Works through the unmatched transactions imported with
Import-LedgerBankStatement and resolves every transaction it can match with
certainty. For each transaction the following are tried in order:

1. Entry - an existing verification with the same amount on the bank account
   within -DateTolerance days that is not yet linked to another bank
   transaction. The transaction is linked to it and nothing new is posted, so
   payments already booked by hand are never booked twice.
2. CustomerInvoice (incoming payments) - an open customer invoice whose OCR
   reference appears in the payment reference or text, or whose invoice
   number appears there and whose remaining amount equals the payment. The
   payment is registered with Add-LedgerInvoicePayment.
3. SupplierInvoice (outgoing payments) - an open supplier invoice whose
   payment reference or own invoice number appears in the payment, or whose
   supplier name appears in the counterparty or text and whose remaining
   amount equals the payment. The payment is registered with
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

    $statements = @(Get-LedgerBankStatementData -JournalPath $JournalPath)
    $linked = Get-LedgerBankLinkedVerifications -Statements $statements
    $invoices = @(Get-LedgerInvoice -JournalPath $JournalPath)
    $supplierInvoices = @(Get-LedgerSupplierInvoice -JournalPath $JournalPath)
    $supplierNames = @{}
    foreach ($s in @(Get-LedgerSupplier -JournalPath $JournalPath)) { $supplierNames[$s.SupplierNumber] = $s.Name }
    $rules = if ($NoRules) { @() } else { @(Read-LedgerBankRules -JournalPath $JournalPath) }
    $fiscalYears = @(Get-LedgerFiscalYear -JournalPath $JournalPath)
    $movementCache = @{}

    foreach ($statement in $statements) {
        if ($Account -and $statement.BankAccount -ne $Account) { continue }
        foreach ($t in @($statement.Transactions)) {
            if ($t.Status -ne 'Unmatched') { continue }
            if ($TransactionId -and $t.TransactionId -notin $TransactionId) { continue }

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
            if ($entry) {
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
                    'CustomerInvoice' { Invoke-LedgerBankInvoicePayment -JournalPath $JournalPath -Transaction $t -InvoiceNumber $inv.InvoiceNumber }
                    'SupplierInvoice' { Invoke-LedgerBankSupplierPayment -JournalPath $JournalPath -Transaction $t -InvoiceNumber $sup.InvoiceNumber }
                    'Rule' {
                        Invoke-LedgerBankAccountEntry -JournalPath $JournalPath -Transaction $t -Account $rule.Account `
                            -Description $rule.Description -VatRate $rule.VatRate -VatAccount $rule.VatAccount -FiscalYear $year.Name
                    }
                }
            }
            catch {
                Write-Warning "Bank transaction $($t.TransactionId): $($_.Exception.Message)"
                continue
            }

            Set-LedgerBankTransactionState -Statement $statement -Transaction $t -Status Matched `
                -MatchType $match.Type -MatchRef $match.Ref -FiscalYear $result.FiscalYear -VerificationNumber $result.VerificationNumber
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

            ConvertTo-LedgerBankTransactionOutput -Transaction $t

            # A transfer to another own bank account (or the tax account) shows up
            # on that account's statement too; link it to the same verification
            # instead of posting the transfer twice.
            if ($match.Type -eq 'Rule' -and -not $rule.VatRate) {
                $counterpart = $null
                $counterStatement = $null
                foreach ($s in $statements) {
                    if ($s.BankAccount -ne $rule.Account) { continue }
                    foreach ($c in @($s.Transactions)) {
                        if ($c.Status -ne 'Unmatched' -or $c.Amount -ne -$t.Amount) { continue }
                        $days = [Math]::Abs(($c.Date - $t.Date).TotalDays)
                        if ($days -gt $DateTolerance) { continue }
                        if (-not $counterpart -or $days -lt [Math]::Abs(($counterpart.Date - $t.Date).TotalDays)) {
                            $counterpart = $c; $counterStatement = $s
                        }
                    }
                }
                if ($counterpart) {
                    Set-LedgerBankTransactionState -Statement $counterStatement -Transaction $counterpart -Status Matched `
                        -MatchType 'Entry' -MatchRef "$($result.FiscalYear)/$($result.VerificationNumber)" `
                        -FiscalYear $result.FiscalYear -VerificationNumber $result.VerificationNumber
                    [void]$linked.Add("$($counterpart.BankAccount)|$($result.FiscalYear)|$($result.VerificationNumber)")
                    ConvertTo-LedgerBankTransactionOutput -Transaction $counterpart
                }
            }
        }
    }
}
