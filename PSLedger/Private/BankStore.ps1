# Helpers for the bank statement store under a journal's 'bank/' directory.
#
# Every import creates one statement file (stmt0001.txt, stmt0002.txt, ...) with
# tab-separated "Key:\tValue" metadata lines (bank account, period, opening and
# closing balance) followed by a 'Transactions:' section with one transaction
# per line:
#
#   Id  Date  Amount  BankReference  Reference  Counterparty  Text  Status
#   MatchType  MatchRef  FiscalYear  VerificationNumber
#
# Transaction ids are unique across all statements of a journal so a single id
# is enough to address a transaction. The optional 'rules.txt' holds the
# konteringsregler used to post recurring bank transactions automatically:
#
#   Pattern  Account  Description  VatRate  VatAccount
#
# Amounts are written and read with the invariant culture.

$script:LedgerBankTransactionStatuses = @('Unmatched', 'Matched', 'Ignored')

function Get-LedgerBankDirectory {
    <#
    .SYNOPSIS
    Returns the path to a journal's bank directory, optionally creating it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [switch]$Create
    )
    $dir = Join-Path $JournalPath 'bank'
    if ($Create -and -not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory | Out-Null
    }
    return $dir
}

function Get-LedgerBankStatementFileName {
    <#
    .SYNOPSIS
    Returns the file name (stmt0001.txt) for a given statement number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$StatementNumber
    )
    return 'stmt' + $StatementNumber.ToString('0000') + '.txt'
}

function ConvertTo-LedgerBankField {
    <#
    .SYNOPSIS
    Collapses tabs and line breaks so a free-text value fits in one tab-separated
    column.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return (($Text -replace "[`t`r`n]+", ' ') -replace '\s{2,}', ' ').Trim()
}

function ConvertTo-LedgerBankStatementObject {
    <#
    .SYNOPSIS
    Parses the lines of a statement file into a statement object with its
    transactions.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Content,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $meta = @{}
    $transactions = [System.Collections.Generic.List[object]]::new()
    $section = 'meta'

    foreach ($line in $Content) {
        if ($line -match '^\s*;') { continue }
        if ($line -eq 'Transactions:') { $section = 'transactions'; continue }

        if ($section -eq 'transactions') {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $p = $line -split "`t"
            if ($p.Count -lt 3) { continue }
            $field = { param($i) if ($p.Count -gt $i) { $p[$i] } else { '' } }
            $transactions.Add([PSCustomObject]@{
                TransactionId      = [int]$p[0]
                StatementNumber    = [int]$meta['StatementNumber']
                BankAccount        = $meta['BankAccount']
                Date               = [datetime]::ParseExact($p[1], 'yyyy-MM-dd', $null)
                Amount             = ConvertFrom-LedgerInvoiceAmount -Text $p[2]
                BankReference      = & $field 3
                Reference          = & $field 4
                Counterparty       = & $field 5
                Text               = & $field 6
                Status             = if (& $field 7) { & $field 7 } else { 'Unmatched' }
                MatchType          = & $field 8
                MatchRef           = & $field 9
                FiscalYear         = & $field 10
                VerificationNumber = if (& $field 11) { [int](& $field 11) } else { $null }
            })
            continue
        }

        $parts = $line -split "`t", 2
        if ($parts.Count -ge 2) {
            $meta[$parts[0].TrimEnd(':')] = $parts[1]
        }
    }

    $parseDate = { param($v) if ($v) { [datetime]::ParseExact($v, 'yyyy-MM-dd', $null) } else { $null } }
    $parseAmount = { param($v) if ($v) { ConvertFrom-LedgerInvoiceAmount -Text $v } else { $null } }

    [PSCustomObject]@{
        StatementNumber = [int]$meta['StatementNumber']
        BankAccount     = $meta['BankAccount']
        Source          = $meta['Source']
        FileName        = $meta['FileName']
        StatementId     = $meta['StatementId']
        AccountId       = $meta['AccountId']
        Currency        = $meta['Currency']
        FromDate        = & $parseDate $meta['FromDate']
        ToDate          = & $parseDate $meta['ToDate']
        OpeningBalance  = & $parseAmount $meta['OpeningBalance']
        ClosingBalance  = & $parseAmount $meta['ClosingBalance']
        ImportedDate    = & $parseDate $meta['ImportedDate']
        Transactions    = $transactions
        FilePath        = $FilePath
    }
}

function Read-LedgerBankStatementFile {
    <#
    .SYNOPSIS
    Reads and parses a single bank statement file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Bank statement file not found: $Path"
    }
    $content = @(Get-Content -Path $Path -Encoding UTF8)
    return ConvertTo-LedgerBankStatementObject -Content $content -FilePath $Path
}

