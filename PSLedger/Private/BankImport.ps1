# Parsers that turn bank files into statement data for Import-LedgerBankStatement.
#
# Each parser returns one or more "parsed statement" objects with AccountId,
# StatementId, Currency, FromDate, ToDate, OpeningBalance, ClosingBalance and a
# Transactions list (Date, Amount, BankReference, Reference, Counterparty, Text).
# Amounts are signed from the account holder's point of view: money in is
# positive, money out is negative.

function Read-LedgerBankTextFile {
    <#
    .SYNOPSIS
    Reads a text file, honouring a byte order mark, and falls back from UTF-8 to
    ISO-8859-1 when the bytes are not valid UTF-8 (common for bank CSV exports).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Encoding
    )
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).ProviderPath)

    if ($Encoding) {
        try {
            [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
        }
        catch {
            Write-Verbose "Code page encodings not available: $($_.Exception.Message)"
        }
        return [System.Text.Encoding]::GetEncoding($Encoding).GetString($bytes)
    }

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    try {
        return [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    }
    catch {
        return [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
    }
}

function ConvertFrom-LedgerBankAmount {
    <#
    .SYNOPSIS
    Parses an amount as written by a bank, e.g. '-1 234,50', '1234.50',
    '1.234,50', '1,234.50' or '250,00-'.

    .DESCRIPTION
    Spaces (including non-breaking spaces) and currency markers are removed.
    Without an explicit DecimalSeparator the last of ',' and '.' is taken as the
    decimal separator when both occur; a single ',' or '.' is a decimal separator
    and a repeated one is a thousands separator.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [string]$DecimalSeparator
    )
    $t = $Text -replace '[\s\u00A0\u202F]', '' -replace '(?i)SEK|kr', ''
    $t = $t -replace '[\u2212\u2013]', '-'
    if ([string]::IsNullOrEmpty($t)) { throw "Empty amount." }

    $negative = $false
    if ($t.EndsWith('-')) { $negative = $true; $t = $t.TrimEnd('-') }
    if ($t.StartsWith('-')) { $negative = -not $negative; $t = $t.Substring(1) }
    elseif ($t.StartsWith('+')) { $t = $t.Substring(1) }

    if ($DecimalSeparator) {
        $thousands = if ($DecimalSeparator -eq ',') { '.' } else { ',' }
        $t = $t.Replace($thousands, '').Replace($DecimalSeparator, '.')
    }
    else {
        $comma = $t.LastIndexOf(',')
        $dot = $t.LastIndexOf('.')
        if ($comma -ge 0 -and $dot -ge 0) {
            if ($comma -gt $dot) { $t = $t.Replace('.', '').Replace(',', '.') }
            else { $t = $t.Replace(',', '') }
        }
        elseif ($comma -ge 0) {
            if (($t.Split(',').Count - 1) -gt 1) { $t = $t.Replace(',', '') } else { $t = $t.Replace(',', '.') }
        }
        elseif ($dot -ge 0 -and ($t.Split('.').Count - 1) -gt 1) {
            $t = $t.Replace('.', '')
        }
    }

    $value = [decimal]0
    if (-not [decimal]::TryParse($t, [System.Globalization.NumberStyles]::AllowDecimalPoint, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
        throw "Could not parse amount '$Text'."
    }
    if ($negative) { $value = -$value }
    return $value
}

function ConvertFrom-LedgerBankDate {
    <#
    .SYNOPSIS
    Parses a bank date using the supplied format or common ISO/Swedish formats.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Text,

        [string]$DateFormat
    )
    $formats = if ($DateFormat) { @($DateFormat) } else {
        @('yyyy-MM-dd', 'yyyy/MM/dd', 'yyyyMMdd', 'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-dd HH:mm', 'dd.MM.yyyy', 'dd/MM/yyyy')
    }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($Text.Trim(), [string[]]$formats, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        return $parsed.Date
    }
    throw "Could not parse date '$Text'."
}

function Split-LedgerCsvLine {
    <#
    .SYNOPSIS
    Splits one CSV line into fields, honouring double-quoted fields.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line,

        [Parameter(Mandatory)]
        [string]$Delimiter
    )
    $fields = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new()
    $inQuotes = $false
    $d = $Delimiter[0]
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($inQuotes) {
            if ($c -eq '"') {
                if ($i + 1 -lt $Line.Length -and $Line[$i + 1] -eq '"') { [void]$sb.Append('"'); $i++ }
                else { $inQuotes = $false }
            }
            else { [void]$sb.Append($c) }
        }
        elseif ($c -eq '"') { $inQuotes = $true }
        elseif ($c -eq $d) { $fields.Add($sb.ToString().Trim()); [void]$sb.Clear() }
        else { [void]$sb.Append($c) }
    }
    $fields.Add($sb.ToString().Trim())
    return , $fields.ToArray()
}

