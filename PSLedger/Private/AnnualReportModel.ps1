<#
    Private helper: assemble a complete K2 årsredovisning as an ordered list of
    layout blocks (see AnnualReportRender.ps1 for the block schema). The blocks are
    format-independent so the same content renders to text, Markdown and .docx.

    Fixed-asset and shareholding notes are auto-detected from the standard BAS
    account ranges below; a note is only emitted when the relevant accounts carry a
    balance.
#>

function Build-LedgerAnnualReportBlocks {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear,

        [Parameter()]
        [switch]$NoComparison
    )

    $profile = Get-LedgerCompanyProfile -JournalPath $JournalPath
    $reportInput = Get-LedgerReportInput -JournalPath $JournalPath -FiscalYear $FiscalYear
    $year = Get-LedgerFiscalYear -JournalPath $JournalPath | Where-Object { $_.Name -eq $FiscalYear }

    # Locate the immediately preceding fiscal year for comparison figures.
    $comparisonYear = $null
    if (-not $NoComparison) {
        $allYears = @(Get-LedgerFiscalYear -JournalPath $JournalPath)
        for ($i = 0; $i -lt $allYears.Count; $i++) {
            if ($allYears[$i].Name -eq $FiscalYear) {
                if ($i -gt 0) { $comparisonYear = $allYears[$i - 1].Name }
                break
            }
        }
    }

    $currentLabel = Format-LedgerYearLabel -FiscalYear $FiscalYear
    $comparisonLabel = if ($comparisonYear) { Format-LedgerYearLabel -FiscalYear $comparisonYear } else { $null }
    $fmt = { param($v) Format-LedgerAmount -Value $v -Decimals 0 }

    # Statements and notes are headed by the period (resultaträkning, notes) or the
    # balance sheet date, as in a printed årsredovisning.
    $comparisonYearObj = if ($comparisonYear) { Get-LedgerFiscalYear -JournalPath $JournalPath | Where-Object { $_.Name -eq $comparisonYear } } else { $null }
    $periodLabel = { param($y, $fallback) if ($y) { "$(([datetime]$y.StartDate).ToString('yyyy-MM-dd'))`n– $(([datetime]$y.EndDate).ToString('yyyy-MM-dd'))" } else { $fallback } }
    $dateLabel = { param($y, $fallback) if ($y) { ([datetime]$y.EndDate).ToString('yyyy-MM-dd') } else { $fallback } }
    $currentPeriod = & $periodLabel $year $currentLabel
    $comparisonPeriod = if ($comparisonYear) { & $periodLabel $comparisonYearObj $comparisonLabel } else { $null }
    $currentDate = & $dateLabel $year $currentLabel
    $comparisonDate = if ($comparisonYear) { & $dateLabel $comparisonYearObj $comparisonLabel } else { $null }

    $dateRange = if ($year) {
        "$(([datetime]$year.StartDate).ToString('yyyy-MM-dd')) - $(([datetime]$year.EndDate).ToString('yyyy-MM-dd'))"
    }
    else { $FiscalYear }

    # ---- Auto-detect notes and assign note numbers in appearance order ----------
    $assetGroups = @(
        @{ Label = 'Immateriella anläggningstillgångar'; CostFrom = 1000; CostTo = 1088; DepFrom = 1089; DepTo = 1099; Row = 'IntangibleAssets' }
        @{ Label = 'Byggnader och mark'; CostFrom = 1100; CostTo = 1118; DepFrom = 1119; DepTo = 1119; Row = 'BuildingsAndLand' }
        @{ Label = 'Maskiner och andra tekniska anläggningar'; CostFrom = 1210; CostTo = 1218; DepFrom = 1219; DepTo = 1219; Row = 'MachineryAndEquipment' }
        @{ Label = 'Inventarier, verktyg och installationer'; CostFrom = 1220; CostTo = 1228; DepFrom = 1229; DepTo = 1229; Row = 'MachineryAndEquipment' }
        @{ Label = 'Andra långfristiga värdepappersinnehav'; CostFrom = 1350; CostTo = 1358; DepFrom = 1359; DepTo = 1359; DepLabel = 'nedskrivningar'; Row = 'LongTermSecurities' }
    )

    $fixedAssetNotes = @()
    $fixedAssetPrevNotes = @()
    $fixedAssetDepLabels = @()
    $fixedAssetRowGroups = @()
    foreach ($g in $assetGroups) {
        $params = @{
            JournalPath = $JournalPath
            FiscalYear  = $FiscalYear
            FromAccount = $g.CostFrom
            ToAccount   = $g.CostTo
            Label       = $g.Label
        }
        if ($null -ne $g.DepFrom) {
            $params.DepreciationFromAccount = $g.DepFrom
            $params.DepreciationToAccount = $g.DepTo
        }
        $note = Get-LedgerFixedAssetNote @params
        if ($note -and ($note.ClosingAcquisition -ne 0 -or $note.OpeningAcquisition -ne 0)) {
            $fixedAssetNotes += $note
            $fixedAssetDepLabels += if ($g.DepLabel) { $g.DepLabel } else { 'avskrivningar' }
            $fixedAssetRowGroups += $g.Row
            $prev = $null
            if ($comparisonYear) {
                $params.FiscalYear = $comparisonYear
                $prev = Get-LedgerFixedAssetNote @params
            }
            $fixedAssetPrevNotes += , $prev
        }
    }

    $hasMarketValue = $null -ne $reportInput.SecuritiesMarketValue -and $reportInput.SecuritiesMarketValue -ne ''
    $shareholdingNote = $null
    $shareholdingPrev = $null
    if ($hasMarketValue) {
        $shareholdingNote = Get-LedgerShareholdingNote -JournalPath $JournalPath -FiscalYear $FiscalYear
        if ($comparisonYear) {
            $shareholdingPrev = Get-LedgerShareholdingNote -JournalPath $JournalPath -FiscalYear $comparisonYear
        }
    }

    $equityNote = @(Get-LedgerEquityReconciliation -JournalPath $JournalPath -FiscalYear $FiscalYear)

    # Numbered notes in balance-sheet appearance order: fixed assets, shareholding,
    # equity. Accounting principles and the employee note are unnumbered.
    $noteKeys = @()
    for ($i = 0; $i -lt $fixedAssetNotes.Count; $i++) { $noteKeys += "FixedAsset$i" }
    if ($shareholdingNote) { $noteKeys += 'Shareholding' }
    if ($equityNote) { $noteKeys += 'Equity' }
    $register = New-LedgerNoteRegister -NoteKey $noteKeys

    $equityNoteNo = Get-LedgerNoteNumber -Register $register -Key 'Equity'

    # ---- Build blocks -----------------------------------------------------------
    $blocks = @()

    $heading = $profile.Name
    if ($profile.OrgNumber) { $heading = "$heading, org.nr $($profile.OrgNumber)" }

    # Cover
    $blocks += @{ Type = 'Title'; Text = 'Årsredovisning'; Cover = $true }
    $blocks += @{ Type = 'Paragraph'; Text = $heading; Cover = $true }
    $blocks += @{ Type = 'Paragraph'; Text = "för räkenskapsåret $dateRange"; Cover = $true }

    # Fastställelseintyg on the cover, as Bolagsverket recommends. It is signed
    # after the årsstämma, so the signing date is always left blank.
    $meetingDate = if ($reportInput.AnnualMeetingDate) { Format-LedgerSwedishDate -Date $reportInput.AnnualMeetingDate } else { '____________' }
    $certPlace = if ($reportInput.CertificatePlace) { $reportInput.CertificatePlace } elseif ($profile.RegisteredOffice) { $profile.RegisteredOffice } else { '____________' }
    $certSigner = if ($reportInput.CertificateSigner) { $reportInput.CertificateSigner } elseif ($profile.BoardMembers.Count -gt 0) { @($profile.BoardMembers)[0] } else { '' }
    $blocks += @{
        Type    = 'Certificate'
        Heading = 'Fastställelseintyg'
        Text    = "Undertecknad styrelseledamot intygar härmed, dels att denna kopia av årsredovisningen överensstämmer med originalet, dels att resultat- och balansräkningen fastställts på årsstämma den $meetingDate. Årsstämman beslöt tillika att godkänna styrelsens förslag till resultatdisposition."
        Place   = "$certPlace den ____________"
        Signer  = $certSigner
    }
    $blocks += @{ Type = 'PageBreak' }

    # Förvaltningsberättelse
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Förvaltningsberättelse' }
    $blocks += @{ Type = 'Paragraph'; Text = "Styrelsen för $($profile.Name) avger följande årsredovisning för räkenskapsåret $dateRange. Om inte annat särskilt anges, redovisas alla belopp i hela kronor." }
    $blocks += @{ Type = 'Heading'; Level = 2; Text = 'Verksamheten' }
    if ($profile.BusinessObject) {
        $blocks += @{ Type = 'Paragraph'; Text = "Allmänt om verksamheten: $($profile.BusinessObject)" }
    }
    if ($profile.RegisteredOffice) {
        $blocks += @{ Type = 'Paragraph'; Text = "Företaget har sitt säte i $($profile.RegisteredOffice)." }
    }
    if ($reportInput.SignificantEvents) {
        $blocks += @{ Type = 'Heading'; Level = 2; Text = 'Väsentliga händelser under räkenskapsåret' }
        $blocks += @{ Type = 'Paragraph'; Text = $reportInput.SignificantEvents }
    }

    # Flerårsöversikt
    $overview = @(Get-LedgerMultiYearOverview -JournalPath $JournalPath -FiscalYear $FiscalYear -Years 5)
    if ($overview.Count -gt 0) {
        $blocks += @{ Type = 'Heading'; Level = 2; Text = 'Flerårsöversikt' }
        $ovHeader = @('') + ($overview | ForEach-Object { $_.YearLabel })
        $ovAlign = @('left') + ($overview | ForEach-Object { 'right' })
        $ovRows = @()
        $ovRows += , (@('Nettoomsättning') + ($overview | ForEach-Object { & $fmt $_.NetSales }))
        $ovRows += , (@('Resultat efter finansiella poster') + ($overview | ForEach-Object { & $fmt $_.ResultAfterFinancialItems }))
        $ovRows += , (@('Årets resultat') + ($overview | ForEach-Object { & $fmt $_.NetResult }))
        $ovRows += , (@('Balansomslutning') + ($overview | ForEach-Object { & $fmt $_.TotalAssets }))
        $ovRows += , (@('Soliditet (%)') + ($overview | ForEach-Object { if ($null -ne $_.EquityRatio) { Format-LedgerAmount -Value $_.EquityRatio -Decimals 1 } else { '' } }))
        $blocks += @{ Type = 'Table'; Header = $ovHeader; Align = $ovAlign; Rows = $ovRows }
        $blocks += @{ Type = 'Paragraph'; Text = 'Soliditet: justerat eget kapital i procent av balansomslutningen.' }
    }

    # Förslag till vinstdisposition
    $disp = Get-LedgerProfitDisposition -JournalPath $JournalPath -FiscalYear $FiscalYear
    if ($disp) {
        $blocks += @{ Type = 'Heading'; Level = 2; Text = 'Förslag till vinstdisposition' }
        $blocks += @{ Type = 'Paragraph'; Text = 'Till årsstämmans förfogande står följande medel (kronor):' }
        $dispRows = @()
        $dispRows += , @('Balanserat resultat', (& $fmt $disp.RetainedEarnings))
        $dispRows += , @('Årets resultat', (& $fmt $disp.YearResult))
        $dispRows += , @('Summa', (& $fmt $disp.TotalDisposable))
        $blocks += @{ Type = 'Table'; Header = @('', $currentLabel); Align = @('left', 'right'); Rows = $dispRows; RowStyles = @('Normal', 'Normal', 'Sum') }
        $blocks += @{ Type = 'Paragraph'; Text = 'Styrelsen föreslår att medlen disponeras så att:' }
        $propRows = @()
        $propRows += , @('Utdelning', (& $fmt $disp.ProposedDividend))
        $propRows += , @('Balanseras i ny räkning', (& $fmt $disp.CarriedForward))
        $propRows += , @('Summa', (& $fmt $disp.TotalDisposable))
        $blocks += @{ Type = 'Table'; Header = @('', $currentLabel); Align = @('left', 'right'); Rows = $propRows; RowStyles = @('Normal', 'Normal', 'Sum') }
        if ($null -ne $disp.DividendPerShare) {
            $blocks += @{ Type = 'Paragraph'; Text = ("Föreslagen utdelning per aktie: {0} kr (antal aktier: {1})." -f (& $fmt $disp.DividendPerShare), $disp.NumberOfShares) }
        }
    }
    $blocks += @{ Type = 'Paragraph'; Text = 'Bolagets resultat och ställning i övrigt framgår av efterföljande resultat- och balansräkning med tilläggsupplysningar.' }

    # ---- Resultaträkning --------------------------------------------------------
    $incCurrent = @(Get-LedgerIncomeStatementPresentation -JournalPath $JournalPath -FiscalYear $FiscalYear)
    $incPrev = @{}
    if ($comparisonYear) {
        foreach ($r in @(Get-LedgerIncomeStatementPresentation -JournalPath $JournalPath -FiscalYear $comparisonYear)) { $incPrev[$r.Group] = $r.Amount }
    }
    $hasAppropriations = ($incCurrent | Where-Object { $_.Group -eq 'Appropriations' }).Amount -ne 0 -or ($incPrev.ContainsKey('Appropriations') -and $incPrev['Appropriations'] -ne 0)
    $income = foreach ($r in $incCurrent) {
        if ($r.Group -eq 'ResultBeforeTax' -and -not $hasAppropriations) { continue }
        [PSCustomObject]@{
            Group            = $r.Group
            Label            = $r.Label
            Amount           = $r.Amount
            ComparisonAmount = if ($comparisonYear -and $incPrev.ContainsKey($r.Group)) { $incPrev[$r.Group] } else { $null }
        }
    }
    $incSections = @(
        @{ Before = 'NetSales'; Label = 'Rörelseintäkter'; Groups = @('NetSales', 'OtherOperatingRevenue') }
        @{ Before = 'RawMaterials'; Label = 'Rörelsekostnader'; Groups = @('RawMaterials', 'OtherExternalExpenses', 'PersonnelCosts', 'Depreciation', 'OtherOperatingExpenses') }
        @{ Before = 'GroupCompanyResult'; Label = 'Finansiella poster'; Groups = @('GroupCompanyResult', 'AssociatedCompanyResult', 'FinancialFixedAssetResult', 'InterestIncome', 'InterestExpenses') }
    )
    $incSums = @('OperatingResult', 'ResultAfterFinancialItems', 'ResultBeforeTax', 'NetResult')
    $blocks += @{ Type = 'PageBreak' }
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Resultaträkning' }
    $blocks += (New-LedgerStatementTable -Rows $income -CurrentLabel $currentPeriod -ComparisonLabel $comparisonPeriod -Fmt $fmt -NoteMap @{} `
            -SumGroups $incSums -KeepGroups $incSums -Sections $incSections -HideZero)

    # ---- Balansräkning (detailed) ----------------------------------------------
    $balCurrent = @(Get-LedgerBalanceSheetPresentation -JournalPath $JournalPath -FiscalYear $FiscalYear)
    $balPrev = @{}
    if ($comparisonYear) {
        foreach ($r in @(Get-LedgerBalanceSheetPresentation -JournalPath $JournalPath -FiscalYear $comparisonYear)) {
            $balPrev[$r.Group] = $r.Amount
        }
    }
    $balRows = foreach ($r in $balCurrent) {
        [PSCustomObject]@{
            Group            = $r.Group
            Label            = $r.Label
            Amount           = $r.Amount
            ComparisonAmount = if ($comparisonYear -and $balPrev.ContainsKey($r.Group)) { $balPrev[$r.Group] } else { $null }
        }
    }
    $balNoteMap = @{}
    for ($i = 0; $i -lt $fixedAssetNotes.Count; $i++) {
        $grp = $fixedAssetRowGroups[$i]
        $no = [string](Get-LedgerNoteNumber -Register $register -Key "FixedAsset$i")
        $balNoteMap[$grp] = if ($balNoteMap.ContainsKey($grp)) { "$($balNoteMap[$grp]), $no" } else { $no }
    }
    if ($shareholdingNote) {
        $no = [string](Get-LedgerNoteNumber -Register $register -Key 'Shareholding')
        $balNoteMap['LongTermSecurities'] = if ($balNoteMap.ContainsKey('LongTermSecurities')) { "$($balNoteMap['LongTermSecurities']), $no" } else { $no }
    }
    if ($equityNoteNo) {
        foreach ($eg in 'Equity', 'ShareCapital', 'RestrictedReserves', 'RetainedEarnings', 'YearResult') {
            $balNoteMap[$eg] = $equityNoteNo
        }
    }
    $fixedGroups = @('IntangibleAssets', 'BuildingsAndLand', 'MachineryAndEquipment', 'GroupShares', 'LongTermSecurities', 'LongTermReceivables')
    $shortTermGroups = @('AccountsPayable', 'CurrentTaxLiabilities', 'OtherShortTermLiabilities', 'AccruedExpenses')
    $balSections = @(
        @{ Before = 'IntangibleAssets'; Label = 'TILLGÅNGAR' }
        @{ Before = 'IntangibleAssets'; Label = 'Anläggningstillgångar'; Groups = $fixedGroups }
        @{ Before = 'BuildingsAndLand'; Label = 'Materiella anläggningstillgångar'; Groups = @('BuildingsAndLand', 'MachineryAndEquipment') }
        @{ Before = 'GroupShares'; Label = 'Finansiella anläggningstillgångar'; Groups = @('GroupShares', 'LongTermSecurities', 'LongTermReceivables') }
        @{ Before = 'Inventory'; Label = 'Omsättningstillgångar'; Groups = @('Inventory', 'AccountsReceivable', 'OtherReceivables', 'PrepaidExpenses', 'ShortTermInvestments', 'CashAndBank') }
        @{ Before = 'ShareCapital'; Label = 'EGET KAPITAL OCH SKULDER' }
        @{ Before = 'ShareCapital'; Label = 'Eget kapital' }
        @{ Before = 'ShareCapital'; Label = 'Bundet eget kapital' }
        @{ Before = 'RetainedEarnings'; Label = 'Fritt eget kapital' }
        @{ Before = 'AccountsPayable'; Label = 'Kortfristiga skulder'; Groups = $shortTermGroups }
    )
    # Subtotals are shown when their section has content; the main totals always.
    $balKeep = @('TotalCurrentAssets', 'TotalAssets', 'Equity', 'TotalEquityAndLiabilities')
    foreach ($pair in @(@('TotalFixedAssets', $fixedGroups), @('TotalShortTermLiabilities', $shortTermGroups))) {
        if ($balRows | Where-Object { $pair[1] -contains $_.Group -and ($_.Amount -ne 0 -or ($null -ne $_.ComparisonAmount -and $_.ComparisonAmount -ne 0)) }) { $balKeep += $pair[0] }
    }
    $blocks += @{ Type = 'PageBreak' }
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Balansräkning' }
    $blocks += (New-LedgerStatementTable -Rows $balRows -CurrentLabel $currentDate -ComparisonLabel $comparisonDate -Fmt $fmt -NoteMap $balNoteMap `
            -SumGroups @('TotalFixedAssets', 'TotalCurrentAssets', 'TotalAssets', 'Equity', 'TotalShortTermLiabilities', 'TotalEquityAndLiabilities') `
            -KeepGroups $balKeep -Sections $balSections -HideZero)

    # ---- Noter / Tilläggsupplysningar ------------------------------------------
    $blocks += @{ Type = 'PageBreak' }
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Noter' }

    $blocks += @{ Type = 'Heading'; Level = 2; Text = 'Redovisnings- och värderingsprinciper' }
    foreach ($p in @(Get-LedgerAccountingPrinciples -AsLines)) {
        $blocks += @{ Type = 'Paragraph'; Text = $p }
    }
    if ($reportInput.ComparativeFiguresNote) {
        $blocks += @{ Type = 'Heading'; Level = 2; Text = 'Jämförelsetal' }
        $blocks += @{ Type = 'Paragraph'; Text = $reportInput.ComparativeFiguresNote }
    }

    $noteHeader = if ($comparisonYear) { @('', $currentPeriod, $comparisonPeriod) } else { @('', $currentPeriod) }
    $noteAlign = if ($comparisonYear) { @('left', 'right', 'right') } else { @('left', 'right') }
    $noteRow = {
        param($label, $cur, $prev, $hasPrev)
        $cells = @($label, (& $fmt $cur))
        if ($comparisonYear) { $cells += if ($hasPrev) { & $fmt $prev } else { '' } }
        , $cells
    }

    # Employee note (unnumbered)
    $emp = Get-LedgerEmployeeNote -JournalPath $JournalPath -FiscalYear $FiscalYear
    if ($emp) {
        $blocks += @{ Type = 'Heading'; Level = 2; Text = $emp.Label }
        $blocks += @{ Type = 'Paragraph'; Text = $emp.Statement }
    }

    # Fixed-asset notes (numbered)
    for ($i = 0; $i -lt $fixedAssetNotes.Count; $i++) {
        $n = $fixedAssetNotes[$i]
        $p = $fixedAssetPrevNotes[$i]
        $hp = $null -ne $p
        $no = Get-LedgerNoteNumber -Register $register -Key "FixedAsset$i"
        $blocks += @{ Type = 'Heading'; Level = 2; Text = "Not $no  $($n.Label)" }
        $rows = @()
        $rows += , (& $noteRow 'Ingående anskaffningsvärde' $n.OpeningAcquisition $p.OpeningAcquisition $hp)
        $rows += , (& $noteRow 'Årets inköp' $n.Purchases $p.Purchases $hp)
        $rows += , (& $noteRow 'Årets avyttringar' $n.Disposals $p.Disposals $hp)
        $rows += , (& $noteRow 'Utgående anskaffningsvärde' $n.ClosingAcquisition $p.ClosingAcquisition $hp)
        if ($n.HasDepreciation) {
            $depLabel = $fixedAssetDepLabels[$i]
            # Write-ups (positive values) are shown as such, e.g. reversed uppskrivningar.
            if ($depLabel -eq 'nedskrivningar' -and (@($n, $p) | Where-Object { $_ } | Where-Object { $_.OpeningDepreciation -gt 0 -or $_.YearDepreciation -gt 0 -or $_.ClosingDepreciation -gt 0 })) {
                $depLabel = 'upp- och nedskrivningar'
            }
            $rows += , (& $noteRow "Ingående $depLabel" $n.OpeningDepreciation $p.OpeningDepreciation $hp)
            $rows += , (& $noteRow "Årets $depLabel" $n.YearDepreciation $p.YearDepreciation $hp)
            $rows += , (& $noteRow "Utgående $depLabel" $n.ClosingDepreciation $p.ClosingDepreciation $hp)
        }
        $rows += , (& $noteRow 'Redovisat värde' $n.BookValue $p.BookValue $hp)
        $styles = foreach ($r in $rows) { if ($r[0] -like 'Utgående *' -or $r[0] -eq 'Redovisat värde') { 'Sum' } else { 'Normal' } }
        $blocks += @{ Type = 'Table'; Header = $noteHeader; Align = $noteAlign; Rows = $rows; RowStyles = @($styles) }
    }

    # Shareholding note (numbered)
    if ($shareholdingNote) {
        $no = Get-LedgerNoteNumber -Register $register -Key 'Shareholding'
        $blocks += @{ Type = 'Heading'; Level = 2; Text = "Not $no  $($shareholdingNote.Label)" }
        $rows = @()
        $rows += , (& $noteRow 'Bokfört värde' $shareholdingNote.BookValue $shareholdingPrev.BookValue ($null -ne $shareholdingPrev))
        $rows += , (& $noteRow 'Marknadsvärde' $shareholdingNote.MarketValue $shareholdingPrev.MarketValue ($null -ne $shareholdingPrev -and $null -ne $shareholdingPrev.MarketValue))
        $blocks += @{ Type = 'Table'; Header = $noteHeader; Align = $noteAlign; Rows = $rows }
    }

    # Equity note (numbered)
    if ($equityNote -and $equityNoteNo) {
        $blocks += @{ Type = 'Heading'; Level = 2; Text = "Not $equityNoteNo  Förändring av eget kapital" }
        $eqRows = @()
        foreach ($c in $equityNote) {
            $eqRows += , @($c.Label, (& $fmt $c.OpeningBalance), (& $fmt $c.Change), (& $fmt $c.ClosingBalance))
        }
        $eqStyles = foreach ($c in $equityNote) { if ($c.Component -eq 'Total') { 'Sum' } else { 'Normal' } }
        $blocks += @{ Type = 'Table'; Header = @('', 'Ingående balans', 'Förändring', 'Utgående balans'); Align = @('left', 'right', 'right', 'right'); Rows = $eqRows; RowStyles = @($eqStyles) }
    }

    # ---- Underskrifter och fastställelseintyg -----------------------------------
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Underskrifter' }
    $signLine = @()
    if ($reportInput.SigningPlace) { $signLine += $reportInput.SigningPlace }
    if ($reportInput.SigningDate) { $signLine += $reportInput.SigningDate }
    if ($signLine.Count -gt 0) {
        $blocks += @{ Type = 'Paragraph'; Text = ($signLine -join ' '); KeepNext = $true }
    }
    if ($profile.BoardMembers.Count -gt 0) {
        $blocks += @{ Type = 'Signatures'; Names = @($profile.BoardMembers) }
    }

    $blocks
}

function Format-LedgerSwedishDate {
    <#
        Private helper: format an ISO date as '1 oktober 2025'. Text that is not a
        date is returned unchanged.
    #>
    param ([string]$Date)
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($Date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$parsed)) {
        return $parsed.ToString('d MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo('sv-SE'))
    }
    $Date
}

function Get-LedgerBalanceSheetPresentation {
    <#
        Private helper: the balansräkning rows as printed in an årsredovisning.
        Unlike Get-LedgerBalanceSheet (natural signs), equity and liabilities are
        shown as positive amounts, and equity is split into Aktiekapital, Bundna
        reserver, Balanserat resultat and Årets resultat using
        Get-LedgerEquityReconciliation, so the unclosed result and any
        resultatdisposition booked during the year are presented correctly.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear
    )

    $balance = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)
    if (-not $balance) { return }
    $sum = {
        param([int[][]]$Ranges)
        $s = [decimal]0
        foreach ($b in $balance) {
            $n = 0
            if (-not [int]::TryParse($b.AccountNumber, [ref]$n)) { continue }
            foreach ($r in $Ranges) { if ($n -ge $r[0] -and $n -le $r[1]) { $s += [decimal]$b.Balance; break } }
        }
        $s
    }

    $eq = @{}
    foreach ($c in @(Get-LedgerEquityReconciliation -JournalPath $JournalPath -FiscalYear $FiscalYear)) {
        $eq[$c.Component] = [decimal]$c.ClosingBalance
    }
    $get = { param($h, $k) if ($h.ContainsKey($k)) { $h[$k] } else { [decimal]0 } }
    $row = { param($section, $group, $label, $value) [PSCustomObject]@{ Section = $section; Group = $group; Label = $label; Amount = [decimal]$value } }

    # A net debit on the tax accounts (2500-2599) is a receivable, not a negative liability.
    $taxBalance = & $sum @(, @(2500, 2599))
    $taxReceivable = if ($taxBalance -gt 0) { $taxBalance } else { [decimal]0 }

    $intangible = & $sum @(, @(1000, 1099))
    $buildings = & $sum @(, @(1100, 1199))
    $machinery = & $sum @(, @(1200, 1299))
    $groupShares = & $sum @(, @(1300, 1349))
    $securities = & $sum @(, @(1350, 1359))
    $longReceivables = & $sum @(, @(1360, 1399))
    $fixed = $intangible + $buildings + $machinery + $groupShares + $securities + $longReceivables

    $inventory = & $sum @(, @(1400, 1499))
    $customers = & $sum @(, @(1500, 1599))
    $otherReceivables = (& $sum @(, @(1600, 1699))) + $taxReceivable
    $prepaid = & $sum @(, @(1700, 1799))
    $shortInvestments = & $sum @(, @(1800, 1899))
    $cash = & $sum @(, @(1900, 1999))
    $current = $inventory + $customers + $otherReceivables + $prepaid + $shortInvestments + $cash

    & $row 'Assets' 'IntangibleAssets' 'Immateriella anläggningstillgångar' $intangible
    & $row 'Assets' 'BuildingsAndLand' 'Byggnader och mark' $buildings
    & $row 'Assets' 'MachineryAndEquipment' 'Maskiner och inventarier' $machinery
    & $row 'Assets' 'GroupShares' 'Andelar i koncern- och intresseföretag' $groupShares
    & $row 'Assets' 'LongTermSecurities' 'Andra långfristiga värdepappersinnehav' $securities
    & $row 'Assets' 'LongTermReceivables' 'Andra långfristiga fordringar' $longReceivables
    & $row 'Assets' 'TotalFixedAssets' 'Summa anläggningstillgångar' $fixed
    & $row 'Assets' 'Inventory' 'Varulager m.m.' $inventory
    & $row 'Assets' 'AccountsReceivable' 'Kundfordringar' $customers
    & $row 'Assets' 'OtherReceivables' 'Övriga fordringar' $otherReceivables
    & $row 'Assets' 'PrepaidExpenses' 'Förutbetalda kostnader och upplupna intäkter' $prepaid
    & $row 'Assets' 'ShortTermInvestments' 'Kortfristiga placeringar' $shortInvestments
    & $row 'Assets' 'CashAndBank' 'Kassa och bank' $cash
    & $row 'Assets' 'TotalCurrentAssets' 'Summa omsättningstillgångar' $current
    & $row 'Assets' 'TotalAssets' 'Summa tillgångar' ($fixed + $current)

    # Liabilities carry natural (credit = negative) signs in the ledger.
    $untaxed = -(& $sum @(, @(2100, 2199)))
    $provisions = -(& $sum @(, @(2200, 2299)))
    $longTerm = -(& $sum @(, @(2300, 2399)))
    $payables = -(& $sum @(, @(2440, 2449)))
    $taxLiabilities = -($taxBalance - $taxReceivable)
    $otherLiabilities = -(& $sum @(@(2400, 2439), @(2450, 2499), @(2600, 2899)))
    $accrued = -(& $sum @(, @(2900, 2999)))
    $shortTerm = $payables + $taxLiabilities + $otherLiabilities + $accrued
    $equity = & $get $eq 'Total'

    & $row 'EquityAndLiabilities' 'ShareCapital' 'Aktiekapital' (& $get $eq 'ShareCapital')
    & $row 'EquityAndLiabilities' 'RestrictedReserves' 'Bundna reserver' (& $get $eq 'RestrictedReserves')
    & $row 'EquityAndLiabilities' 'RetainedEarnings' 'Balanserat resultat' (& $get $eq 'RetainedEarnings')
    & $row 'EquityAndLiabilities' 'YearResult' 'Årets resultat' (& $get $eq 'YearResult')
    & $row 'EquityAndLiabilities' 'Equity' 'Summa eget kapital' $equity
    & $row 'EquityAndLiabilities' 'UntaxedReserves' 'Obeskattade reserver' $untaxed
    & $row 'EquityAndLiabilities' 'Provisions' 'Avsättningar' $provisions
    & $row 'EquityAndLiabilities' 'LongTermLiabilities' 'Långfristiga skulder' $longTerm
    & $row 'EquityAndLiabilities' 'AccountsPayable' 'Leverantörsskulder' $payables
    & $row 'EquityAndLiabilities' 'CurrentTaxLiabilities' 'Skatteskulder' $taxLiabilities
    & $row 'EquityAndLiabilities' 'OtherShortTermLiabilities' 'Övriga skulder' $otherLiabilities
    & $row 'EquityAndLiabilities' 'AccruedExpenses' 'Upplupna kostnader och förutbetalda intäkter' $accrued
    & $row 'EquityAndLiabilities' 'TotalShortTermLiabilities' 'Summa kortfristiga skulder' $shortTerm
    & $row 'EquityAndLiabilities' 'TotalEquityAndLiabilities' 'Summa eget kapital och skulder' ($equity + $untaxed + $provisions + $longTerm + $shortTerm)
}

function Get-LedgerIncomeStatementPresentation {
    <#
        Private helper: the resultaträkning rows in the K2 kostnadsslagsindelad
        layout (ÅRL bilaga 2), with revenue and profits as positive amounts. Bank
        and other external costs are Övriga externa kostnader (5000-6999); only
        7900-7999 are Övriga rörelsekostnader. Financial items are split into the
        statutory lines. Resultat före skatt is only included when there are
        bokslutsdispositioner.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$FiscalYear
    )

    $balance = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)
    $sum = {
        param([int]$From, [int]$To)
        $s = [decimal]0
        foreach ($b in $balance) {
            $n = 0
            if ([int]::TryParse($b.AccountNumber, [ref]$n) -and $n -ge $From -and $n -le $To) { $s -= [decimal]$b.Balance }
        }
        $s
    }
    $row = { param($group, $label, $value) [PSCustomObject]@{ Group = $group; Label = $label; Amount = [decimal]$value } }

    & $row 'NetSales' 'Nettoomsättning' (& $sum 3000 3799)
    & $row 'OtherOperatingRevenue' 'Övriga rörelseintäkter' (& $sum 3800 3999)
    & $row 'RawMaterials' 'Råvaror och förnödenheter' (& $sum 4000 4999)
    & $row 'OtherExternalExpenses' 'Övriga externa kostnader' (& $sum 5000 6999)
    & $row 'PersonnelCosts' 'Personalkostnader' (& $sum 7000 7699)
    & $row 'Depreciation' 'Av- och nedskrivningar av materiella och immateriella anläggningstillgångar' (& $sum 7700 7899)
    & $row 'OtherOperatingExpenses' 'Övriga rörelsekostnader' (& $sum 7900 7999)
    & $row 'OperatingResult' 'Rörelseresultat' (& $sum 3000 7999)
    & $row 'GroupCompanyResult' 'Resultat från andelar i koncernföretag' (& $sum 8000 8099)
    & $row 'AssociatedCompanyResult' 'Resultat från andelar i intresseföretag' (& $sum 8100 8199)
    & $row 'FinancialFixedAssetResult' 'Resultat från övriga finansiella anläggningstillgångar' (& $sum 8200 8299)
    & $row 'InterestIncome' 'Övriga ränteintäkter och liknande resultatposter' (& $sum 8300 8399)
    & $row 'InterestExpenses' 'Räntekostnader och liknande resultatposter' (& $sum 8400 8799)
    & $row 'ResultAfterFinancialItems' 'Resultat efter finansiella poster' (& $sum 3000 8799)
    & $row 'Appropriations' 'Bokslutsdispositioner' (& $sum 8800 8899)
    & $row 'ResultBeforeTax' 'Resultat före skatt' (& $sum 3000 8899)
    & $row 'Tax' 'Skatt på årets resultat' (& $sum 8900 8979)
    & $row 'OtherTaxes' 'Övriga skatter' (& $sum 8980 8998)
    & $row 'NetResult' 'Årets resultat' (& $sum 3000 8998)
}
function New-LedgerStatementTable {
    [CmdletBinding()]
    param (
        [Parameter()]
        [object[]]$Rows,

        [Parameter(Mandatory)]
        [string]$CurrentLabel,

        [Parameter()]
        [AllowNull()]
        [string]$ComparisonLabel,

        [Parameter(Mandatory)]
        [scriptblock]$Fmt,

        [Parameter()]
        [hashtable]$NoteMap = @{},

        # Groups rendered as summary rows (bold with a rule above).
        [Parameter()]
        [string[]]$SumGroups = @(),

        # Caption rows inserted before a group: @{ Before = 'Group'; Label = '...';
        # Groups = @(...) }. With Groups, the caption is only shown when at least
        # one of those groups is shown.
        [Parameter()]
        [object[]]$Sections = @(),

        # Omit rows whose amounts are zero in every year shown.
        [Parameter()]
        [switch]$HideZero,

        # Groups that are always shown, even with -HideZero.
        [Parameter()]
        [string[]]$KeepGroups = @()
    )

    $hasComparison = -not [string]::IsNullOrEmpty($ComparisonLabel)
    if ($hasComparison) {
        $header = @('', 'Not', $CurrentLabel, $ComparisonLabel)
        $align = @('left', 'left', 'right', 'right')
    }
    else {
        $header = @('', 'Not', $CurrentLabel)
        $align = @('left', 'left', 'right')
    }

    $isShown = @{}
    foreach ($r in $Rows) {
        $keep = $KeepGroups -contains $r.Group
        $zero = ([decimal]$r.Amount -eq 0) -and (-not $hasComparison -or $null -eq $r.ComparisonAmount -or [decimal]$r.ComparisonAmount -eq 0)
        $isShown[$r.Group] = $keep -or -not ($HideZero -and $zero)
    }

    $tableRows = @()
    $rowStyles = @()
    foreach ($r in $Rows) {
        foreach ($s in $Sections) {
            if ($s.Before -ne $r.Group) { continue }
            if ($s.Groups -and -not ($s.Groups | Where-Object { $isShown[$_] })) { continue }
            $tableRows += , @(@($s.Label) + (@('') * ($header.Count - 1)))
            $rowStyles += 'Section'
        }
        if (-not $isShown[$r.Group]) { continue }
        $noteRef = if ($NoteMap.ContainsKey($r.Group)) { [string]$NoteMap[$r.Group] } else { '' }
        if ($hasComparison) {
            $tableRows += , @($r.Label, $noteRef, (& $Fmt $r.Amount), (& $Fmt $r.ComparisonAmount))
        }
        else {
            $tableRows += , @($r.Label, $noteRef, (& $Fmt $r.Amount))
        }
        $rowStyles += if ($SumGroups -contains $r.Group) { 'Sum' } else { 'Normal' }
    }

    @{ Type = 'Table'; Header = $header; Align = $align; Rows = $tableRows; RowStyles = $rowStyles }
}
