function Read-LedgerBankPostingFields {
    [CmdletBinding()]
    param ([string]$Path)

    $fields = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop) {
        if ($line.StartsWith(';') -or -not $line) { continue }
        if ($line -notmatch '^([A-Za-z]+):\t(.*)$' -or $fields.ContainsKey($Matches[1])) {
            throw "Invalid bank posting record '$Path': malformed or duplicate field."
        }
        $fields[$Matches[1]] = $Matches[2]
    }
    $fields
}

function Save-LedgerBankPostingFields {
    [CmdletBinding()]
    param ([string]$Path, [System.Collections.IDictionary]$Fields)

    $null = New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force -ErrorAction Stop
    $lines = @('; PSLedger bank posting')
    foreach ($key in $Fields.Keys) { $lines += "${key}:`t$($Fields[$key])" }
    Set-LedgerFileContent -Path $Path -Value $lines -NoClobber
}

function Get-LedgerBankPostingOperation {
    [CmdletBinding()]
    param ([string]$JournalPath)

    $directory = Join-Path $JournalPath 'bank' 'posting'
    if (-not (Test-Path -LiteralPath $directory)) { return }
    $owners = [Collections.Generic.HashSet[int]]::new()
    $identities = [Collections.Generic.HashSet[guid]]::new()
    $reservations = [Collections.Generic.HashSet[string]]::new()
    foreach ($sidecar in Get-ChildItem -LiteralPath $directory -File -ErrorAction Stop | Where-Object Name -Match '^(counterpart|ambiguous)(\d+)\.txt$') {
        $null = $sidecar.Name -match '^(counterpart|ambiguous)(\d+)\.txt$'
        if (-not (Test-Path -LiteralPath (Join-Path $directory "txn$($Matches[2]).txt"))) {
            throw "Bank posting record '$($sidecar.FullName)' has no corresponding plan."
        }
    }
    foreach ($file in Get-ChildItem -LiteralPath $directory -Filter 'txn*.txt' -File -ErrorAction Stop) {
        $f = Read-LedgerBankPostingFields -Path $file.FullName
        foreach ($key in 'FormatVersion', 'OperationId', 'TransactionId', 'StatementNumber', 'BankHash', 'BankAccount',
            'Date', 'Amount', 'Account', 'VatRate', 'VatAccount', 'Description', 'MatchType', 'MatchRef',
            'FiscalYear', 'VerificationNumber', 'VerificationHash', 'DateTolerance') {
            if (-not $f.ContainsKey($key)) { throw "Invalid bank posting record '$($file.FullName)': missing $key." }
        }
        $id = [guid]::Empty
        $date = [datetime]::MinValue
        if ($f.FormatVersion -ne '1' -or
            -not [guid]::TryParseExact($f.OperationId, 'D', [ref]$id) -or $id -eq [guid]::Empty -or
            $f.TransactionId -notmatch '^[1-9]\d*$' -or $f.StatementNumber -notmatch '^[1-9]\d*$' -or
            $f.VerificationNumber -notmatch '^[1-9]\d*$' -or
            $f.BankAccount -notmatch '^\d+$' -or $f.Account -notmatch '^\d+$' -or
            $f.Amount -notmatch '^-?\d+(\.\d{1,2})?$' -or $f.VatRate -notmatch '^\d+(\.\d+)?$' -or
            $f.DateTolerance -notmatch '^\d+$' -or [int]$f.DateTolerance -gt 365 -or
            $f.MatchType -notin 'Manual', 'Rule' -or
            ($f.MatchType -eq 'Manual' -and $f.MatchRef -ne $f.Account) -or [string]::IsNullOrWhiteSpace($f.MatchRef) -or
            $f.BankHash -cnotmatch '^[0-9a-f]{64}$' -or $f.VerificationHash -cnotmatch '^[0-9a-f]{64}$' -or
            -not [datetime]::TryParseExact($f.Date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None, [ref]$date)) {
            throw "Invalid bank posting record '$($file.FullName)': invalid identity, inputs or hash."
        }
        $null = Assert-LedgerSafeLeafName -Name $f.FiscalYear -Kind 'fiscal year'
        if ($file.Name -ne "txn$($f.TransactionId).txt" -or -not $owners.Add([int]$f.TransactionId) -or
            -not $identities.Add($id) -or -not $reservations.Add("$($f.FiscalYear)|$($f.VerificationNumber)")) {
            throw "Bank posting identity or reservation is duplicated or does not match '$($file.Name)'."
        }
        $operation = [pscustomobject]@{
            Path = $file.FullName; OperationId = $id; TransactionId = [int]$f.TransactionId
            StatementNumber = [int]$f.StatementNumber; BankHash = $f.BankHash; BankAccount = $f.BankAccount
            Date = $date; Amount = [decimal]::Parse($f.Amount, [Globalization.CultureInfo]::InvariantCulture)
            Account = $f.Account; VatRate = [decimal]::Parse($f.VatRate, [Globalization.CultureInfo]::InvariantCulture)
            VatAccount = $f.VatAccount; Description = $f.Description; MatchType = $f.MatchType; MatchRef = $f.MatchRef
            FiscalYear = $f.FiscalYear; VerificationNumber = [int]$f.VerificationNumber; VerificationHash = $f.VerificationHash
            DateTolerance = [int]$f.DateTolerance; Counterpart = $null
            ManualCounterpart = Test-Path -LiteralPath (Join-Path $directory "ambiguous$($f.TransactionId).txt")
        }
        if ($operation.ManualCounterpart) {
            $marker = Read-LedgerBankPostingFields -Path (Join-Path $directory "ambiguous$($f.TransactionId).txt")
            if ($marker.OperationId -ne "$id") { throw "Invalid bank posting ambiguity record for transaction $($f.TransactionId)." }
        }
        $claimPath = Join-Path $directory "counterpart$($f.TransactionId).txt"
        if (Test-Path -LiteralPath $claimPath) {
            $claim = Read-LedgerBankPostingFields -Path $claimPath
            if ($claim.OperationId -ne "$id" -or $claim.TransactionId -notmatch '^[1-9]\d*$' -or
                $claim.StatementNumber -notmatch '^[1-9]\d*$' -or $claim.BankHash -cnotmatch '^[0-9a-f]{64}$' -or
                $operation.VatRate -ne 0 -or -not $owners.Add([int]$claim.TransactionId)) {
                throw "Invalid or conflicting bank counterpart record '$claimPath'."
            }
            $operation.Counterpart = [pscustomobject]@{
                TransactionId = [int]$claim.TransactionId; StatementNumber = [int]$claim.StatementNumber; BankHash = $claim.BankHash
            }
        }
        $operation
    }
}

