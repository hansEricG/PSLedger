# BAS account to Skatteverket SRU field code (fältkod) mapping for the INK2
# income tax return (aktiebolag). Used when exporting INFO.SRU + BLANKETTER.SRU.
#
# The räkenskapsschema (INK2R) is derived directly from the trial balance:
#   * Balance sheet assets (BAS class 1)      -> reported with their natural
#     (debit-positive) sign.
#   * Balance sheet equity and liabilities    -> negated so a credit balance is
#     reported as a positive amount.
#   * Income statement accounts (class 3-8)   -> negated so revenue is positive
#     and costs are negative.
#
# The official mapping is maintained by BAS-kontogruppen together with
# Skatteverket (bas.se/kontoplaner/sru/). Årets resultat and total equity are
# computed from the full account range in Export-LedgerIncomeTaxReturn, so the
# bottom line always ties out even if an unusual account is not classified onto
# a specific line here.

function Get-SruAccountRules {
    <#
    .SYNOPSIS
    Returns the ordered BAS-account-range to SRU-code rules for INK2R.

    .DESCRIPTION
    Each rule has Min/Max (inclusive BAS account range), the target Sru field
    code and a Kind: 'Asset' (reported as-is), 'Debt' (equity/liabilities,
    negated) or 'Income' (income statement, negated). Rules are ordered so that
    more specific ranges are matched before the wider ranges that contain them.
    #>
    [CmdletBinding()]
    param()

    @(
        # --- Balance sheet: assets (class 1) ---------------------------------
        [PSCustomObject]@{ Min = 1010; Max = 1079; Sru = 7201; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1080; Max = 1089; Sru = 7202; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1090; Max = 1099; Sru = 7201; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1100; Max = 1119; Sru = 7214; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1120; Max = 1129; Sru = 7216; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1130; Max = 1179; Sru = 7214; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1180; Max = 1189; Sru = 7217; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1190; Max = 1199; Sru = 7214; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1200; Max = 1299; Sru = 7215; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1311; Max = 1316; Sru = 7230; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1320; Max = 1329; Sru = 7232; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1330; Max = 1338; Sru = 7231; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1340; Max = 1349; Sru = 7232; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1350; Max = 1359; Sru = 7233; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1360; Max = 1369; Sru = 7234; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1370; Max = 1379; Sru = 7235; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1380; Max = 1389; Sru = 7233; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1390; Max = 1399; Sru = 7235; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1400; Max = 1409; Sru = 7246; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1410; Max = 1419; Sru = 7241; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1440; Max = 1449; Sru = 7242; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1450; Max = 1469; Sru = 7243; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1470; Max = 1489; Sru = 7244; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1490; Max = 1499; Sru = 7245; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1500; Max = 1519; Sru = 7251; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1560; Max = 1579; Sru = 7252; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1620; Max = 1620; Sru = 7262; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1520; Max = 1559; Sru = 7261; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1580; Max = 1599; Sru = 7261; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1600; Max = 1699; Sru = 7261; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1700; Max = 1799; Sru = 7263; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1800; Max = 1859; Sru = 7271; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1860; Max = 1869; Sru = 7270; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1870; Max = 1899; Sru = 7271; Kind = 'Asset' }
        [PSCustomObject]@{ Min = 1900; Max = 1999; Sru = 7281; Kind = 'Asset' }

        # --- Balance sheet: equity and liabilities (class 2) -----------------
        [PSCustomObject]@{ Min = 2010; Max = 2089; Sru = 7301; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2090; Max = 2099; Sru = 7302; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2110; Max = 2129; Sru = 7321; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2130; Max = 2149; Sru = 7323; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2150; Max = 2159; Sru = 7322; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2160; Max = 2199; Sru = 7323; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2210; Max = 2219; Sru = 7331; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2220; Max = 2229; Sru = 7332; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2230; Max = 2299; Sru = 7333; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2320; Max = 2329; Sru = 7350; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2330; Max = 2339; Sru = 7351; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2340; Max = 2359; Sru = 7352; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2360; Max = 2379; Sru = 7353; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2380; Max = 2399; Sru = 7354; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2400; Max = 2409; Sru = 7362; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2410; Max = 2419; Sru = 7360; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2420; Max = 2439; Sru = 7361; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2440; Max = 2449; Sru = 7365; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2450; Max = 2459; Sru = 7363; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2460; Max = 2469; Sru = 7364; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2470; Max = 2479; Sru = 7367; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2480; Max = 2489; Sru = 7369; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2490; Max = 2490; Sru = 7366; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2491; Max = 2499; Sru = 7369; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2500; Max = 2599; Sru = 7368; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2600; Max = 2799; Sru = 7369; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2800; Max = 2899; Sru = 7369; Kind = 'Debt' }
        [PSCustomObject]@{ Min = 2900; Max = 2999; Sru = 7370; Kind = 'Debt' }

        # --- Income statement (class 3-8) ------------------------------------
        [PSCustomObject]@{ Min = 3000; Max = 3799; Sru = 7410; Kind = 'Income' }
        [PSCustomObject]@{ Min = 3800; Max = 3899; Sru = 7412; Kind = 'Income' }
        [PSCustomObject]@{ Min = 3900; Max = 3999; Sru = 7413; Kind = 'Income' }
        [PSCustomObject]@{ Min = 4000; Max = 4599; Sru = 7511; Kind = 'Income' }
        [PSCustomObject]@{ Min = 4600; Max = 4699; Sru = 7512; Kind = 'Income' }
        [PSCustomObject]@{ Min = 4700; Max = 4899; Sru = 7511; Kind = 'Income' }
        [PSCustomObject]@{ Min = 4900; Max = 4999; Sru = 7411; Kind = 'Income' }
        [PSCustomObject]@{ Min = 5000; Max = 6999; Sru = 7513; Kind = 'Income' }
        [PSCustomObject]@{ Min = 7000; Max = 7699; Sru = 7514; Kind = 'Income' }
        [PSCustomObject]@{ Min = 7700; Max = 7799; Sru = 7516; Kind = 'Income' }
        [PSCustomObject]@{ Min = 7800; Max = 7899; Sru = 7515; Kind = 'Income' }
        [PSCustomObject]@{ Min = 7900; Max = 7999; Sru = 7517; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8000; Max = 8099; Sru = 7414; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8100; Max = 8199; Sru = 7415; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8200; Max = 8269; Sru = 7423; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8270; Max = 8299; Sru = 7416; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8300; Max = 8399; Sru = 7417; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8400; Max = 8499; Sru = 7522; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8500; Max = 8599; Sru = 7521; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8810; Max = 8810; Sru = 7524; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8820; Max = 8820; Sru = 7419; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8830; Max = 8830; Sru = 7420; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8840; Max = 8840; Sru = 7525; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8850; Max = 8850; Sru = 7421; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8860; Max = 8899; Sru = 7422; Kind = 'Income' }
        [PSCustomObject]@{ Min = 8900; Max = 8989; Sru = 7528; Kind = 'Income' }
        # Account 8999 (Årets resultat) is a result-appropriation transfer to
        # equity, not a P&L line, and is intentionally left unmapped.
    )
}

