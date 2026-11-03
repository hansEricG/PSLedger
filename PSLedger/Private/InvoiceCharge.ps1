# Helper for booking a late charge (reminder fee, late-payment compensation or
# late-payment interest) onto a posted customer invoice. A charge debits the
# invoice's receivable account and credits an income account, and is appended to
# the invoice's 'Charges:' section so it increases the invoice total (and thus the
# open receivable) while staying reconciled against the general ledger.
#
# Each charge is a recoverable operation: an immutable plan in
# invoices/charges/<ChargeId>.txt reserves the verification number before the
# verification is written, and repeating the call with the same ChargeId
# completes an interrupted charge without booking it twice.

function Add-LedgerInvoiceChargeInternal {
    <#
    .SYNOPSIS
    Books a late charge on a posted, unpaid invoice and records it on the invoice.

    .DESCRIPTION
    Debits the invoice's receivable account and credits the supplied income
    account with the charge amount (no VAT), then appends the charge to the
    invoice's Charges section. With -Reminder, the reminder count and date are
    updated in the same invoice write. Returns $true when the charge is recorded
    and $false when it was skipped by -WhatIf or -Confirm.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$InvoiceNumber,

        [Parameter(Mandatory)]
        [ValidateSet('Fee', 'Interest')]
        [string]$Type,

        [Parameter()]
        [decimal]$Amount,

        [Parameter()]
        [decimal]$AnnualRate,

        [Parameter()]
        [string]$Account,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [string]$FiscalYear,

        [Parameter()]
        [ValidateScript({ if ($_ -eq [guid]::Empty) { throw 'ChargeId must not be an empty GUID.' }; $true })]
        [guid]$ChargeId,

        [Parameter()]
        [switch]$Reminder
    )

    $journalLock = $null
    try {
        $journalLock = Enter-LedgerJournalLock -JournalPath $JournalPath
        Assert-LedgerJournalSchema -Path $JournalPath -Write
        $invoiceDir = Get-LedgerInvoiceDirectory -JournalPath $JournalPath
        $filePath = Join-Path $invoiceDir (Get-LedgerInvoiceFileName -InvoiceNumber $InvoiceNumber)
        if (-not (Test-Path $filePath)) {
            throw "Invoice $InvoiceNumber does not exist."
        }

        $invoice = Read-LedgerInvoiceFile -Path $filePath
        if ($invoice.InvoiceNumber -ne $InvoiceNumber) {
            throw "Invoice $InvoiceNumber has an inconsistent identity."
        }
        $id = if ($PSBoundParameters.ContainsKey('ChargeId')) { $ChargeId } else { [guid]::NewGuid() }
        $operationPath = Join-Path $JournalPath 'invoices' 'charges' "$id.txt"
        $operation = if (Test-Path -LiteralPath $operationPath) { Read-LedgerInvoiceChargeOperation -Path $operationPath } else { $null }
        $chargeAmount = $Amount
        $chargeDate = $Date.Date
        $chargeAccount = if ($Account) { $Account } elseif ($Type -eq 'Interest') { '8310' } else { '3590' }
        $chargeYear = $FiscalYear
        if ($operation) {
            if ($operation.InvoiceNumber -ne $InvoiceNumber -or $operation.ChargeType -ne $Type -or
                [bool]$operation.ReminderCount -ne [bool]$Reminder -or
                ($PSBoundParameters.ContainsKey('Amount') -and $Amount -ne $operation.ChargeAmount) -or
                ($PSBoundParameters.ContainsKey('Date') -and $Date.Date -ne $operation.ChargeDate) -or
                ($Account -and $Account -ne $operation.ChargeAccount) -or
                ($FiscalYear -and $FiscalYear -ne $operation.FiscalYear)) {
                throw "ChargeId $id has a saved plan with different charge inputs. Use its original inputs to retry."
            }
            $chargeAmount = $operation.ChargeAmount
            $chargeDate = $operation.ChargeDate
            $chargeAccount = $operation.ChargeAccount
            $chargeYear = $operation.FiscalYear
            if (Get-LedgerRecordedInvoiceCharge -Invoice $invoice -Operation $operation) {
                $verificationPath = Join-Path $JournalPath $chargeYear ('ver{0:D4}.txt' -f $operation.VerificationNumber)
                Assert-LedgerInvoicePostingVerification -Path $verificationPath -Operation $operation
                Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $chargeYear
                return (-not $WhatIfPreference)
            }
            if ((Get-LedgerContentHash -Path $filePath) -ne $operation.InvoiceHash) {
                throw "Invoice $InvoiceNumber has changed since charge $id was planned. Recovery stopped."
            }
        }
        Assert-LedgerNoPendingInvoicePayment -JournalPath $JournalPath -Invoice $invoice -ExceptChargeId $id

        if ($invoice.Status -eq 'Draft') {
            throw "Invoice $InvoiceNumber has not been posted. Post it first with Invoke-LedgerInvoicePosting."
        }
        if ($invoice.Status -notin @('Booked', 'Partial')) {
            throw "Invoice $InvoiceNumber is not an open receivable (status '$($invoice.Status)'). Charges can only be booked on posted, unpaid invoices."
        }

        if (-not $operation -and -not $PSBoundParameters.ContainsKey('Amount')) {
            if ($Type -ne 'Interest' -or -not $PSBoundParameters.ContainsKey('AnnualRate')) {
                throw "Specify either -AnnualRate (to calculate interest) or -Amount (to book an explicit amount)."
            }
            $daysOverdue = [int]($chargeDate - [datetime]$invoice.DueDate).TotalDays
            if ($daysOverdue -le 0) {
                throw "Invoice $InvoiceNumber is not overdue on $($chargeDate.ToString('yyyy-MM-dd')) (due $($invoice.DueDate.ToString('yyyy-MM-dd'))). No interest to charge."
            }
            $chargeAmount = [Math]::Round([decimal]$invoice.RemainingAmount * $AnnualRate * $daysOverdue / 365, 2)
            if ($chargeAmount -le 0) {
                throw "The calculated interest for invoice $InvoiceNumber is zero. Nothing to book."
            }
        }
        if ($chargeAmount -le 0) {
            throw "Charge amount must be greater than zero."
        }
        if ([Math]::Round($chargeAmount, 2) -ne $chargeAmount) {
            throw "Charge amount $chargeAmount has more than two decimals."
        }
        if ($chargeAccount -notmatch '^\d+$') {
            throw "Invalid charge account '$chargeAccount'."
        }
        $chargeAmount = [decimal]::Parse($chargeAmount.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture),
            [Globalization.CultureInfo]::InvariantCulture)

        if (-not $chargeYear) {
            $chargeYear = Find-FiscalYearForDate -JournalPath $JournalPath -Date $chargeDate
            if (-not $chargeYear) {
                throw "No fiscal year covers the charge date $($chargeDate.ToString('yyyy-MM-dd')). Create one with New-LedgerFiscalYear or specify -FiscalYear."
            }
        }

        $label = if ($Type -eq 'Interest') { 'Dröjsmålsränta' } else { 'Påminnelseavgift' }
        $entryParameters = @{
            JournalPath = $JournalPath; FiscalYear = $chargeYear; Date = $chargeDate
            Description = "$label kundfaktura $InvoiceNumber"; OperationId = $id
            Rows = @(
                @{ Account = $invoice.ReceivableAccount; Amount = $chargeAmount }
                @{ Account = $chargeAccount; Amount = -$chargeAmount }
            )
        }
        $existingVerification = $false
        if ($operation) {
            $verificationPath = Join-Path $JournalPath $chargeYear ('ver{0:D4}.txt' -f $operation.VerificationNumber)
            $existingVerification = Test-Path -LiteralPath $verificationPath
            if ($existingVerification) { Assert-LedgerInvoicePostingVerification -Path $verificationPath -Operation $operation }
        }
        $unsealedNumber = if ($existingVerification) { $operation.VerificationNumber } else { 0 }
        Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $chargeYear -UnsealedVerification $unsealedNumber
        if (-not $existingVerification) {
            $lines = @(Get-LedgerVerificationLines @entryParameters)
            $hash = Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
            if ($operation -and $hash -ne $operation.VerificationHash) {
                throw "Charge $id no longer produces its saved verification plan. Recovery stopped."
            }
            if (-not $operation) {
                $operation = [pscustomobject]@{
                    OperationId = $id; InvoiceNumber = $InvoiceNumber; FiscalYear = $chargeYear
                    VerificationNumber = Get-LedgerNextVerificationNumber -JournalPath $JournalPath -FiscalYear $chargeYear
                    InvoiceHash = Get-LedgerContentHash -Path $filePath; VerificationHash = $hash
                    ChargeType = $Type; ChargeDate = $chargeDate; ChargeAmount = $chargeAmount; ChargeAccount = $chargeAccount
                    ReminderCount = if ($Reminder) { [int]$invoice.ReminderCount + 1 } else { 0 }
                }
            }
        }

        $action = if ($Reminder) { "Record payment reminder and book fee of $chargeAmount" }
        elseif ($Type -eq 'Interest') { "Book interest of $chargeAmount" }
        else { "Book fee of $chargeAmount" }
        if (-not $PSCmdlet.ShouldProcess("Invoice $InvoiceNumber", "$action (ChargeId $id)")) {
            return $false
        }

        if (-not (Test-Path -LiteralPath $operationPath)) {
            Save-LedgerInvoiceChargeOperation -Path $operationPath -Operation $operation
        }
        try {
            if (-not $existingVerification) {
                Write-LedgerVerification @entryParameters -ReservedNumber $operation.VerificationNumber -Confirm:$false
            }
            Complete-LedgerInvoicePostingVerification -JournalPath $JournalPath -Operation $operation
            if ((Get-LedgerContentHash -Path $filePath) -ne $operation.InvoiceHash) {
                throw "Invoice $InvoiceNumber changed during the charge. Its saved verification was not removed."
            }

            $invoice.Charges += [PSCustomObject]@{
                Date               = $chargeDate
                Type               = $Type
                Amount             = $chargeAmount
                Account            = $chargeAccount
                VerificationNumber = $operation.VerificationNumber
                FiscalYear         = $chargeYear
            }
            if ($operation.ReminderCount) {
                $invoice.ReminderCount = $operation.ReminderCount
                $invoice.LastReminderDate = $chargeDate
            }
            Save-LedgerInvoiceFile -Invoice $invoice
        }
        catch {
            throw [InvalidOperationException]::new(
                "Could not confirm completion of charge $id for invoice $InvoiceNumber. Keep '$operationPath' and retry $(Get-LedgerInvoiceChargeCommand -Operation $operation -JournalPath $JournalPath). $($_.Exception.Message)",
                $_.Exception)
        }
        $true
    }
    finally { Exit-LedgerJournalLock -Lock $journalLock }
}