function Get-LedgerBankPostingOwner {
    [CmdletBinding()]
    param ([object[]]$Operations, [int]$TransactionId)
    $found = @($Operations | Where-Object { $_.TransactionId -eq $TransactionId -or $_.Counterpart.TransactionId -eq $TransactionId })
    if ($found.Count -gt 1) { throw "Bank transaction $TransactionId has conflicting posting plans." }
    $found
}

function Assert-LedgerBankPostingSource {
    [CmdletBinding()]
    param ([psobject]$Transaction, [psobject]$Operation, [switch]$Counterpart)

    $source = if ($Counterpart) { $Operation.Counterpart } else { $Operation }
    $account = if ($Counterpart) { $Operation.Account } else { $Operation.BankAccount }
    $amount = if ($Counterpart) { -$Operation.Amount } else { $Operation.Amount }
    $type = if ($Counterpart) { 'Entry' } else { $Operation.MatchType }
    $ref = if ($Counterpart) { "$($Operation.FiscalYear)/$($Operation.VerificationNumber)" } else { $Operation.MatchRef }
    if ($Transaction.TransactionId -ne $source.TransactionId -or $Transaction.StatementNumber -ne $source.StatementNumber -or
        (Get-LedgerBankTransactionHash -Transaction $Transaction) -ne $source.BankHash -or
        $Transaction.BankAccount -ne $account -or $Transaction.Amount -ne $amount) {
        throw "Bank transaction $($Transaction.TransactionId) differs from its saved posting plan. Recovery stopped."
    }
    if ($Transaction.Status -eq 'Unmatched' -and -not $Transaction.MatchType -and -not $Transaction.MatchRef -and
        -not $Transaction.FiscalYear -and -not $Transaction.VerificationNumber) { return }
    if ($Transaction.Status -eq 'Matched' -and $Transaction.MatchType -eq $type -and $Transaction.MatchRef -eq $ref -and
        $Transaction.FiscalYear -eq $Operation.FiscalYear -and $Transaction.VerificationNumber -eq $Operation.VerificationNumber) { return }
    throw "Bank transaction $($Transaction.TransactionId) has a conflicting saved posting link."
}

