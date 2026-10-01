# Matching and posting helpers shared by Invoke-LedgerBankMatching and
# Set-LedgerBankTransaction. A bank transaction is resolved by one of:
#
#   Entry            - linked to an existing verification with the same amount
#                      on the bank account (nothing new is posted)
#   CustomerInvoice  - posted as a payment of a customer invoice
#   SupplierInvoice  - posted as a payment of a supplier invoice
#   Rule             - posted against the account of a matching bank rule
#   Manual           - posted against an account given by the user

function Get-LedgerBankDigitTokens {
    <#
    .SYNOPSIS
    Returns the digit sequences in a transaction's reference and text, used to
    find OCR references and invoice numbers.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Transaction
    )
    $tokens = [System.Collections.Generic.List[string]]::new()
    $refDigits = ([string]$Transaction.Reference) -replace '[\s-]', ''
    if ($refDigits -match '^\d+$') { $tokens.Add($refDigits) }
    foreach ($value in @($Transaction.Reference, $Transaction.Text)) {
        if (-not $value) { continue }
        foreach ($m in [regex]::Matches($value, '\d+')) { $tokens.Add($m.Value) }
    }
    return , @($tokens | Select-Object -Unique)
}

function Get-LedgerBankLinkedVerifications {
    <#
    .SYNOPSIS
    Returns a set of 'BankAccount|FiscalYear|VerificationNumber' keys already
    linked to a bank transaction. The key includes the bank account because a
    transfer between two own bank accounts is one verification that is linked
    once from each account's statement.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Statements
    )
    $set = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($s in $Statements) {
        foreach ($t in $s.Transactions) {
            if ($t.Status -eq 'Matched' -and $null -ne $t.VerificationNumber) {
                [void]$set.Add("$($t.BankAccount)|$($t.FiscalYear)|$($t.VerificationNumber)")
            }
        }
    }
    return , $set
}

function Get-LedgerBankAccountMovements {
    <#
    .SYNOPSIS
    Returns one object per verification in a fiscal year that touches the bank
    account, with the net amount on that account.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$BankAccount
    )
    foreach ($e in @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Account $BankAccount)) {
        $amount = [decimal]0
        foreach ($r in $e.Rows) { if ($r.Account -eq $BankAccount) { $amount += $r.Amount } }
        [PSCustomObject]@{
            FiscalYear         = $FiscalYear
            VerificationNumber = $e.VerificationNumber
            Date               = [datetime]::ParseExact($e.Date.Trim(), 'yyyy-MM-dd', $null)
            Description        = $e.Description
            Amount             = $amount
        }
    }
}

function Find-LedgerBankEntryMatch {
    <#
    .SYNOPSIS
    Finds an unlinked verification with the transaction's amount on the bank
    account within the date tolerance, preferring the closest date.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Transaction,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Movements,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Linked,

        [int]$DateTolerance = 3
    )
    $Movements |
        Where-Object {
            $_.Amount -eq $Transaction.Amount -and
            [Math]::Abs(($_.Date - $Transaction.Date).TotalDays) -le $DateTolerance -and
            -not $Linked.Contains("$($Transaction.BankAccount)|$($_.FiscalYear)|$($_.VerificationNumber)")
        } |
        Sort-Object @{ Expression = { [Math]::Abs(($_.Date - $Transaction.Date).TotalDays) } }, VerificationNumber |
        Select-Object -First 1
}

function Find-LedgerBankInvoiceMatch {
    <#
    .SYNOPSIS
    Finds the open customer invoice an incoming payment belongs to.

    .DESCRIPTION
    Matches on the invoice's OCR reference appearing in the payment reference or
    text, provided the amount does not exceed the remaining amount. Falls back
    to an invoice whose number appears in the reference or text and whose
    remaining amount equals the payment exactly. Returns nothing unless exactly
    one invoice qualifies.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Transaction,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Invoices
    )
    if ($Transaction.Amount -le 0 -or -not $Invoices) { return }
    $tokens = Get-LedgerBankDigitTokens -Transaction $Transaction
    if (-not $tokens) { return }

    $open = @($Invoices | Where-Object { $_.Status -in 'Booked', 'Partial' -and $_.RemainingAmount -gt 0 })
    $byOcr = @($open | Where-Object { $_.OcrReference -in $tokens -and $Transaction.Amount -le $_.RemainingAmount })
    if ($byOcr.Count -eq 1) { return $byOcr[0] }
    if ($byOcr.Count -gt 1) { return }

    $byNumber = @($open | Where-Object { [string]$_.InvoiceNumber -in $tokens -and $_.RemainingAmount -eq $Transaction.Amount })
    if ($byNumber.Count -eq 1) { return $byNumber[0] }
}

