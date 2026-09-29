<#
.SYNOPSIS
Imports a bank statement (camt.053 or CSV) into the journal.

.DESCRIPTION
Reads the transactions from a bank file and stores them as a bank statement
under the journal's 'bank/' directory (bank/stmt0001.txt, ...). The
transactions are not posted; they start as 'Unmatched' and are matched and
posted with Invoke-LedgerBankMatching or Set-LedgerBankTransaction, and the bank
account is reconciled against the ledger with Get-LedgerBankReconciliation.

Two formats are supported:

- Camt053: ISO 20022 camt.053 XML (bankens kontoutdrag), which most Swedish
  banks offer. Only booked entries are imported, and opening and closing
  balances are taken from the statement. An entry holding several payments
  with their own amounts (for example a batch of OCR payments) is split into
  one transaction per payment.
- Csv: a CSV export from the internet bank. The header row is located
  automatically and preamble lines before it are skipped. Columns are
  recognised from common names (Bokföringsdag/Datum, Belopp, Beskrivning/Text,
  Referens, Mottagare/Avsändare, Bokfört saldo/Saldo) or given explicitly with
  the *Column parameters. The delimiter, the decimal separator and the file
  encoding (UTF-8 or ISO-8859-1) are detected automatically. With a balance
  column the opening and closing balances are derived from the running
  balance.

Transactions already imported for the same bank account are skipped, so
overlapping files can be imported safely. Transactions are identified by the
bank's own reference when the file has one, otherwise by date, amount,
reference and text (identical transactions are counted, so two equal card
purchases on the same day are both kept).

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Path
The bank file to import.

.PARAMETER Format
The file format: 'Camt053' or 'Csv'. Defaults to Camt053 for .xml files and Csv
otherwise.

.PARAMETER Account
The ledger account that represents the bank account. Defaults to '1930'
(Företagskonto/checkkonto). A ledger account can only hold statements for one
bank account (IBAN); importing a statement for another bank account into the
same ledger account is refused.

.PARAMETER AccountId
Camt053 only. Imports only the statement for this bank account (IBAN or
account number, spaces ignored). Required when the file holds statements for
several bank accounts.

.PARAMETER Delimiter
CSV only. The field delimiter. Detected from the header row if omitted.

.PARAMETER Encoding
CSV only. The file encoding, e.g. 'utf-8' or 'iso-8859-1'. Detected if omitted.

.PARAMETER DateFormat
CSV only. A .NET date format such as 'yyyy-MM-dd'. Common ISO and Swedish
formats are recognised if omitted.

.PARAMETER DecimalSeparator
CSV only. ',' or '.'. Detected per value if omitted.

.PARAMETER DateColumn
CSV only. The name of the booking date column.

.PARAMETER AmountColumn
CSV only. The name of the signed amount column.

.PARAMETER TextColumn
CSV only. The name of the description column.

.PARAMETER ReferenceColumn
CSV only. The name of the payment reference (OCR) column.

.PARAMETER CounterpartyColumn
CSV only. The name of the counterparty (payer/payee) column.

.PARAMETER BalanceColumn
CSV only. The name of the running balance column.

.EXAMPLE
Import-LedgerBankStatement -JournalPath .\MinFirma.ledger -Path .\kontoutdrag-2024-03.xml

Imports a camt.053 statement for the business account 1930 and returns a
summary with the number of imported and skipped transactions.

.EXAMPLE
Import-LedgerBankStatement -Path .\Swedbank-transaktioner.csv -Account 1930 -Encoding 'iso-8859-1' `
    -DateColumn 'Bokföringsdag' -AmountColumn 'Belopp' -TextColumn 'Beskrivning' `
    -ReferenceColumn 'Referens' -BalanceColumn 'Bokfört saldo'