function Resolve-SruAccountRule {
    <#
    .SYNOPSIS
    Returns the first SRU rule whose range contains the given BAS account, or
    $null when the account is not classified.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$Account,

        [Parameter(Mandatory)]
        [object[]]$Rules
    )

    foreach ($rule in $Rules) {
        if ($Account -ge $rule.Min -and $Account -le $rule.Max) {
            return $rule
        }
    }
    return $null
}

function ConvertTo-SruOrgNr {
    <#
    .SYNOPSIS
    Normalises an organisation number to the 12-digit form Skatteverket's SRU
    files require (SSÅÅMMDDNNNK, no hyphen). A 10-digit company number is
    prefixed with the century marker '16'.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$OrgNumber
    )

    $digits = ($OrgNumber -replace '\D', '')
    switch ($digits.Length) {
        12 { return $digits }
        10 { return "16$digits" }
        default {
            throw "Cannot format organisation number '$OrgNumber' for SRU: expected 10 or 12 digits, got $($digits.Length)."
        }
    }
}

function Get-SruPeriodSuffix {
    <#
    .SYNOPSIS
    Returns the SRU blankett period suffix (P1, P2 or P4) for the month a fiscal
    year ends in. The income year in the blankett type string is the year the
    fiscal year ends.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$EndMonth
    )

    if ($EndMonth -ge 1 -and $EndMonth -le 4) { return 'P1' }
    if ($EndMonth -ge 5 -and $EndMonth -le 8) { return 'P2' }
    return 'P4'
}
