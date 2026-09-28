# BAS account to Skatteverket SRU field code (fältkod) mapping for the INK2
# income tax return (aktiebolag). Used when exporting INFO.SRU + BLANKETTER.SRU.
#
# Sources:
#   * Account ranges: BAS kopplingstabell "INK2_P1_intervall" (bas.se/kontoplaner/sru/).
#   * Field codes, rows, printed signs and data types: Skatteverket's
#     fältnamnstabeller INK2_, INK2R_ and INK2S_SKV2002-33-01-24-04 (package
#     "Ändringar från och med 2025P4", Teknisk information om filöverföring).
#
# Amounts are written as they appear on the form: the row's printed sign (+/-)
# carries the direction, so costs, deductions and a loss are positive numbers.
# A negative amount is only written to go against the printed sign (e.g. a tax
# income on 3.25). Rows split into a (+) and a (-) field get the field that
# matches the net amount. Balance sheet rows have no printed sign.

function Get-SruAccountRules {
    <#
    .SYNOPSIS
    Returns the ordered BAS-account-range to SRU-code rules for INK2R.

    .DESCRIPTION
    Each rule has Min/Max (inclusive BAS account range) and a Kind:

      Asset   balance sheet asset, reported debit-positive in Sru
      Debt    equity or liability, reported credit-positive in Sru
      Income  income statement line; the net of all accounts matched by the
              rule (income positive) goes to Sru when positive and to MinusSru
              (as a positive amount) when negative. A rule with only Sru or
              only MinusSru reports the net against that field's printed sign.

    Rules are ordered so that more specific ranges are matched before the wider
    ranges that contain them. An optional AltSru on Asset/Debt rules is used,
    per account, when the balance has the opposite sign (an asset in credit or
    a liability in debit), so a debit balance on 2510 Skatteskulder is
    reported as a receivable rather than a negative liability.
    #>
    [CmdletBinding()]
    param()

    $r = {
        param($Min, $Max, $Kind, $Sru, $MinusSru = $null, $AltSru = $null)
        [PSCustomObject]@{ Min = $Min; Max = $Max; Kind = $Kind; Sru = $Sru; MinusSru = $MinusSru; AltSru = $AltSru }
    }

    @(
        # --- Balance sheet: assets (class 1) ---------------------------------
        & $r 1088 1088 Asset 7202
        & $r 1000 1099 Asset 7201
        & $r 1120 1129 Asset 7216
        & $r 1180 1189 Asset 7217
        & $r 1100 1199 Asset 7214
        & $r 1280 1289 Asset 7217
        & $r 1200 1299 Asset 7215
        & $r 1310 1319 Asset 7230
        & $r 1320 1329 Asset 7232
        & $r 1336 1337 Asset 7233
        & $r 1330 1339 Asset 7231
        & $r 1346 1347 Asset 7235
        & $r 1340 1349 Asset 7232
        & $r 1350 1359 Asset 7233
        & $r 1360 1369 Asset 7234
        & $r 1370 1399 Asset 7235
        & $r 1400 1429 Asset 7241
        & $r 1440 1449 Asset 7242
        & $r 1450 1469 Asset 7243
        & $r 1470 1479 Asset 7245
        & $r 1480 1489 Asset 7246
        & $r 1490 1499 Asset 7244
        & $r 1573 1573 Asset 7261
        & $r 1560 1579 Asset 7252
        & $r 1500 1599 Asset 7251
        & $r 1620 1629 Asset 7262
        # Skattekontot (163x): a credit balance is a skatteskuld (2.49).
        & $r 1630 1639 Asset 7261 -AltSru 7368
        & $r 1673 1673 Asset 7261
        & $r 1660 1679 Asset 7252
        & $r 1600 1699 Asset 7261
        & $r 1700 1799 Asset 7263
        & $r 1860 1869 Asset 7270
        & $r 1800 1899 Asset 7271
        & $r 1900 1999 Asset 7281

        # --- Balance sheet: equity and liabilities (class 2) -----------------
        & $r 2000 2089 Debt 7301
        & $r 2090 2099 Debt 7302
        & $r 2100 2139 Debt 7321
        & $r 2150 2159 Debt 7322
        & $r 2140 2199 Debt 7323
        & $r 2210 2219 Debt 7331
        & $r 2230 2239 Debt 7332
        & $r 2200 2299 Debt 7333
        & $r 2300 2329 Debt 7350
        & $r 2330 2339 Debt 7351
        & $r 2340 2359 Debt 7352
        & $r 2373 2373 Debt 7354
        & $r 2360 2379 Debt 7353
        & $r 2380 2399 Debt 7354
        & $r 2410 2419 Debt 7361
        & $r 2420 2429 Debt 7362
        & $r 2430 2439 Debt 7363
        & $r 2440 2449 Debt 7365
        & $r 2450 2459 Debt 7364
        & $r 2473 2473 Debt 7369
        & $r 2460 2479 Debt 7367
        & $r 2480 2489 Debt 7360
        & $r 2492 2492 Debt 7366
        & $r 2400 2499 Debt 7369
        # Skatteskulder (25xx): a debit balance is a receivable (2.21).
        & $r 2500 2599 Debt 7368 -AltSru 7261
        & $r 2874 2879 Debt 7367
        & $r 2600 2899 Debt 7369
        & $r 2900 2999 Debt 7370

        # --- Income statement (class 3-8) ------------------------------------
        & $r 3000 3799 Income 7410
        & $r 3800 3899 Income 7412
        & $r 3900 3999 Income 7413
        & $r 4910 4929 Income $null 7511
        & $r 4960 4969 Income $null 7512
        & $r 4980 4989 Income $null 7512
        & $r 4900 4999 Income 7411 7510
        # BAS allows 40xx-47xx on either 3.5 or 3.6; PSLedger reports them on 3.5.
        & $r 4000 4899 Income $null 7511
        & $r 5000 6999 Income $null 7513
        & $r 7000 7699 Income $null 7514
        & $r 7740 7749 Income $null 7516
        & $r 7790 7799 Income $null 7516
        & $r 7700 7899 Income $null 7515
        & $r 7900 7999 Income $null 7517
        & $r 8070 8089 Income $null 7521
        & $r 8000 8099 Income 7414 7518
        & $r 8113 8113 Income 7423 7530
        & $r 8118 8118 Income 7423 7530
        & $r 8123 8123 Income 7423 7530
        & $r 8133 8133 Income 7423 7530
        & $r 8170 8189 Income $null 7521
        & $r 8100 8199 Income 7415 7519
        & $r 8270 8289 Income $null 7521
        & $r 8200 8299 Income 7416 7520
        & $r 8370 8389 Income $null 7521
        & $r 8300 8399 Income 7417
        & $r 8400 8499 Income $null 7522
        & $r 8810 8810 Income 7420 7525
        & $r 8811 8811 Income $null 7525
        & $r 8819 8819 Income 7420
        & $r 8820 8829 Income 7419
        & $r 8830 8839 Income $null 7524
        & $r 8840 8849 Income $null 7527
        & $r 8850 8859 Income 7421 7526
        & $r 8860 8899 Income 7422 7527
        & $r 8900 8989 Income $null 7528
        # 899x (Årets resultat) is the result-appropriation transfer to equity,
        # not a P&L line, and is intentionally left unmapped.
    )
}