function ConvertFrom-LedgerBankCsv {
    <#
    .SYNOPSIS
    Parses a bank CSV export into a single parsed statement.

    .DESCRIPTION
    The header row is located automatically (preamble lines before it are
    skipped) as the first line that contains both a date and an amount column.
    Columns are either given explicitly or recognised from common Swedish and
    English column names. The delimiter (';', ',' or tab) is detected from the
    header row unless given. With a balance column the opening and closing
    balances are derived from the running balance, whether the file lists the
    newest or the oldest transaction first.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Delimiter,
        [string]$Encoding,
        [string]$DateFormat,
        [string]$DecimalSeparator,
        [string]$DateColumn,
        [string]$AmountColumn,
        [string]$TextColumn,
        [string]$ReferenceColumn,
        [string]$CounterpartyColumn,
        [string]$BalanceColumn
    )

    $candidates = @{
        Date         = @('Bokföringsdag', 'Bokföringsdatum', 'Bokförd', 'Bokfört', 'Datum', 'Transaktionsdag', 'Transaktionsdatum', 'Date', 'Booking date')
        Amount       = @('Belopp', 'Belopp SEK', 'Amount')
        Text         = @('Beskrivning', 'Text', 'Rubrik', 'Transaktion', 'Specifikation', 'Meddelande', 'Description')
        Reference    = @('Referens', 'OCR', 'Reference')
        Counterparty = @('Motpart', 'Mottagare', 'Avsändare', 'Namn', 'Counterparty')
        Balance      = @('Bokfört saldo', 'Saldo', 'Balance')
    }
    $explicit = @{
        Date = $DateColumn; Amount = $AmountColumn; Text = $TextColumn
        Reference = $ReferenceColumn; Counterparty = $CounterpartyColumn; Balance = $BalanceColumn
    }

    $resolveColumns = {
        param([string[]]$Header)
        $map = @{}
        foreach ($key in $candidates.Keys) {
            $names = if ($explicit[$key]) { @($explicit[$key]) } else { $candidates[$key] }
            foreach ($name in $names) {
                for ($i = 0; $i -lt $Header.Count; $i++) {
                    if ($Header[$i] -ieq $name) { $map[$key] = $i; break }
                }
                if ($map.ContainsKey($key)) { break }
            }
        }
        return $map
    }

    $content = Read-LedgerBankTextFile -Path $Path -Encoding $Encoding
    $lines = $content -split "\r?\n"
    $delimiters = if ($Delimiter) { @($Delimiter) } else { @(';', ',', "`t") }

    $headerIndex = -1
    $columns = $null
    $delim = $null
    for ($i = 0; $i -lt [Math]::Min($lines.Count, 50) -and $headerIndex -lt 0; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        foreach ($d in $delimiters) {
            $header = Split-LedgerCsvLine -Line $lines[$i] -Delimiter $d
            $map = & $resolveColumns $header
            if ($map.ContainsKey('Date') -and $map.ContainsKey('Amount')) {
                $headerIndex = $i; $columns = $map; $delim = $d
                break
            }
        }
    }
    if ($headerIndex -lt 0) {
        $wanted = if ($DateColumn -or $AmountColumn) { "'$DateColumn' and '$AmountColumn'" } else { 'a date column and an amount column' }
        throw "Could not find a header row with $wanted in '$Path'. Specify -DateColumn and -AmountColumn (and -Delimiter if needed)."
    }
    foreach ($key in 'Text', 'Reference', 'Counterparty', 'Balance') {
        if ($explicit[$key] -and -not $columns.ContainsKey($key)) {
            throw "Column '$($explicit[$key])' was not found in the header row."
        }
    }

    $cell = { param($fields, $key) if ($columns.ContainsKey($key) -and $columns[$key] -lt $fields.Count) { $fields[$columns[$key]] } else { '' } }

    $transactions = [System.Collections.Generic.List[object]]::new()
    $balances = [System.Collections.Generic.List[object]]::new()
    for ($i = $headerIndex + 1; $i -lt $lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        $fields = Split-LedgerCsvLine -Line $lines[$i] -Delimiter $delim
        $dateText = & $cell $fields 'Date'
        $amountText = & $cell $fields 'Amount'
        if ([string]::IsNullOrWhiteSpace($dateText) -or [string]::IsNullOrWhiteSpace($amountText)) { continue }
        try {
            $date = ConvertFrom-LedgerBankDate -Text $dateText -DateFormat $DateFormat
            $amount = ConvertFrom-LedgerBankAmount -Text $amountText -DecimalSeparator $DecimalSeparator
        }
        catch {
            Write-Warning "Skipping line $($i + 1) in '$Path': $($_.Exception.Message)"
            continue
        }
        $transactions.Add([PSCustomObject]@{
            Date          = $date
            Amount        = $amount
            BankReference = ''
            Reference     = & $cell $fields 'Reference'
            Counterparty  = & $cell $fields 'Counterparty'
            Text          = & $cell $fields 'Text'
        })
        $balanceText = & $cell $fields 'Balance'
        $balances.Add($(if ($balanceText) { try { ConvertFrom-LedgerBankAmount -Text $balanceText -DecimalSeparator $DecimalSeparator } catch { $null } } else { $null }))
    }

    $opening = $null
    $closing = $null
    $n = $transactions.Count
    if ($n -gt 0 -and $columns.ContainsKey('Balance') -and $null -ne $balances[0] -and $null -ne $balances[$n - 1]) {
        $sum = [decimal]0
        foreach ($t in $transactions) { $sum += $t.Amount }
        # Oldest first: the first row's balance already includes its own amount.
        $ascOpening = $balances[0] - $transactions[0].Amount
        $ascClosing = $balances[$n - 1]
        $descOpening = $balances[$n - 1] - $transactions[$n - 1].Amount
        $descClosing = $balances[0]
        $descending = $transactions[0].Date -gt $transactions[$n - 1].Date
        $ascOk = ($ascOpening + $sum) -eq $ascClosing
        $descOk = ($descOpening + $sum) -eq $descClosing
        if (($descending -and $descOk) -or ($descOk -and -not $ascOk)) { $opening = $descOpening; $closing = $descClosing }
        elseif ($ascOk) { $opening = $ascOpening; $closing = $ascClosing }
        else { Write-Warning "The balance column in '$Path' does not agree with the amounts; opening and closing balances are not recorded." }
    }

    # Keep the stored order chronological.
    $ordered = @($transactions)
    if ($n -gt 1 -and $transactions[0].Date -gt $transactions[$n - 1].Date) {
        [array]::Reverse($ordered)
    }

    [PSCustomObject]@{
        AccountId      = ''
        StatementId    = ''
        Currency       = ''
        FromDate       = if ($n) { ($ordered | Measure-Object -Property Date -Minimum).Minimum } else { $null }
        ToDate         = if ($n) { ($ordered | Measure-Object -Property Date -Maximum).Maximum } else { $null }
        OpeningBalance = $opening
        ClosingBalance = $closing
        Transactions   = $ordered
    }
}