function Save-LedgerBankStatementFile {
    <#
    .SYNOPSIS
    Serialises a bank statement object (metadata and transactions) to its file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Statement
    )

    $date = { param($v) if ($v) { ([datetime]$v).ToString('yyyy-MM-dd') } else { '' } }
    $amount = { param($v) if ($null -ne $v) { Format-LedgerInvoiceAmount -Value ([decimal]$v) } else { '' } }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('; PSLedger Bank Statement')
    $lines.Add("StatementNumber:`t$($Statement.StatementNumber)")
    $lines.Add("BankAccount:`t$($Statement.BankAccount)")
    $lines.Add("Source:`t$($Statement.Source)")
    $lines.Add("FileName:`t$(ConvertTo-LedgerBankField $Statement.FileName)")
    $lines.Add("StatementId:`t$(ConvertTo-LedgerBankField $Statement.StatementId)")
    $lines.Add("AccountId:`t$(ConvertTo-LedgerBankField $Statement.AccountId)")
    $lines.Add("Currency:`t$($Statement.Currency)")
    $lines.Add("FromDate:`t$(& $date $Statement.FromDate)")
    $lines.Add("ToDate:`t$(& $date $Statement.ToDate)")
    $lines.Add("OpeningBalance:`t$(& $amount $Statement.OpeningBalance)")
    $lines.Add("ClosingBalance:`t$(& $amount $Statement.ClosingBalance)")
    $lines.Add("ImportedDate:`t$(& $date $Statement.ImportedDate)")
    $lines.Add('Transactions:')

    foreach ($t in $Statement.Transactions) {
        $fields = @(
            $t.TransactionId
            $t.Date.ToString('yyyy-MM-dd')
            Format-LedgerInvoiceAmount -Value ([decimal]$t.Amount)
            ConvertTo-LedgerBankField $t.BankReference
            ConvertTo-LedgerBankField $t.Reference
            ConvertTo-LedgerBankField $t.Counterparty
            ConvertTo-LedgerBankField $t.Text
            $t.Status
            $t.MatchType
            ConvertTo-LedgerBankField $t.MatchRef
            $t.FiscalYear
            if ($null -ne $t.VerificationNumber) { $t.VerificationNumber } else { '' }
        )
        $lines.Add(($fields -join "`t"))
    }

    Set-LedgerFileContent -Path $Statement.FilePath -Value $lines.ToArray()
}

function Get-LedgerBankStatementData {
    <#
    .SYNOPSIS
    Reads all bank statements of a journal, ordered by statement number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    $dir = Get-LedgerBankDirectory -JournalPath $JournalPath
    if (-not (Test-Path $dir -PathType Container)) { return }
    $files = Get-ChildItem -Path $dir -Filter 'stmt*.txt' -File | Where-Object { $_.BaseName -match '^stmt\d+$' }
    $files | ForEach-Object { Read-LedgerBankStatementFile -Path $_.FullName } | Sort-Object StatementNumber
}

function Find-LedgerBankTransaction {
    <#
    .SYNOPSIS
    Locates a bank transaction by id and returns it together with the statement
    that holds it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$TransactionId
    )
    foreach ($s in @(Get-LedgerBankStatementData -JournalPath $JournalPath)) {
        foreach ($t in $s.Transactions) {
            if ($t.TransactionId -eq $TransactionId) {
                return [PSCustomObject]@{ Statement = $s; Transaction = $t }
            }
        }
    }
    throw "Bank transaction $TransactionId does not exist."
}

function Set-LedgerBankTransactionState {
    <#
    .SYNOPSIS
    Updates the status and match information of a transaction and saves its
    statement file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Statement,

        [Parameter(Mandatory)]
        [psobject]$Transaction,

        [Parameter(Mandatory)]
        [ValidateSet('Unmatched', 'Matched', 'Ignored')]
        [string]$Status,

        [string]$MatchType = '',

        [string]$MatchRef = '',

        [string]$FiscalYear = '',

        [Nullable[int]]$VerificationNumber
    )
    $Transaction.Status = $Status
    $Transaction.MatchType = $MatchType
    $Transaction.MatchRef = $MatchRef
    $Transaction.FiscalYear = $FiscalYear
    $Transaction.VerificationNumber = $VerificationNumber
    Save-LedgerBankStatementFile -Statement $Statement
}