function Get-SruFieldDefinitions {
    <#
    .SYNOPSIS
    Returns the INK2, INK2R and INK2S field definitions: form, row (ruta),
    SRU field code, printed sign and description.

    .DESCRIPTION
    Sign is '+' or '-' for rows that add to or subtract from the result (the
    form's printed sign) and '*' for information-only rows. NonNegative marks
    fields of Skatteverket's type Numeriskt_B, which do not accept a negative
    amount. Rows that the form splits into a (+) and a (-) field carry the
    suffix in Box (e.g. '3.15+'). Transcribed from
    INK2*_SKV2002-33-01-24-04 (valid from 2025P4).
    #>
    [CmdletBinding()]
    param()

    $data = @'
INK2|1.1|7104|*|B|Överskott av näringsverksamhet
INK2|1.2|7114|*|B|Underskott av näringsverksamhet
INK2R|2.1|7201|*|A|Koncessioner, patent, licenser, varumärken, hyresrätter, goodwill och liknande rättigheter
INK2R|2.2|7202|*|A|Förskott avseende immateriella anläggningstillgångar
INK2R|2.3|7214|*|A|Byggnader och mark
INK2R|2.4|7215|*|A|Maskiner, inventarier och övriga materiella anläggningstillgångar
INK2R|2.5|7216|*|A|Förbättringsutgifter på annans fastighet
INK2R|2.6|7217|*|A|Pågående nyanläggningar och förskott avseende materiella anläggningstillgångar
INK2R|2.7|7230|*|A|Andelar i koncernföretag
INK2R|2.8|7231|*|A|Andelar i intresseföretag och gemensamt styrda företag
INK2R|2.9|7233|*|A|Ägarintressen i övriga företag och andra långfristiga värdepappersinnehav
INK2R|2.10|7232|*|A|Fordringar hos koncern-, intresse- och gemensamt styrda företag
INK2R|2.11|7234|*|A|Lån till delägare eller närstående
INK2R|2.12|7235|*|A|Fordringar hos övriga företag som det finns ett ägarintresse i och andra långfristiga fordringar
INK2R|2.13|7241|*|A|Råvaror och förnödenheter
INK2R|2.14|7242|*|A|Varor under tillverkning
INK2R|2.15|7243|*|A|Färdiga varor och handelsvaror
INK2R|2.16|7244|*|A|Övriga lagertillgångar
INK2R|2.17|7245|*|A|Pågående arbeten för annans räkning
INK2R|2.18|7246|*|A|Förskott till leverantörer
INK2R|2.19|7251|*|A|Kundfordringar
INK2R|2.20|7252|*|A|Fordringar hos koncern-, intresse- och gemensamt styrda företag
INK2R|2.21|7261|*|A|Fordringar hos övriga företag som det finns ett ägarintresse i och övriga fordringar
INK2R|2.22|7262|*|A|Upparbetad men ej fakturerad intäkt
INK2R|2.23|7263|*|A|Förutbetalda kostnader och upplupna intäkter
INK2R|2.24|7270|*|A|Andelar i koncernföretag (kortfristiga placeringar)
INK2R|2.25|7271|*|A|Övriga kortfristiga placeringar
INK2R|2.26|7281|*|A|Kassa, bank och redovisningsmedel
INK2R|2.27|7301|*|A|Bundet eget kapital
INK2R|2.28|7302|*|A|Fritt eget kapital
INK2R|2.29|7321|*|A|Periodiseringsfonder
INK2R|2.30|7322|*|A|Ackumulerade överavskrivningar
INK2R|2.31|7323|*|A|Övriga obeskattade reserver
INK2R|2.32|7331|*|A|Avsättningar för pensioner enligt tryggandelagen
INK2R|2.33|7332|*|A|Övriga avsättningar för pensioner och liknande förpliktelser
INK2R|2.34|7333|*|A|Övriga avsättningar
INK2R|2.35|7350|*|A|Obligationslån
INK2R|2.36|7351|*|A|Checkräkningskredit (långfristig)
INK2R|2.37|7352|*|A|Övriga skulder till kreditinstitut (långfristiga)
INK2R|2.38|7353|*|A|Skulder till koncern-, intresse- och gemensamt styrda företag (långfristiga)
INK2R|2.39|7354|*|A|Skulder till övriga företag som det finns ett ägarintresse i och övriga skulder (långfristiga)
INK2R|2.40|7360|*|A|Checkräkningskredit (kortfristig)
INK2R|2.41|7361|*|A|Övriga skulder till kreditinstitut (kortfristiga)
INK2R|2.42|7362|*|A|Förskott från kunder
INK2R|2.43|7363|*|A|Pågående arbeten för annans räkning (skuld)
INK2R|2.44|7364|*|A|Fakturerad men ej upparbetad intäkt
INK2R|2.45|7365|*|A|Leverantörsskulder
INK2R|2.46|7366|*|A|Växelskulder
INK2R|2.47|7367|*|A|Skulder till koncern-, intresse- och gemensamt styrda företag (kortfristiga)
INK2R|2.48|7369|*|A|Skulder till övriga företag som det finns ett ägarintresse i och övriga skulder (kortfristiga)
INK2R|2.49|7368|*|A|Skatteskulder
INK2R|2.50|7370|*|A|Upplupna kostnader och förutbetalda intäkter
INK2R|3.1|7410|+|A|Nettoomsättning
INK2R|3.2+|7411|+|A|Förändring av lager av produkter i arbete, färdiga varor och pågående arbete (+)
INK2R|3.2-|7510|-|A|Förändring av lager av produkter i arbete, färdiga varor och pågående arbete (-)
INK2R|3.3|7412|+|A|Aktiverat arbete för egen räkning
INK2R|3.4|7413|+|A|Övriga rörelseintäkter
INK2R|3.5|7511|-|A|Råvaror och förnödenheter
INK2R|3.6|7512|-|A|Handelsvaror
INK2R|3.7|7513|-|A|Övriga externa kostnader
INK2R|3.8|7514|-|A|Personalkostnader
INK2R|3.9|7515|-|A|Av- och nedskrivningar av materiella och immateriella anläggningstillgångar
INK2R|3.10|7516|-|A|Nedskrivningar av omsättningstillgångar utöver normala nedskrivningar
INK2R|3.11|7517|-|A|Övriga rörelsekostnader
INK2R|3.12+|7414|+|A|Resultat från andelar i koncernföretag (+)
INK2R|3.12-|7518|-|A|Resultat från andelar i koncernföretag (-)
INK2R|3.13+|7415|+|A|Resultat från andelar i intresseföretag och gemensamt styrda företag (+)
INK2R|3.13-|7519|-|A|Resultat från andelar i intresseföretag och gemensamt styrda företag (-)
INK2R|3.14+|7423|+|A|Resultat från övriga företag som det finns ett ägarintresse i (+)
INK2R|3.14-|7530|-|A|Resultat från övriga företag som det finns ett ägarintresse i (-)
INK2R|3.15+|7416|+|A|Resultat från övriga finansiella anläggningstillgångar (+)
INK2R|3.15-|7520|-|A|Resultat från övriga finansiella anläggningstillgångar (-)
INK2R|3.16|7417|+|A|Övriga ränteintäkter och liknande resultatposter
INK2R|3.17|7521|-|A|Nedskrivningar av finansiella anläggningstillgångar och kortfristiga placeringar
INK2R|3.18|7522|-|A|Räntekostnader och liknande resultatposter
INK2R|3.19|7524|-|A|Lämnade koncernbidrag
INK2R|3.20|7419|+|A|Mottagna koncernbidrag
INK2R|3.21|7420|+|B|Återföring av periodiseringsfond
INK2R|3.22|7525|-|B|Avsättning till periodiseringsfond
INK2R|3.23+|7421|+|A|Förändring av överavskrivningar (+)
INK2R|3.23-|7526|-|A|Förändring av överavskrivningar (-)
INK2R|3.24+|7422|+|A|Övriga bokslutsdispositioner (+)
INK2R|3.24-|7527|-|A|Övriga bokslutsdispositioner (-)
INK2R|3.25|7528|-|A|Skatt på årets resultat
INK2R|3.26|7450|+|B|Årets resultat, vinst
INK2R|3.27|7550|-|B|Årets resultat, förlust
INK2S|4.1|7650|+|B|Årets resultat, vinst
INK2S|4.2|7750|-|B|Årets resultat, förlust
INK2S|4.3a|7651|+|A|Bokförda kostnader som inte ska dras av: skatt på årets resultat
INK2S|4.3b|7652|+|A|Bokförda kostnader som inte ska dras av: nedskrivning av finansiella tillgångar
INK2S|4.3c|7653|+|A|Bokförda kostnader som inte ska dras av: andra bokförda kostnader
INK2S|4.4a|7751|-|A|Kostnader som ska dras av men inte ingår i resultatet: lämnade koncernbidrag
INK2S|4.4b|7764|-|A|Kostnader som ska dras av men inte ingår i resultatet: andra ej bokförda kostnader
INK2S|4.5a|7752|-|A|Bokförda intäkter som inte ska tas upp: ackordsvinster
INK2S|4.5b|7753|-|A|Bokförda intäkter som inte ska tas upp: utdelning
INK2S|4.5c|7754|-|A|Bokförda intäkter som inte ska tas upp: andra bokförda intäkter
INK2S|4.6a|7654|+|B|Beräknad schablonintäkt på periodiseringsfonder vid beskattningsårets ingång
INK2S|4.6b|7668|+|A|Beräknad schablonintäkt på fondandelar ägda vid kalenderårets ingång
INK2S|4.6c|7655|+|A|Mottagna koncernbidrag
INK2S|4.6d|7673|+|A|Uppräknat belopp vid återföring av periodiseringsfond
INK2S|4.6e|7665|+|A|Andra ej bokförda intäkter
INK2S|4.7a|7755|-|B|Avyttring av delägarrätter: bokförd vinst
INK2S|4.7b|7656|+|B|Avyttring av delägarrätter: bokförd förlust
INK2S|4.7c|7756|-|B|Avyttring av delägarrätter: uppskov med kapitalvinst enligt blankett N4
INK2S|4.7d|7657|+|B|Avyttring av delägarrätter: återfört uppskov med kapitalvinst enligt blankett N4
INK2S|4.7e|7658|+|B|Avyttring av delägarrätter: kapitalvinst för beskattningsåret
INK2S|4.7f|7757|-|B|Avyttring av delägarrätter: kapitalförlust som ska dras av
INK2S|4.8a|7758|-|B|Andel i handelsbolag: bokförd intäkt/vinst
INK2S|4.8b|7659|+|B|Andel i handelsbolag: skattemässigt överskott enligt N3B
INK2S|4.8c|7660|+|B|Andel i handelsbolag: bokförd kostnad/förlust
INK2S|4.8d|7759|-|B|Andel i handelsbolag: skattemässigt underskott enligt N3B
INK2S|4.9+|7666|+|B|Skattemässig justering för avskrivningar på byggnader m.m. (+)
INK2S|4.9-|7765|-|B|Skattemässig justering för avskrivningar på byggnader m.m. (-)
INK2S|4.10+|7661|+|B|Skattemässig justering vid avyttring av näringsfastighet och näringsbostadsrätt (+)
INK2S|4.10-|7760|-|B|Skattemässig justering vid avyttring av näringsfastighet och näringsbostadsrätt (-)
INK2S|4.11|7761|-|B|Skogs-/substansminskningsavdrag (blankett N8)
INK2S|4.12|7662|+|A|Återföringar vid avyttring av fastighet
INK2S|4.13+|7663|+|B|Andra skattemässiga justeringar av resultatet (+)
INK2S|4.13-|7762|-|B|Andra skattemässiga justeringar av resultatet (-)
INK2S|4.14a|7763|-|B|Outnyttjat underskott från föregående år
INK2S|4.14b|7671|+|A|Reduktion av outnyttjat underskott med hänsyn till beloppsspärr, ackord eller konkurs
INK2S|4.14c|7672|+|A|Reduktion av outnyttjat underskott med hänsyn till koncernbidragsspärr, fusionsspärr m.m.
INK2S|4.15|7670|+|B|Överskott (flyttas till p. 1.1)
INK2S|4.16|7770|-|B|Underskott (flyttas till p. 1.2)
INK2S|4.17|8020|*|A|Värdeminskningsavdrag på byggnader vid beskattningsårets utgång
INK2S|4.18|8021|*|A|Värdeminskningsavdrag på markanläggningar vid beskattningsårets utgång
INK2S|4.19|8023|*|B|Vid restvärdesavskrivning: återförda belopp
INK2S|4.20|8026|*|B|Lån från aktieägare (fysisk person) vid räkenskapsårets utgång
INK2S|4.21|8022|*|A|Pensionskostnader (som ingår i p. 3.8)
INK2S|4.22|8028|*|B|Koncernbidragsspärrat och fusionsspärrat underskott m.m.
'@
    foreach ($line in ($data -split "`r?`n")) {
        if (-not $line) { continue }
        $f = $line -split '\|'
        [PSCustomObject]@{
            Form        = $f[0]
            Box         = $f[1]
            Code        = [int]$f[2]
            Sign        = $f[3]
            NonNegative = ($f[4] -eq 'B')
            Description = $f[5]
        }
    }
}

function Resolve-SruInk2sField {
    <#
    .SYNOPSIS
    Resolves an INK2S field given either its SRU code ('7652') or its row on
    the form ('4.3b', '4.13+'), returning the field definition.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [object[]]$Fields
    )

    $k = ($Key -replace '\s', '').ToLowerInvariant()
    $ink2s = @($Fields | Where-Object Form -eq 'INK2S')
    if ($k -match '^\d{4}$') {
        $field = $ink2s | Where-Object { $_.Code -eq [int]$k }
    }
    else {
        $field = $ink2s | Where-Object { $_.Box.ToLowerInvariant() -eq $k }
        if (-not $field) {
            $pair = @($ink2s | Where-Object { $_.Box.ToLowerInvariant().TrimEnd('+', '-') -eq $k })
            if ($pair.Count -gt 1) {
                throw "INK2S row '$Key' has a (+) and a (-) field; write '$($k)+' or '$($k)-'."
            }
            $field = $pair | Select-Object -First 1
        }
    }
    if (-not $field) {
        throw "Unknown INK2S field '$Key'. Use a row on the form (e.g. '4.3b') or its SRU code (e.g. '7652')."
    }
    if ($field.Code -in 7650, 7750) {
        throw "INK2S $($field.Box) (årets resultat) is taken from the books and cannot be supplied as an adjustment."
    }
    $field
}