function Select-LedgerXmlNode {
    <#
    .SYNOPSIS
    Selects child nodes by a slash-separated path of local element names,
    ignoring XML namespaces (camt versions use different namespaces).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Node,

        [Parameter(Mandatory)]
        [string]$Path
    )
    $xpath = ($Path -split '/' | ForEach-Object { "*[local-name()='$_']" }) -join '/'
    return @($Node.SelectNodes($xpath))
}

function Get-LedgerXmlText {
    <#
    .SYNOPSIS
    Returns the trimmed text of the first non-empty node found by any of the
    given local-name paths, or an empty string.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Node,

        [Parameter(Mandatory)]
        [string[]]$Path
    )
    foreach ($p in $Path) {
        foreach ($n in (Select-LedgerXmlNode -Node $Node -Path $p)) {
            $text = $n.InnerText.Trim()
            if ($text) { return $text }
        }
    }
    return ''
}

function ConvertFrom-LedgerCamtAmount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Text,

        [string]$Indicator
    )
    $value = [decimal]::Parse($Text, [System.Globalization.CultureInfo]::InvariantCulture)
    if ($Indicator -eq 'DBIT') { $value = -$value }
    return $value
}

function ConvertFrom-LedgerCamt053 {
    <#
    .SYNOPSIS
    Parses an ISO 20022 camt.053 (or camt.052) file into parsed statements.

    .DESCRIPTION
    Only booked entries are imported. An entry that carries several transaction
    details with their own amounts (for example a batch of incoming OCR
    payments) is split into one transaction per detail so each payment can be
    matched individually. The structured creditor reference (OCR) becomes the
    Reference; unstructured remittance information and additional entry
    information become the Text. The counterparty is the debtor for incoming
    and the creditor for outgoing payments.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    $doc = [System.Xml.XmlDocument]::new()
    $doc.PreserveWhitespace = $false
    $doc.Load((Resolve-Path -LiteralPath $Path).ProviderPath)

    $statements = @($doc.SelectNodes("//*[local-name()='Stmt' or local-name()='Rpt']"))
    if (-not $statements) {
        throw "No camt.053 statement (Stmt) found in '$Path'."
    }

    foreach ($stmt in $statements) {
        $opening = $null; $closing = $null; $prcd = $null
        $openingDate = $null; $closingDate = $null
        foreach ($bal in (Select-LedgerXmlNode -Node $stmt -Path 'Bal')) {
            $code = Get-LedgerXmlText -Node $bal -Path 'Tp/CdOrPrtry/Cd'
            $amtText = Get-LedgerXmlText -Node $bal -Path 'Amt'
            if (-not $amtText) { continue }
            $amount = ConvertFrom-LedgerCamtAmount -Text $amtText -Indicator (Get-LedgerXmlText -Node $bal -Path 'CdtDbtInd')
            $dateText = Get-LedgerXmlText -Node $bal -Path 'Dt/Dt', 'Dt/DtTm'
            $date = if ($dateText) { [datetime]::ParseExact($dateText.Substring(0, 10), 'yyyy-MM-dd', $null) } else { $null }
            switch ($code) {
                'OPBD' { $opening = $amount; $openingDate = $date }
                'PRCD' { $prcd = $amount; if (-not $openingDate) { $openingDate = $date } }
                'CLBD' { $closing = $amount; $closingDate = $date }
            }
        }
        if ($null -eq $opening) { $opening = $prcd }

        $transactions = [System.Collections.Generic.List[object]]::new()
        foreach ($ntry in (Select-LedgerXmlNode -Node $stmt -Path 'Ntry')) {
            $status = Get-LedgerXmlText -Node $ntry -Path 'Sts/Cd', 'Sts'
            if ($status -and $status -ne 'BOOK') { continue }

            $indicator = Get-LedgerXmlText -Node $ntry -Path 'CdtDbtInd'
            $entryAmount = ConvertFrom-LedgerCamtAmount -Text (Get-LedgerXmlText -Node $ntry -Path 'Amt') -Indicator $indicator
            $dateText = Get-LedgerXmlText -Node $ntry -Path 'BookgDt/Dt', 'BookgDt/DtTm', 'ValDt/Dt', 'ValDt/DtTm'
            if (-not $dateText) { throw "An entry in '$Path' has no booking date." }
            $date = [datetime]::ParseExact($dateText.Substring(0, 10), 'yyyy-MM-dd', $null)
            $bankRef = Get-LedgerXmlText -Node $ntry -Path 'AcctSvcrRef', 'NtryRef'
            $entryInfo = Get-LedgerXmlText -Node $ntry -Path 'AddtlNtryInf'

            $details = @(Select-LedgerXmlNode -Node $ntry -Path 'NtryDtls/TxDtls')
            $parsedDetails = foreach ($tx in $details) {
                $txIndicator = Get-LedgerXmlText -Node $tx -Path 'CdtDbtInd'
                if (-not $txIndicator) { $txIndicator = $indicator }
                $txAmountText = Get-LedgerXmlText -Node $tx -Path 'Amt', 'AmtDtls/TxAmt/Amt'
                $partyPaths = if ($txIndicator -eq 'DBIT') {
                    @('RltdPties/Cdtr/Nm', 'RltdPties/Cdtr/Pty/Nm')
                } else {
                    @('RltdPties/Dbtr/Nm', 'RltdPties/Dbtr/Pty/Nm')
                }
                $endToEnd = Get-LedgerXmlText -Node $tx -Path 'Refs/EndToEndId'
                if ($endToEnd -eq 'NOTPROVIDED') { $endToEnd = '' }
                $reference = Get-LedgerXmlText -Node $tx -Path 'RmtInf/Strd/CdtrRefInf/Ref', 'RmtInf/Strd/CdtrRefInf/CdtrRef'
                $ustrd = @(Select-LedgerXmlNode -Node $tx -Path 'RmtInf/Ustrd' | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_ }) -join ' '
                $text = @($ustrd, (Get-LedgerXmlText -Node $tx -Path 'AddtlTxInf')) | Where-Object { $_ }
                [PSCustomObject]@{
                    Amount       = if ($txAmountText) { ConvertFrom-LedgerCamtAmount -Text $txAmountText -Indicator $txIndicator } else { $null }
                    Reference    = if ($reference) { $reference } else { $endToEnd }
                    Counterparty = Get-LedgerXmlText -Node $tx -Path $partyPaths
                    Text         = ($text -join ' ')
                    AcctSvcrRef  = Get-LedgerXmlText -Node $tx -Path 'Refs/AcctSvcrRef'
                }
            }
            $parsedDetails = @($parsedDetails)

            $split = $false
            if ($parsedDetails.Count -gt 1 -and -not ($parsedDetails | Where-Object { $null -eq $_.Amount })) {
                $detailSum = [decimal]0
                foreach ($pd in $parsedDetails) { $detailSum += $pd.Amount }
                $split = $detailSum -eq $entryAmount
            }

            if ($split) {
                for ($i = 0; $i -lt $parsedDetails.Count; $i++) {
                    $pd = $parsedDetails[$i]
                    $transactions.Add([PSCustomObject]@{
                        Date          = $date
                        Amount        = $pd.Amount
                        BankReference = if ($pd.AcctSvcrRef) { $pd.AcctSvcrRef } elseif ($bankRef) { "$bankRef/$($i + 1)" } else { '' }
                        Reference     = $pd.Reference
                        Counterparty  = $pd.Counterparty
                        Text          = (@($pd.Text, $entryInfo) | Where-Object { $_ }) -join ' '
                    })
                }
            }
            else {
                $first = if ($parsedDetails.Count -gt 0) { $parsedDetails[0] } else { $null }
                $texts = @($parsedDetails | ForEach-Object { $_.Text }) + $entryInfo | Where-Object { $_ } | Select-Object -Unique
                $transactions.Add([PSCustomObject]@{
                    Date          = $date
                    Amount        = $entryAmount
                    BankReference = $bankRef
                    Reference     = if ($first) { $first.Reference } else { '' }
                    Counterparty  = if ($first) { $first.Counterparty } else { '' }
                    Text          = ($texts -join ' ')
                })
            }
        }

        $fromText = Get-LedgerXmlText -Node $stmt -Path 'FrToDt/FrDtTm', 'FrToDt/FrDt'
        $toText = Get-LedgerXmlText -Node $stmt -Path 'FrToDt/ToDtTm', 'FrToDt/ToDt'
        $fromDate = if ($fromText) { [datetime]::ParseExact($fromText.Substring(0, 10), 'yyyy-MM-dd', $null) }
                    elseif ($openingDate) { $openingDate }
                    elseif ($transactions.Count) { ($transactions | Measure-Object -Property Date -Minimum).Minimum }
                    else { $null }
        $toDate = if ($toText) { [datetime]::ParseExact($toText.Substring(0, 10), 'yyyy-MM-dd', $null) }
                  elseif ($closingDate) { $closingDate }
                  elseif ($transactions.Count) { ($transactions | Measure-Object -Property Date -Maximum).Maximum }
                  else { $null }

        [PSCustomObject]@{
            AccountId      = Get-LedgerXmlText -Node $stmt -Path 'Acct/Id/IBAN', 'Acct/Id/Othr/Id'
            StatementId    = Get-LedgerXmlText -Node $stmt -Path 'Id'
            Currency       = Get-LedgerXmlText -Node $stmt -Path 'Acct/Ccy'
            FromDate       = $fromDate
            ToDate         = $toDate
            OpeningBalance = $opening
            ClosingBalance = $closing
            Transactions   = $transactions.ToArray()
        }
    }
}