function Find-LedgerBankSupplierInvoiceMatch {
    <#
    .SYNOPSIS
    Finds the open supplier invoice an outgoing payment belongs to.

    .DESCRIPTION
    Matches on the invoice's payment reference (OCR) or the supplier's own
    invoice number appearing in the payment, provided the amount does not exceed
    the remaining amount. Falls back to an invoice whose supplier name appears in
    the counterparty or text and whose remaining amount equals the payment
    exactly. Returns nothing unless exactly one invoice qualifies.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Transaction,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Invoices,

        [Parameter()]
        [hashtable]$SupplierNames = @{}
    )
    if ($Transaction.Amount -ge 0 -or -not $Invoices) { return }
    $paid = -$Transaction.Amount
    $tokens = Get-LedgerBankDigitTokens -Transaction $Transaction
    $haystack = "$($Transaction.Reference) $($Transaction.Text) $($Transaction.Counterparty)"

    $open = @($Invoices | Where-Object { $_.Status -in 'Booked', 'Partial' -and $_.RemainingAmount -gt 0 })
    $byRef = @($open | Where-Object {
        $inv = $_
        $refDigits = ([string]$inv.Reference) -replace '[\s-]', ''
        $paid -le $inv.RemainingAmount -and (
            ($refDigits -and $refDigits -in $tokens) -or
            ($inv.SupplierReference -and $inv.SupplierReference.Length -ge 3 -and
                $haystack.IndexOf($inv.SupplierReference, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
        )
    })
    if ($byRef.Count -eq 1) { return $byRef[0] }
    if ($byRef.Count -gt 1) { return }

    $byName = @($open | Where-Object {
        $name = $SupplierNames[$_.SupplierNumber]
        $_.RemainingAmount -eq $paid -and $name -and
            $haystack.IndexOf($name, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($byName.Count -eq 1) { return $byName[0] }
}

function Find-LedgerBankRuleMatch {
    <#
    .SYNOPSIS
    Returns the first bank rule (in priority order) whose pattern matches.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Transaction,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )
    foreach ($rule in $Rules) {
        if (Test-LedgerBankPatternMatch -Pattern $rule.Pattern -Transaction $Transaction) {
            return $rule
        }
    }
}

function Get-LedgerBankTransactionDescription {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Transaction
    )
    $parts = @($Transaction.Counterparty, $Transaction.Text, $Transaction.Reference) | Where-Object { $_ } | Select-Object -Unique
    if ($parts) { return ($parts -join ' ') }
    return "Banktransaktion $($Transaction.TransactionId)"
}

function Invoke-LedgerBankInvoicePayment {
    <#
    .SYNOPSIS
    Registers a bank transaction as a customer invoice payment and returns the
    created verification's fiscal year and number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [psobject]$Transaction,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber
    )
    if ($Transaction.Amount -le 0) {
        throw "Bank transaction $($Transaction.TransactionId) is an outgoing payment and cannot pay a customer invoice."
    }
    $inv = Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber `
        -Date $Transaction.Date -Amount $Transaction.Amount -Account $Transaction.BankAccount `
        -PassThru -WhatIf:$false -Confirm:$false
    $payment = @($inv.Payments)[-1]
    [PSCustomObject]@{ FiscalYear = $payment.FiscalYear; VerificationNumber = $payment.VerificationNumber }
}

function Invoke-LedgerBankSupplierPayment {
    <#
    .SYNOPSIS
    Registers a bank transaction as a supplier invoice payment and returns the
    created verification's fiscal year and number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [psobject]$Transaction,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber
    )
    if ($Transaction.Amount -ge 0) {
        throw "Bank transaction $($Transaction.TransactionId) is an incoming payment and cannot pay a supplier invoice."
    }
    $inv = Add-LedgerSupplierPayment -JournalPath $JournalPath -InvoiceNumber $InvoiceNumber `
        -Date $Transaction.Date -Amount (-$Transaction.Amount) -Account $Transaction.BankAccount `
        -PassThru -WhatIf:$false -Confirm:$false
    $payment = @($inv.Payments)[-1]
    [PSCustomObject]@{ FiscalYear = $payment.FiscalYear; VerificationNumber = $payment.VerificationNumber }
}

function Invoke-LedgerBankAccountEntry {
    <#
    .SYNOPSIS
    Posts a bank transaction against a counter account (optionally with VAT) and
    returns the created verification's fiscal year and number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [psobject]$Transaction,

        [Parameter(Mandatory)]
        [string]$Account,

        [string]$Description,

        [decimal]$VatRate = 0,

        [string]$VatAccount,

        [string]$FiscalYear
    )
    if (-not $FiscalYear) {
        $FiscalYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $Transaction.Date
        if (-not $FiscalYear) {
            throw "No fiscal year covers the transaction date $($Transaction.Date.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
        }
    }
    if (-not $Description) {
        $Description = Get-LedgerBankTransactionDescription -Transaction $Transaction
    }
    $rows = Get-LedgerBankEntryRows -BankAccount $Transaction.BankAccount -Amount $Transaction.Amount `
        -Account $Account -VatRate $VatRate -VatAccount $VatAccount
    $ver = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date $Transaction.Date `
        -Description $Description -Rows $rows -PassThru -WhatIf:$false -Confirm:$false
    [PSCustomObject]@{ FiscalYear = $ver.FiscalYear; VerificationNumber = $ver.VerificationNumber }
}