Imports a CSV export from the internet bank into the current journal with an
explicit column mapping.
#>
function Import-LedgerBankStatement {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Camt053', 'Csv')]
        [string]$Format,

        [Parameter()]
        [string]$Account = '1930',

        [Parameter()]
        [string]$AccountId,

        [Parameter()]
        [string]$Delimiter,

        [Parameter()]
        [string]$Encoding,

        [Parameter()]
        [string]$DateFormat,

        [Parameter()]
        [ValidateSet(',', '.')]
        [string]$DecimalSeparator,

        [Parameter()]
        [string]$DateColumn,

        [Parameter()]
        [string]$AmountColumn,

        [Parameter()]
        [string]$TextColumn,

        [Parameter()]
        [string]$ReferenceColumn,

        [Parameter()]
        [string]$CounterpartyColumn,

        [Parameter()]
        [string]$BalanceColumn
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Bank file not found: $Path"
    }
    if (-not $Format) {
        $Format = if ([System.IO.Path]::GetExtension($Path) -ieq '.xml') { 'Camt053' } else { 'Csv' }
    }

    $parsed = if ($Format -eq 'Camt053') {
        @(ConvertFrom-LedgerCamt053 -Path $Path)
    }
    else {
        $csvParams = @{ Path = $Path }
        foreach ($name in 'Delimiter', 'Encoding', 'DateFormat', 'DecimalSeparator', 'DateColumn', 'AmountColumn',
            'TextColumn', 'ReferenceColumn', 'CounterpartyColumn', 'BalanceColumn') {
            if ($PSBoundParameters.ContainsKey($name)) { $csvParams[$name] = $PSBoundParameters[$name] }
        }
        @(ConvertFrom-LedgerBankCsv @csvParams)
    }

    $existing = @(Get-LedgerBankStatementData -JournalPath $JournalPath)

    # One ledger account must map to one bank account: refuse a file holding
    # several accounts, or an account other than the one already imported.
    $normalizeId = { param($id) ([string]$id -replace '\s', '').ToUpperInvariant() }
    if ($AccountId -and $Format -eq 'Camt053') {
        $parsed = @($parsed | Where-Object { (& $normalizeId $_.AccountId) -eq (& $normalizeId $AccountId) })
        if (-not $parsed) { throw "The file has no statement for bank account '$AccountId'." }
    }
    $fileIds = @($parsed | ForEach-Object { & $normalizeId $_.AccountId } | Where-Object { $_ } | Select-Object -Unique)
    if ($fileIds.Count -gt 1) {
        throw "The file holds statements for several bank accounts ($($fileIds -join ', ')). Import them one at a time with -AccountId and -Account."
    }
    if ($fileIds.Count -eq 1) {
        $knownIds = @($existing | Where-Object BankAccount -eq $Account | ForEach-Object { & $normalizeId $_.AccountId } | Where-Object { $_ } | Select-Object -Unique)
        if ($knownIds -and $fileIds[0] -notin $knownIds) {
            throw "Ledger account $Account already holds statements for bank account $($knownIds -join ', '), not $($fileIds[0]). Use -Account to import into another ledger account."
        }
    }
    $nextStatement = 1 + (@($existing | ForEach-Object { $_.StatementNumber }) + 0 | Measure-Object -Maximum).Maximum
    $nextTransaction = 1 + (@($existing | ForEach-Object { $_.Transactions } | ForEach-Object { $_.TransactionId }) + 0 | Measure-Object -Maximum).Maximum

    # Index what is already stored for this bank account so overlapping files
    # do not import the same transaction twice.
    $knownRefs = [System.Collections.Generic.HashSet[string]]::new()
    $knownPrints = @{}
    $fingerprint = { param($t) '{0}|{1}|{2}|{3}' -f $t.Date.ToString('yyyy-MM-dd'), (Format-LedgerInvoiceAmount -Value ([decimal]$t.Amount)), (ConvertTo-LedgerBankField $t.Reference), (ConvertTo-LedgerBankField $t.Text) }
    foreach ($s in ($existing | Where-Object BankAccount -eq $Account)) {
        foreach ($t in $s.Transactions) {
            if ($t.BankReference) { [void]$knownRefs.Add($t.BankReference); continue }
            $key = & $fingerprint $t
            $knownPrints[$key] = 1 + [int]$knownPrints[$key]
        }
    }

    foreach ($p in $parsed) {
        if ($null -ne $p.OpeningBalance -and $null -ne $p.ClosingBalance) {
            $sum = [decimal]0
            foreach ($t in $p.Transactions) { $sum += $t.Amount }
            if ($p.OpeningBalance + $sum -ne $p.ClosingBalance) {
                Write-Warning "Statement '$($p.StatementId)' in '$Path' does not balance: opening $($p.OpeningBalance) + transactions $sum <> closing $($p.ClosingBalance)."
            }
        }
        if ($p.Currency -and $p.Currency -ne 'SEK') {
            Write-Warning "Statement '$($p.StatementId)' is in $($p.Currency); amounts are imported as they are, without currency conversion."
        }

        $seenInFile = @{}
        $new = [System.Collections.Generic.List[object]]::new()
        $skipped = 0
        foreach ($t in $p.Transactions) {
            if ($t.BankReference) {
                if ($knownRefs.Contains($t.BankReference)) { $skipped++; continue }
            }
            else {
                $key = & $fingerprint $t
                $seenInFile[$key] = 1 + [int]$seenInFile[$key]
                if ($seenInFile[$key] -le [int]$knownPrints[$key]) { $skipped++; continue }
            }
            $new.Add($t)
        }

        $fileName = Split-Path -Leaf $Path
        if ($new.Count -eq 0) {
            Write-Warning "No new transactions in '$fileName'$(if ($p.StatementId) { " (statement $($p.StatementId))" }); nothing was imported."
            [PSCustomObject]@{
                StatementNumber = $null
                BankAccount     = $Account
                FromDate        = $p.FromDate
                ToDate          = $p.ToDate
                OpeningBalance  = $p.OpeningBalance
                ClosingBalance  = $p.ClosingBalance
                Imported        = 0
                Skipped         = $skipped
            }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($fileName, "Import $($new.Count) bank transactions for account $Account")) {
            continue
        }

        $dir = Get-LedgerBankDirectory -JournalPath $JournalPath -Create
        $transactions = [System.Collections.Generic.List[object]]::new()
        foreach ($t in $new) {
            $transactions.Add([PSCustomObject]@{
                TransactionId      = $nextTransaction++
                StatementNumber    = $nextStatement
                BankAccount        = $Account
                Date               = $t.Date
                Amount             = [decimal]$t.Amount
                BankReference      = ConvertTo-LedgerBankField $t.BankReference
                Reference          = ConvertTo-LedgerBankField $t.Reference
                Counterparty       = ConvertTo-LedgerBankField $t.Counterparty
                Text               = ConvertTo-LedgerBankField $t.Text
                Status             = 'Unmatched'
                MatchType          = ''
                MatchRef           = ''
                FiscalYear         = ''
                VerificationNumber = $null
            })
            if ($t.BankReference) { [void]$knownRefs.Add($t.BankReference) }
        }
        foreach ($key in $seenInFile.Keys) {
            if ($seenInFile[$key] -gt [int]$knownPrints[$key]) { $knownPrints[$key] = $seenInFile[$key] }
        }

        $statement = [PSCustomObject]@{
            StatementNumber = $nextStatement
            BankAccount     = $Account
            Source          = $Format
            FileName        = $fileName
            StatementId     = $p.StatementId
            AccountId       = $p.AccountId
            Currency        = $p.Currency
            FromDate        = $p.FromDate
            ToDate          = $p.ToDate
            OpeningBalance  = $p.OpeningBalance
            ClosingBalance  = $p.ClosingBalance
            ImportedDate    = (Get-Date).Date
            Transactions    = $transactions
            FilePath        = Join-Path $dir (Get-LedgerBankStatementFileName -StatementNumber $nextStatement)
        }
        Save-LedgerBankStatementFile -Statement $statement

        [PSCustomObject]@{
            StatementNumber = $nextStatement
            BankAccount     = $Account
            FromDate        = $p.FromDate
            ToDate          = $p.ToDate
            OpeningBalance  = $p.OpeningBalance
            ClosingBalance  = $p.ClosingBalance
            Imported        = $transactions.Count
            Skipped         = $skipped
        }
        $nextStatement++
    }
}
