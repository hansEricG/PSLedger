# Archive packages (arkivering): report blocks and checksum helpers used by
# Export-LedgerArchive and Test-LedgerArchive. The reports use the shared block
# model (see AnnualReportRender.ps1) so each one is written as both text and PDF.
# Table text columns are kept short so a row fits an A4 PDF page in 9 pt Courier.

$script:LedgerArchiveFormatVersion = 1
$script:LedgerArchiveChecksumFile = 'checksums.txt'
$script:LedgerArchiveManifestFile = 'manifest.txt'

function Format-LedgerArchiveAmount {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [decimal]$Amount,

        [switch]$BlankZero
    )
    if ($BlankZero -and $Amount -eq 0) { return '' }
    $Amount.ToString('#,##0.00', [cultureinfo]::InvariantCulture).Replace(',', ' ').Replace('.', ',')
}

function Get-LedgerArchiveShortText {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text,

        [Parameter(Mandatory)]
        [int]$MaxLength
    )
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $MaxLength) { return $Text }
    $Text.Substring(0, $MaxLength - 2) + '..'
}

function New-LedgerArchiveReportHeader {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param (
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] $Context
    )
    $company = if ($Context.OrgNumber) { "$($Context.CompanyName) ($($Context.OrgNumber))" } else { $Context.CompanyName }
    $blocks = @(
        @{ Type = 'Title'; Text = $Title }
        @{ Type = 'Paragraph'; Text = $company }
        @{ Type = 'Paragraph'; Text = "Räkenskapsår $($Context.StartDate) - $($Context.EndDate)" }
    )
    if ($Context.Preliminary) {
        $blocks += @{ Type = 'Paragraph'; Text = 'PRELIMINÄR: räkenskapsåret var inte stängt när arkivet skapades.' }
    }
    $blocks += @{ Type = 'Paragraph'; Text = "Framtagen $($Context.Created) med PSLedger $($Context.Version)." }
    $blocks
}

function Get-LedgerArchiveRowText {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] $Row,
        [Parameter(Mandatory)] [hashtable]$AccountNames
    )
    $text = [string]$AccountNames[[string]$Row.Account]
    if ($Row.Objects -and $Row.Objects.Count -gt 0) {
        $tags = @($Row.Objects.Keys | Sort-Object | ForEach-Object { "$($_):$($Row.Objects[$_])" }) -join ' '
        $text = "$text [$tags]"
    }
    if ($Row.Comment) { $text = "$text - $($Row.Comment)" }
    $text.Trim()
}

function Build-LedgerArchiveJournalBlocks {
    <#
    .SYNOPSIS
    Grundbok: every verification in date order with its rows.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Entries,
        [Parameter(Mandatory)] [hashtable]$AccountNames,
        [Parameter(Mandatory)] $Context
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    $styles = [System.Collections.Generic.List[string]]::new()
    $totalDebit = [decimal]0
    $totalCredit = [decimal]0
    $sorted = $Entries | Sort-Object @{ Expression = { [datetime]$_.Date } }, @{ Expression = { [int]$_.VerificationNumber } }
    foreach ($e in $sorted) {
        $rows.Add(@([string]$e.VerificationNumber, ([datetime]$e.Date).ToString('yyyy-MM-dd'), '', (Get-LedgerArchiveShortText $e.Description 40), '', ''))
        $styles.Add('Section')
        foreach ($r in $e.Rows) {
            $amount = [decimal]$r.Amount
            if ($amount -gt 0) { $totalDebit += $amount } else { $totalCredit -= $amount }
            $rows.Add(@('', '', [string]$r.Account,
                    (Get-LedgerArchiveShortText (Get-LedgerArchiveRowText -Row $r -AccountNames $AccountNames) 40),
                    (Format-LedgerArchiveAmount ([Math]::Max($amount, 0)) -BlankZero),
                    (Format-LedgerArchiveAmount ([Math]::Max(-$amount, 0)) -BlankZero)))
            $styles.Add('Normal')
        }
    }
    $rows.Add(@('', '', '', "Summa ($(@($Entries).Count) verifikationer)", (Format-LedgerArchiveAmount $totalDebit), (Format-LedgerArchiveAmount $totalCredit)))
    $styles.Add('Sum')

    @(New-LedgerArchiveReportHeader -Title 'Grundbok (verifikationslista)' -Context $Context) + @(
        @{ Type = 'Table'; Header = @('Ver', 'Datum', 'Konto', 'Text', 'Debet', 'Kredit')
            Align = @('right', 'left', 'left', 'left', 'right', 'right')
            Rows = $rows.ToArray(); RowStyles = $styles.ToArray()
        }
    )
}