function Save-LedgerBankPostingCounterpart {
    [CmdletBinding()]
    param ([string]$JournalPath, [psobject]$Operation, [psobject]$Transaction)

    $primary = Find-LedgerBankTransaction -JournalPath $JournalPath -TransactionId $Operation.TransactionId
    Assert-LedgerBankPostingSource -Transaction $primary.Transaction -Operation $Operation
    $owners = @(Get-LedgerBankPostingOperation -JournalPath $JournalPath)
    if ($Operation.Counterpart -or (Get-LedgerBankPostingOwner -Operations $owners -TransactionId $Transaction.TransactionId) -or
        (Get-LedgerBankInvoicePaymentOperation -Transaction $Transaction -Operations @(Get-LedgerInvoicePaymentOperation -JournalPath $JournalPath)) -or
        $Operation.VatRate -ne 0 -or $Operation.Account -eq $Operation.BankAccount -or $Transaction.BankAccount -ne $Operation.Account -or
        $Transaction.Amount -ne -$Operation.Amount -or $Transaction.Status -ne 'Unmatched' -or
        [Math]::Abs(($Transaction.Date - $Operation.Date).TotalDays) -gt $Operation.DateTolerance) {
        throw "Bank transaction $($Transaction.TransactionId) cannot be claimed as this posting's counterpart."
    }
    $fields = [ordered]@{
        OperationId = $Operation.OperationId; TransactionId = $Transaction.TransactionId
        StatementNumber = $Transaction.StatementNumber; BankHash = Get-LedgerBankTransactionHash -Transaction $Transaction
    }
    Save-LedgerBankPostingFields -Path (Join-Path (Split-Path $Operation.Path -Parent) "counterpart$($Operation.TransactionId).txt") -Fields $fields
    $Operation.Counterpart = [pscustomobject]$fields
}