function ConvertTo-LedgerBankTransactionOutput {
    <#
    .SYNOPSIS
    Returns the public view of a stored transaction.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Transaction
    )
    [PSCustomObject]@{
        TransactionId      = $Transaction.TransactionId
        StatementNumber    = $Transaction.StatementNumber
        BankAccount        = $Transaction.BankAccount
        Date               = $Transaction.Date
        Amount             = $Transaction.Amount
        Reference          = $Transaction.Reference
        Counterparty       = $Transaction.Counterparty
        Text               = $Transaction.Text
        BankReference      = $Transaction.BankReference
        Status             = $Transaction.Status
        MatchType          = $Transaction.MatchType
        MatchRef           = $Transaction.MatchRef
        FiscalYear         = $Transaction.FiscalYear
        VerificationNumber = $Transaction.VerificationNumber
    }
}

function Get-LedgerBankRulePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    return Join-Path (Get-LedgerBankDirectory -JournalPath $JournalPath) 'rules.txt'
}

function Read-LedgerBankRules {
    <#
    .SYNOPSIS
    Reads the bank posting rules (konteringsregler) in priority order.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    $path = Get-LedgerBankRulePath -JournalPath $JournalPath
    if (-not (Test-Path $path -PathType Leaf)) { return }
    $priority = 0
    foreach ($line in (Get-Content -Path $path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*;') { continue }
        $p = $line -split "`t"
        if ($p.Count -lt 2) { continue }
        $priority++
        [PSCustomObject]@{
            Priority    = $priority
            Pattern     = $p[0]
            Account     = $p[1]
            Description = if ($p.Count -ge 3) { $p[2] } else { '' }
            VatRate     = if ($p.Count -ge 4 -and $p[3]) { ConvertFrom-LedgerInvoiceAmount -Text $p[3] } else { [decimal]0 }
            VatAccount  = if ($p.Count -ge 5) { $p[4] } else { '' }
        }
    }
}

function Save-LedgerBankRules {
    <#
    .SYNOPSIS
    Writes the bank posting rules in the given order.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )
    Get-LedgerBankDirectory -JournalPath $JournalPath -Create | Out-Null
    $lines = @('; PSLedger bank rules: Pattern, Account, Description, VatRate, VatAccount')
    foreach ($r in $Rules) {
        $lines += @(
            ConvertTo-LedgerBankField $r.Pattern
            $r.Account
            ConvertTo-LedgerBankField $r.Description
            Format-LedgerInvoiceAmount -Value ([decimal]$r.VatRate)
            $r.VatAccount
        ) -join "`t"
    }
    Set-LedgerFileContent -Path (Get-LedgerBankRulePath -JournalPath $JournalPath) -Value $lines
}

function Test-LedgerBankPatternMatch {
    <#
    .SYNOPSIS
    Tests whether a rule pattern matches a transaction's counterparty, text or
    reference. Patterns with * or ? are wildcards; other patterns match when the
    field contains them. Matching is case-insensitive.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [psobject]$Transaction
    )
    $isWildcard = [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Pattern)
    foreach ($value in @($Transaction.Counterparty, $Transaction.Text, $Transaction.Reference)) {
        if ([string]::IsNullOrEmpty($value)) { continue }
        if ($isWildcard) {
            if ($value -like $Pattern) { return $true }
        }
        elseif ($value.IndexOf($Pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Get-LedgerBankEntryRows {
    <#
    .SYNOPSIS
    Builds balanced verification rows for a bank transaction posted against a
    counter account, optionally splitting out VAT.

    .DESCRIPTION
    The bank account receives the signed transaction amount. The counter account
    receives the opposite amount; with a VAT rate the gross amount is split into
    a net part on the counter account and a VAT part on the VAT account.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$BankAccount,

        [Parameter(Mandatory)]
        [decimal]$Amount,

        [Parameter(Mandatory)]
        [string]$Account,

        [decimal]$VatRate = 0,

        [string]$VatAccount
    )
    if ($VatRate -lt 0) { throw "VatRate must not be negative." }
    if ($VatRate -gt 0 -and -not $VatAccount) { throw "A VatAccount is required when VatRate is set." }

    $rows = @(@{ Account = $BankAccount; Amount = $Amount })
    if ($VatRate -gt 0) {
        $net = [Math]::Round($Amount / (1 + $VatRate), 2)
        $vat = $Amount - $net
        $rows += @{ Account = $Account; Amount = -$net }
        if ($vat -ne 0) { $rows += @{ Account = $VatAccount; Amount = -$vat } }
    }
    else {
        $rows += @{ Account = $Account; Amount = -$Amount }
    }
    return $rows
}