function Build-LedgerArchiveGeneralLedgerBlocks {
    <#
    .SYNOPSIS
    Huvudbok: per account, opening balance, every transaction and closing balance.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Entries,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Balances,
        [Parameter(Mandatory)] $Context
    )
    $byAccount = @{}
    $sorted = $Entries | Sort-Object @{ Expression = { [datetime]$_.Date } }, @{ Expression = { [int]$_.VerificationNumber } }
    foreach ($e in $sorted) {
        foreach ($r in $e.Rows) {
            $key = [string]$r.Account
            if (-not $byAccount.ContainsKey($key)) { $byAccount[$key] = [System.Collections.Generic.List[object]]::new() }
            $byAccount[$key].Add([pscustomobject]@{ Entry = $e; Amount = [decimal]$r.Amount })
        }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $styles = [System.Collections.Generic.List[string]]::new()
    foreach ($b in ($Balances | Sort-Object { [string]$_.AccountNumber })) {
        $account = [string]$b.AccountNumber
        $balance = [decimal]$b.OpeningBalance
        $rows.Add(@($account, '', (Get-LedgerArchiveShortText $b.AccountName 30), '', '', ''))
        $styles.Add('Section')
        $rows.Add(@('', '', 'Ingående saldo', '', '', (Format-LedgerArchiveAmount $balance)))
        $styles.Add('Normal')
        $debit = [decimal]0
        $credit = [decimal]0
        if ($byAccount.ContainsKey($account)) {
            foreach ($t in $byAccount[$account]) {
                $balance += $t.Amount
                if ($t.Amount -gt 0) { $debit += $t.Amount } else { $credit -= $t.Amount }
                $rows.Add(@([string]$t.Entry.VerificationNumber, ([datetime]$t.Entry.Date).ToString('yyyy-MM-dd'),
                        (Get-LedgerArchiveShortText $t.Entry.Description 30),
                        (Format-LedgerArchiveAmount ([Math]::Max($t.Amount, 0)) -BlankZero),
                        (Format-LedgerArchiveAmount ([Math]::Max(-$t.Amount, 0)) -BlankZero),
                        (Format-LedgerArchiveAmount $balance)))
                $styles.Add('Normal')
            }
        }
        $rows.Add(@('', '', 'Utgående saldo', (Format-LedgerArchiveAmount $debit), (Format-LedgerArchiveAmount $credit), (Format-LedgerArchiveAmount $balance)))
        $styles.Add('Sum')
    }

    @(New-LedgerArchiveReportHeader -Title 'Huvudbok' -Context $Context) + @(
        @{ Type = 'Table'; Header = @('Ver', 'Datum', 'Text', 'Debet', 'Kredit', 'Saldo')
            Align = @('right', 'left', 'left', 'right', 'right', 'right')
            Rows = $rows.ToArray(); RowStyles = $styles.ToArray()
        }
    )
}

