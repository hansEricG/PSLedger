# BAS account to Swedish VAT declaration box mapping.
#
# Maps BAS accounts to the boxes (rutor) of Skatteverket's VAT return
# (skattedeklaration för moms) and the boxes to the eSKD 6.0 XML tags. A journal
# can override the default mapping with a vat.txt file (see docs/File-format.md).

function Get-VatBoxDefinition {
    <#
    .SYNOPSIS
    Returns the VAT declaration boxes in Skatteverket's eSKD order.

    .DESCRIPTION
    Kind decides how account totals become a box amount: Sales and OutputVat
    boxes hold credit balances (reported negated), PurchaseBase and InputVat
    boxes hold debit balances. Box 49 is derived from the others.
    #>
    [CmdletBinding()]
    param()

    $boxes = @(
        ,@(5, 'ForsMomsEjAnnan', 'Sales', 'Momspliktig försäljning')
        ,@(6, 'UttagMoms', 'Sales', 'Momspliktiga uttag')
        ,@(7, 'UlagMargbesk', 'Sales', 'Beskattningsunderlag vid vinstmarginalbeskattning')
        ,@(8, 'HyrinkomstFriv', 'Sales', 'Hyresinkomster vid frivillig skattskyldighet')
        ,@(20, 'InkopVaruAnnatEg', 'PurchaseBase', 'Inköp av varor från ett annat EU-land')
        ,@(21, 'InkopTjanstAnnatEg', 'PurchaseBase', 'Inköp av tjänster från ett annat EU-land')
        ,@(22, 'InkopTjanstUtomEg', 'PurchaseBase', 'Inköp av tjänster från ett land utanför EU')
        ,@(23, 'InkopVaruSverige', 'PurchaseBase', 'Inköp av varor i Sverige (omvänd skattskyldighet)')
        ,@(24, 'InkopTjanstSverige', 'PurchaseBase', 'Övriga inköp av tjänster (omvänd skattskyldighet)')
        ,@(50, 'MomsUlagImport', 'PurchaseBase', 'Beskattningsunderlag vid import')
        ,@(35, 'ForsVaruAnnatEg', 'Sales', 'Försäljning av varor till ett annat EU-land')
        ,@(36, 'ForsVaruUtomEg', 'Sales', 'Försäljning av varor utanför EU')
        ,@(37, 'InkopVaruMellan3p', 'PurchaseBase', 'Mellanmans inköp av varor vid trepartshandel')
        ,@(38, 'ForsVaruMellan3p', 'Sales', 'Mellanmans försäljning av varor vid trepartshandel')
        ,@(39, 'ForsTjSkskAnnatEg', 'Sales', 'Försäljning av tjänster till ett annat EU-land')
        ,@(40, 'ForsTjOvrUtomEg', 'Sales', 'Övrig försäljning av tjänster omsatta utomlands')
        ,@(41, 'ForsKopareSkskSverige', 'Sales', 'Försäljning när köparen är skattskyldig i Sverige')
        ,@(42, 'ForsOvrigt', 'Sales', 'Övrig försäljning m.m.')
        ,@(10, 'MomsUtgHog', 'OutputVat', 'Utgående moms 25 %')
        ,@(11, 'MomsUtgMedel', 'OutputVat', 'Utgående moms 12 %')
        ,@(12, 'MomsUtgLag', 'OutputVat', 'Utgående moms 6 %')
        ,@(30, 'MomsInkopUtgHog', 'OutputVat', 'Utgående moms 25 % på inköp')
        ,@(31, 'MomsInkopUtgMedel', 'OutputVat', 'Utgående moms 12 % på inköp')
        ,@(32, 'MomsInkopUtgLag', 'OutputVat', 'Utgående moms 6 % på inköp')
        ,@(60, 'MomsImportUtgHog', 'OutputVat', 'Utgående moms 25 % vid import')
        ,@(61, 'MomsImportUtgMedel', 'OutputVat', 'Utgående moms 12 % vid import')
        ,@(62, 'MomsImportUtgLag', 'OutputVat', 'Utgående moms 6 % vid import')
        ,@(48, 'MomsIngAvdr', 'InputVat', 'Ingående moms att dra av')
        ,@(49, 'MomsBetala', 'Result', 'Moms att betala eller få tillbaka')
    )
    foreach ($b in $boxes) {
        [PSCustomObject]@{ Box = $b[0]; Tag = $b[1]; Kind = $b[2]; Name = $b[3] }
    }
}