function Get-SruTaxAdjustmentRules {
    <#
    .SYNOPSIS
    Returns the BAS-account-range rules that derive INK2S tax adjustments
    automatically from the trial balance.

    .DESCRIPTION
    Each rule has Min/Max (inclusive BAS account range) and the INK2S field the
    net balance of the range goes to. DebitSru receives a net debit balance
    (a cost to add back) and CreditSru a net credit balance (an income to
    deduct); either may be $null. Assumption is $true for rules that rest on a
    judgement rather than on the account's own definition; the export warns when
    such a rule produces an amount.

    The unambiguous rules cover BAS accounts whose name states the tax
    treatment (skattefria ränteintäkter, ej avdragsgilla kostnader, ränta på
    skattekontot). The assumption rule treats write-downs (827x) and reversals
    of write-downs (828x) of shares in other companies as non-deductible and
    non-taxable, which holds for kapitalplaceringsaktier but not for
    lageraktier.
    #>
    [CmdletBinding()]
    param()

    @(
        # 4.3c Andra bokförda kostnader (ej avdragsgilla)
        [PSCustomObject]@{ Min = 6072; Max = 6072; DebitSru = 7653; CreditSru = $null; Assumption = $false; Label = 'Representation, ej avdragsgill' }
        [PSCustomObject]@{ Min = 6982; Max = 6982; DebitSru = 7653; CreditSru = $null; Assumption = $false; Label = 'Föreningsavgifter, ej avdragsgilla' }
        [PSCustomObject]@{ Min = 6992; Max = 6992; DebitSru = 7653; CreditSru = $null; Assumption = $false; Label = 'Övriga externa kostnader, ej avdragsgilla' }
        [PSCustomObject]@{ Min = 7622; Max = 7622; DebitSru = 7653; CreditSru = $null; Assumption = $false; Label = 'Sjuk- och hälsovård, ej avdragsgill' }
        [PSCustomObject]@{ Min = 7632; Max = 7632; DebitSru = 7653; CreditSru = $null; Assumption = $false; Label = 'Personalrepresentation, ej avdragsgill' }
        [PSCustomObject]@{ Min = 8423; Max = 8423; DebitSru = 7653; CreditSru = $null; Assumption = $false; Label = 'Räntekostnader för skatter och avgifter' }
        # 4.5c Andra bokförda intäkter (ej skattepliktiga)
        [PSCustomObject]@{ Min = 8314; Max = 8314; DebitSru = $null; CreditSru = 7754; Assumption = $false; Label = 'Skattefria ränteintäkter' }
        # 4.3b Nedskrivning av finansiella tillgångar / 4.5c återförda nedskrivningar
        [PSCustomObject]@{ Min = 8270; Max = 8289; DebitSru = 7652; CreditSru = 7754; Assumption = $true; Label = 'Ned- och uppskrivningar av andelar i andra företag' }
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
    Returns the SRU blankett period suffix for the month a fiscal year ends in:
    P1 (January-April), P2 (May-June), P3 (July-August) or P4
    (September-December). The income year in the blankett type string is the
    year the fiscal year ends.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$EndMonth
    )

    if ($EndMonth -ge 1 -and $EndMonth -le 4) { return 'P1' }
    if ($EndMonth -ge 5 -and $EndMonth -le 6) { return 'P2' }
    if ($EndMonth -ge 7 -and $EndMonth -le 8) { return 'P3' }
    return 'P4'
}