function Build-LedgerArchiveTrialBalanceBlocks {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Balances,
        [Parameter(Mandatory)] $Context
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($b in ($Balances | Sort-Object { [string]$_.AccountNumber })) {
        $rows.Add(@([string]$b.AccountNumber, (Get-LedgerArchiveShortText $b.AccountName 24),
                (Format-LedgerArchiveAmount ([decimal]$b.OpeningBalance)),
                (Format-LedgerArchiveAmount ([decimal]$b.Debit)),
                (Format-LedgerArchiveAmount ([decimal]$b.Credit)),
                (Format-LedgerArchiveAmount ([decimal]$b.Balance))))
    }
    @(New-LedgerArchiveReportHeader -Title 'Saldobalans' -Context $Context) + @(
        @{ Type = 'Table'; Header = @('Konto', 'Namn', 'Ingående', 'Debet', 'Kredit', 'Utgående')
            Align = @('left', 'left', 'right', 'right', 'right', 'right'); Rows = $rows.ToArray()
        }
    )
}

function Build-LedgerArchiveStatementBlocks {
    <#
    .SYNOPSIS
    Resultaträkning or balansräkning from Get-LedgerIncomeStatement/BalanceSheet lines.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param (
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Lines,
        [Parameter(Mandatory)] $Context,
        [string[]]$SumGroups = @(),
        [string[]]$NegateSections = @(),
        [string]$Note
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    $styles = [System.Collections.Generic.List[string]]::new()
    foreach ($l in $Lines) {
        $amount = [decimal]$l.Amount
        if ($l.Section -in $NegateSections) { $amount = -$amount }
        $rows.Add(@([string]$l.Label, (Format-LedgerArchiveAmount $amount)))
        $styles.Add($(if ($l.Group -in $SumGroups) { 'Sum' } else { 'Normal' }))
    }
    $blocks = @(New-LedgerArchiveReportHeader -Title $Title -Context $Context)
    if ($Note) { $blocks += @{ Type = 'Paragraph'; Text = $Note } }
    $blocks + @(
        @{ Type = 'Table'; Header = @('Post', 'Belopp'); Align = @('left', 'right')
            Rows = $rows.ToArray(); RowStyles = $styles.ToArray()
        }
    )
}

function Build-LedgerArchiveVatBlocks {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Lines,
        [Parameter(Mandatory)] $Context
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($l in $Lines) {
        $rows.Add(@([string]$l.Box, (Get-LedgerArchiveShortText $l.Name 50), (Format-LedgerArchiveAmount ([decimal]$l.Amount))))
    }
    @(New-LedgerArchiveReportHeader -Title 'Momsrapport' -Context $Context) + @(
        @{ Type = 'Paragraph'; Text = 'Hela räkenskapsåret, per ruta i momsdeklarationen.' }
        @{ Type = 'Table'; Header = @('Ruta', 'Benämning', 'Belopp'); Align = @('right', 'left', 'right'); Rows = $rows.ToArray() }
    )
}

function Write-LedgerArchiveReport {
    <#
    .SYNOPSIS
    Writes report blocks as <BasePath>.txt and <BasePath>.pdf.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [object[]]$Block,
        [Parameter(Mandatory)] [string]$BasePath
    )
    [System.IO.File]::WriteAllText("$BasePath.txt", (ConvertTo-LedgerReportText -Block $Block), [System.Text.UTF8Encoding]::new($false))
    ConvertTo-LedgerReportPdf -Block $Block -Path "$BasePath.pdf"
}

function Get-LedgerArchiveFileHash {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string]$Path
    )
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
    }
}

function Get-LedgerArchiveRelativeFile {
    <#
    .SYNOPSIS
    Files under a package root as relative paths with forward slashes, sorted ordinally.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)] [string]$Root
    )
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $files = foreach ($f in Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force) {
        $f.FullName.Substring($rootFull.Length + 1).Replace('\', '/')
    }
    [string[]]$sorted = @($files)
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    , $sorted
}

function Read-LedgerArchiveManifest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string]$Path
    )
    $manifest = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if (-not $line -or $line.StartsWith(';')) { continue }
        $parts = $line.Split("`t", 2)
        if ($parts.Count -eq 2) { $manifest[$parts[0]] = $parts[1] }
    }
    $manifest
}