function Get-VatDefaultRule {
    <#
    .SYNOPSIS
    Returns the default BAS account ranges per box, most specific first.

    .DESCRIPTION
    The last rule, 3000-3799 to box 05, is the catch-all for taxable sales and
    is marked Implicit: accounts that only match it are reported in box 05.
    #>
    [CmdletBinding()]
    param()

    $rules = @(
        ,@(3004, 3004, 42)   # Försäljning inom Sverige, momsfri
        ,@(3105, 3105, 36)   # Försäljning varor till land utanför EU
        ,@(3107, 3107, 38)   # Försäljning varor, mellanman vid trepartshandel
        ,@(3108, 3108, 35)   # Försäljning varor till annat EU-land, momsfri
        ,@(3211, 3212, 7)    # Försäljning positiv/negativ VMB
        ,@(3231, 3233, 41)   # Försäljning inom byggsektorn m.m., omvänd skattskyldighet
        ,@(3305, 3305, 40)   # Försäljning tjänster till land utanför EU
        ,@(3308, 3308, 39)   # Försäljning tjänster till annat EU-land
        ,@(3401, 3403, 6)    # Egna uttag, momspliktiga
        ,@(3404, 3404, 42)   # Egna uttag, momsfria
        ,@(3913, 3914, 8)    # Frivilligt momspliktiga hyresintäkter
        ,@(4415, 4417, 23)   # Inköpta varor i Sverige, omvänd skattskyldighet
        ,@(4425, 4427, 24)   # Inköpta tjänster i Sverige, omvänd skattskyldighet
        ,@(4512, 4512, 37)   # Inköp av varor, mellanman vid trepartshandel
        ,@(4515, 4517, 20)   # Inköp av varor från annat EU-land
        ,@(4531, 4533, 22)   # Inköp av tjänster från land utanför EU
        ,@(4535, 4537, 21)   # Inköp av tjänster från annat EU-land
        ,@(4545, 4547, 50)   # Import av varor, beskattningsunderlag
        ,@(2610, 2613, 10)   # Utgående moms 25 %
        ,@(2616, 2616, 10)   # Utgående moms VMB 25 %
        ,@(2614, 2614, 30)   # Utgående moms omvänd skattskyldighet 25 %
        ,@(2617, 2617, 30)
        ,@(2615, 2615, 60)   # Utgående moms import av varor 25 %
        ,@(2620, 2623, 11)
        ,@(2626, 2626, 11)
        ,@(2624, 2624, 31)
        ,@(2627, 2627, 31)
        ,@(2625, 2625, 61)
        ,@(2630, 2633, 12)
        ,@(2636, 2636, 12)
        ,@(2634, 2634, 32)
        ,@(2637, 2637, 32)
        ,@(2635, 2635, 62)
        ,@(2640, 2647, 48)   # Ingående moms (2648 vilande moms is excluded)
        ,@(2649, 2649, 48)
    )
    foreach ($r in $rules) {
        [PSCustomObject]@{ From = [long]$r[0]; To = [long]$r[1]; Box = [int]$r[2]; Source = 'Default'; Implicit = $false }
    }
    [PSCustomObject]@{ From = 3000L; To = 3799L; Box = 5; Source = 'Default'; Implicit = $true }
}

function Get-LedgerVatMappingPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    Join-Path $JournalPath 'vat.txt'
}

function Read-LedgerVatMapping {
    <#
    .SYNOPSIS
    Reads the journal's vat.txt override rules in file order.

    .DESCRIPTION
    Each record is an account or an account range (3000-3099) and a box number,
    or '-' for no box. Throws on a record it cannot read, since a silently
    ignored rule would put amounts in the wrong box of a tax return.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    $path = Get-LedgerVatMappingPath -JournalPath $JournalPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }

    $valid = @(Get-VatBoxDefinition | Where-Object Kind -ne 'Result' | ForEach-Object Box)
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*;') { continue }
        $p = $line -split "`t"
        if ($p.Count -lt 2 -or $p[0].Trim() -notmatch '^(\d+)(?:-(\d+))?$') {
            throw "vat.txt line ${lineNumber}: expected '<account or range><TAB><box>', got '$line'."
        }
        $from = [long]$Matches[1]
        $to = if ($Matches[2]) { [long]$Matches[2] } else { $from }
        if ($to -lt $from) {
            throw "vat.txt line ${lineNumber}: range '$($p[0].Trim())' ends before it starts."
        }
        $boxText = $p[1].Trim()
        $box = $null
        if ($boxText -ne '-') {
            if ($boxText -notmatch '^\d{1,2}$' -or [int]$boxText -notin $valid) {
                throw "vat.txt line ${lineNumber}: '$boxText' is not a VAT declaration box. Use a box number such as 05 or 39, or '-' for no box."
            }
            $box = [int]$boxText
        }
        [PSCustomObject]@{ From = $from; To = $to; Box = $box; Source = 'vat.txt'; Implicit = $false }
    }
}

function Save-LedgerVatMapping {
    <#
    .SYNOPSIS
    Writes vat.txt override rules in the given order.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )
    $lines = @('; PSLedger VAT mapping: Account or range, Box')
    foreach ($r in $Rules) {
        $account = if ($r.From -eq $r.To) { "$($r.From)" } else { "$($r.From)-$($r.To)" }
        $box = if ($null -eq $r.Box) { '-' } else { '{0:D2}' -f [int]$r.Box }
        $lines += "$account`t$box"
    }
    Set-LedgerFileContent -Path (Get-LedgerVatMappingPath -JournalPath $JournalPath) -Value $lines
}

function Get-VatBoxMapping {
    <#
    .SYNOPSIS
    Returns the effective mapping rules: vat.txt rules first, then the defaults.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath
    )
    if ($JournalPath) { Read-LedgerVatMapping -JournalPath $JournalPath }
    Get-VatDefaultRule
}

function Resolve-VatBoxRule {
    <#
    .SYNOPSIS
    Returns the first rule that matches an account, or $null.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Account,

        [Parameter(Mandatory)]
        [object[]]$Rules
    )
    if ($Account -notmatch '^\d+$') { return $null }
    $number = [long]$Account
    foreach ($rule in $Rules) {
        if ($number -ge $rule.From -and $number -le $rule.To) { return $rule }
    }
    $null
}

function Get-VatEskdTagMap {
    <#
    .SYNOPSIS
    Returns the eSKD 6.0 XML tag of each box in Skatteverket's order.
    #>
    [CmdletBinding()]
    param()

    Get-VatBoxDefinition | Select-Object Box, Tag
}