function Find-LedgerBankPostingCounterpart {
    [CmdletBinding()]
    param ([string]$JournalPath, [psobject]$Operation)

    if ($Operation.VatRate -ne 0 -or $Operation.Account -eq $Operation.BankAccount -or $Operation.Counterpart -or $Operation.ManualCounterpart) { return }
    $operations = @(Get-LedgerBankPostingOperation -JournalPath $JournalPath)
    $payments = @(Get-LedgerInvoicePaymentOperation -JournalPath $JournalPath)
    $candidates = @(foreach ($s in Get-LedgerBankStatementData -JournalPath $JournalPath) {
        if ($s.BankAccount -ne $Operation.Account) { continue }
        foreach ($t in $s.Transactions) {
            if ($t.Status -ne 'Unmatched' -or $t.Amount -ne -$Operation.Amount -or
                [Math]::Abs(($t.Date - $Operation.Date).TotalDays) -gt $Operation.DateTolerance) { continue }
            if (Get-LedgerBankPostingOwner -Operations $operations -TransactionId $t.TransactionId) { continue }
            if (Get-LedgerBankInvoicePaymentOperation -Transaction $t -Operations $payments) { continue }
            $t
        }
    })
    if (-not $candidates.Count) { return }
    $ordered = @($candidates | Sort-Object { [Math]::Abs(($_.Date - $Operation.Date).TotalDays) })
    $nearest = @($ordered | Where-Object { [Math]::Abs(($_.Date - $Operation.Date).TotalDays) -eq [Math]::Abs(($ordered[0].Date - $Operation.Date).TotalDays) })
    $ambiguous = $nearest.Count -ne 1
    if (-not $ambiguous) {
        $candidate = $nearest[0]
        $competing = @($operations | Where-Object {
            -not $_.Counterpart -and $_.VatRate -eq 0 -and $_.Account -eq $candidate.BankAccount -and
                $_.Amount -eq -$candidate.Amount -and [Math]::Abs(($_.Date - $candidate.Date).TotalDays) -le $_.DateTolerance
        } | Sort-Object { [Math]::Abs(($_.Date - $candidate.Date).TotalDays) })
        $closest = @($competing | Where-Object {
            [Math]::Abs(($_.Date - $candidate.Date).TotalDays) -eq [Math]::Abs(($competing[0].Date - $candidate.Date).TotalDays)
        })
        $ambiguous = $closest.Count -gt 1
        if (-not $ambiguous -and $closest[0].TransactionId -ne $Operation.TransactionId) { return }
    }
    if ($ambiguous) {
        Save-LedgerBankPostingFields -Path (Join-Path (Split-Path $Operation.Path -Parent) "ambiguous$($Operation.TransactionId).txt") `
            -Fields ([ordered]@{ OperationId = $Operation.OperationId })
        $Operation.ManualCounterpart = $true
        Write-Warning "Bank transaction $($Operation.TransactionId) has ambiguous counterparts. Its posting is retained; select the counterpart manually with Set-LedgerBankTransaction -VerificationNumber $($Operation.VerificationNumber) -FiscalYear '$($Operation.FiscalYear)'."
        return
    }
    Save-LedgerBankPostingCounterpart -JournalPath $JournalPath -Operation $Operation -Transaction $nearest[0]
}

function Complete-LedgerBankPosting {
    [CmdletBinding()]
    param ([string]$JournalPath, [psobject]$Operation)

    try {
        $primary = Find-LedgerBankTransaction -JournalPath $JournalPath -TransactionId $Operation.TransactionId
        Assert-LedgerBankPostingSource -Transaction $primary.Transaction -Operation $Operation
        if ($Operation.Counterpart) {
            $counter = Find-LedgerBankTransaction -JournalPath $JournalPath -TransactionId $Operation.Counterpart.TransactionId
            Assert-LedgerBankPostingSource -Transaction $counter.Transaction -Operation $Operation -Counterpart
        }
        $rows = @(Get-LedgerBankEntryRows -BankAccount $Operation.BankAccount -Amount $Operation.Amount `
            -Account $Operation.Account -VatRate $Operation.VatRate -VatAccount $Operation.VatAccount)
        $path = Join-Path $JournalPath $Operation.FiscalYear ('ver{0:D4}.txt' -f $Operation.VerificationNumber)
        if (Test-Path -LiteralPath $path) {
            Assert-LedgerInvoicePostingVerification -Path $path -Operation $Operation
            $entry = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $Operation.FiscalYear -VerificationNumber $Operation.VerificationNumber
            if ($entry.Date -ne $Operation.Date.ToString('yyyy-MM-dd') -or $entry.Description -ne $Operation.Description -or $entry.Rows.Count -ne $rows.Count) {
                throw 'Saved bank verification does not match its planned inputs.'
            }
            for ($i = 0; $i -lt $rows.Count; $i++) {
                if ($entry.Rows[$i].Account -ne $rows[$i].Account -or $entry.Rows[$i].Amount -ne $rows[$i].Amount) {
                    throw 'Saved bank verification does not match its planned rows.'
                }
            }
        }
        else {
            Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $Operation.FiscalYear
            $parameters = @{
                JournalPath = $JournalPath; FiscalYear = $Operation.FiscalYear; Date = $Operation.Date
                Description = $Operation.Description; Rows = $rows; OperationId = $Operation.OperationId
            }
            $lines = @(Get-LedgerVerificationLines @parameters)
            $hash = Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
            if ($hash -ne $Operation.VerificationHash) { throw 'Bank posting inputs no longer produce the saved verification plan.' }
            Write-LedgerVerification @parameters -ReservedNumber $Operation.VerificationNumber -Confirm:$false
        }
        Complete-LedgerInvoicePostingVerification -JournalPath $JournalPath -Operation $Operation
        Find-LedgerBankPostingCounterpart -JournalPath $JournalPath -Operation $Operation
        $changed = @()
        foreach ($id in @($Operation.TransactionId, $Operation.Counterpart.TransactionId)) {
            if (-not $id) { continue }
            $found = Find-LedgerBankTransaction -JournalPath $JournalPath -TransactionId $id
            $counterpart = $id -ne $Operation.TransactionId
            Assert-LedgerBankPostingSource -Transaction $found.Transaction -Operation $Operation -Counterpart:$counterpart
            if ($found.Transaction.Status -eq 'Matched') { continue }
            $type = if ($counterpart) { 'Entry' } else { $Operation.MatchType }
            $ref = if ($counterpart) { "$($Operation.FiscalYear)/$($Operation.VerificationNumber)" } else { $Operation.MatchRef }
            Set-LedgerBankTransactionState -Statement $found.Statement -Transaction $found.Transaction -Status Matched `
                -MatchType $type -MatchRef $ref -FiscalYear $Operation.FiscalYear -VerificationNumber $Operation.VerificationNumber
            $changed += ConvertTo-LedgerBankTransactionOutput -Transaction $found.Transaction
        }
        [pscustomobject]@{ FiscalYear = $Operation.FiscalYear; VerificationNumber = $Operation.VerificationNumber; Changed = $changed }
    }
    catch {
        throw [InvalidOperationException]::new(
            "Bank posting for transaction $($Operation.TransactionId) could not complete. Keep '$($Operation.Path)' and retry Invoke-LedgerBankMatching or the original Set-LedgerBankTransaction command. $($_.Exception.Message)", $_.Exception)
    }
}
