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

    $dateRange = if ($year) {
        "$(([datetime]$year.StartDate).ToString('yyyy-MM-dd')) - $(([datetime]$year.EndDate).ToString('yyyy-MM-dd'))"
    }
    else { $FiscalYear }

    # ---- Auto-detect notes and assign note numbers in appearance order ----------
    $assetGroups = @(
        @{ Label = 'Immateriella anläggningstillgångar'; CostFrom = 1000; CostTo = 1088; DepFrom = 1089; DepTo = 1099 }
        @{ Label = 'Byggnader och mark'; CostFrom = 1100; CostTo = 1118; DepFrom = 1119; DepTo = 1119 }
        @{ Label = 'Maskiner och andra tekniska anläggningar'; CostFrom = 1210; CostTo = 1218; DepFrom = 1219; DepTo = 1219 }
        @{ Label = 'Inventarier, verktyg och installationer'; CostFrom = 1220; CostTo = 1228; DepFrom = 1229; DepTo = 1229 }
        @{ Label = 'Andra långfristiga värdepappersinnehav'; CostFrom = 1350; CostTo = 1358; DepFrom = 1359; DepTo = 1359; DepLabel = 'nedskrivningar' }
    )

    $fixedAssetNotes = @()
    $fixedAssetDepLabels = @()
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
        }
    }

    $hasMarketValue = $null -ne $reportInput.SecuritiesMarketValue -and $reportInput.SecuritiesMarketValue -ne ''
    $shareholdingNote = $null
    if ($hasMarketValue) {
        $shareholdingNote = Get-LedgerShareholdingNote -JournalPath $JournalPath -FiscalYear $FiscalYear
    }

    $equityNote = @(Get-LedgerEquityReconciliation -JournalPath $JournalPath -FiscalYear $FiscalYear)

    # Numbered notes in balance-sheet appearance order: fixed assets, shareholding,
    # equity. Accounting principles and the employee note are unnumbered.
    $noteKeys = @()
    for ($i = 0; $i -lt $fixedAssetNotes.Count; $i++) { $noteKeys += "FixedAsset$i" }
    if ($shareholdingNote) { $noteKeys += 'Shareholding' }
    if ($equityNote) { $noteKeys += 'Equity' }
    $register = New-LedgerNoteRegister -NoteKey $noteKeys

    $firstFixedAssetNoteNo = if ($fixedAssetNotes.Count -gt 0) { Get-LedgerNoteNumber -Register $register -Key 'FixedAsset0' } else { $null }
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
        $blocks += @{ Type = 'Table'; Header = $ovHeader; Align = $ovAlign; Rows = $ovRows }
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

    # ---- Resultaträkning --------------------------------------------------------
    $income = @(Get-LedgerAnnualReport -JournalPath $JournalPath -FiscalYear $FiscalYear -NoComparison:$NoComparison |
            Where-Object { $_.Statement -eq 'IncomeStatement' })
    $blocks += @{ Type = 'PageBreak' }
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Resultaträkning' }
    $blocks += (New-LedgerStatementTable -Rows $income -CurrentLabel $currentLabel -ComparisonLabel $comparisonLabel -Fmt $fmt -NoteMap @{} `
            -SumGroups @('OperatingResult', 'ResultAfterFinancialItems', 'NetResult') -HideZero)

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
    if ($firstFixedAssetNoteNo) { $balNoteMap['FixedAssets'] = $firstFixedAssetNoteNo }
    if ($equityNoteNo) {
        foreach ($eg in 'Equity', 'ShareCapital', 'RestrictedReserves', 'RetainedEarnings', 'YearResult') {
            $balNoteMap[$eg] = $equityNoteNo
        }
    }
    $balSections = @(
        @{ Before = 'FixedAssets'; Label = 'TILLGÅNGAR' }
        @{ Before = 'Inventory'; Label = 'Omsättningstillgångar'; Groups = @('Inventory', 'AccountsReceivable', 'OtherReceivables', 'CashAndBank') }
        @{ Before = 'ShareCapital'; Label = 'EGET KAPITAL OCH SKULDER' }
        @{ Before = 'ShareCapital'; Label = 'Eget kapital' }
        @{ Before = 'CurrentTaxLiabilities'; Label = 'Kortfristiga skulder'; Groups = @('CurrentTaxLiabilities', 'OtherShortTermLiabilities') }
    )
    $blocks += @{ Type = 'PageBreak' }
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Balansräkning' }
    $blocks += (New-LedgerStatementTable -Rows $balRows -CurrentLabel $currentLabel -ComparisonLabel $comparisonLabel -Fmt $fmt -NoteMap $balNoteMap `
            -SumGroups @('TotalAssets', 'Equity', 'TotalEquityAndLiabilities') -Sections $balSections -HideZero)

    # ---- Noter / Tilläggsupplysningar ------------------------------------------
    $blocks += @{ Type = 'PageBreak' }
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Noter' }

    $blocks += @{ Type = 'Heading'; Level = 2; Text = 'Redovisnings- och värderingsprinciper' }
    foreach ($p in @(Get-LedgerAccountingPrinciples -AsLines)) {
        $blocks += @{ Type = 'Paragraph'; Text = $p }
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
        $no = Get-LedgerNoteNumber -Register $register -Key "FixedAsset$i"
        $blocks += @{ Type = 'Heading'; Level = 2; Text = "Not $no  $($n.Label)" }
        $rows = @()
        $rows += , @('Ingående anskaffningsvärde', (& $fmt $n.OpeningAcquisition))
        $rows += , @('Årets inköp', (& $fmt $n.Purchases))
        $rows += , @('Årets avyttringar', (& $fmt $n.Disposals))
        $rows += , @('Utgående anskaffningsvärde', (& $fmt $n.ClosingAcquisition))
        if ($n.HasDepreciation) {
            $depLabel = $fixedAssetDepLabels[$i]
            $rows += , @("Ingående $depLabel", (& $fmt $n.OpeningDepreciation))
            $rows += , @("Årets $depLabel", (& $fmt $n.YearDepreciation))
            $rows += , @("Utgående $depLabel", (& $fmt $n.ClosingDepreciation))
        }
        $rows += , @('Redovisat värde', (& $fmt $n.BookValue))
        $styles = foreach ($r in $rows) { if ($r[0] -like 'Utgående *' -or $r[0] -eq 'Redovisat värde') { 'Sum' } else { 'Normal' } }
        $blocks += @{ Type = 'Table'; Header = @('', $currentLabel); Align = @('left', 'right'); Rows = $rows; RowStyles = @($styles) }
    }

    # Shareholding note (numbered)
    if ($shareholdingNote) {
        $no = Get-LedgerNoteNumber -Register $register -Key 'Shareholding'
        $blocks += @{ Type = 'Heading'; Level = 2; Text = "Not $no  $($shareholdingNote.Label)" }
        $rows = @()
        $rows += , @('Bokfört värde', (& $fmt $shareholdingNote.BookValue))
        $rows += , @('Marknadsvärde', (& $fmt $shareholdingNote.MarketValue))
        $blocks += @{ Type = 'Table'; Header = @('', $currentLabel); Align = @('left', 'right'); Rows = $rows }
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
        $blocks += @{ Type = 'Paragraph'; Text = ($signLine -join ' ') }
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

    $bs = @(Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear -Detailed)
    if (-not $bs) { return }
    $amount = @{}
    foreach ($r in $bs) { $amount[$r.Group] = [decimal]$r.Amount }

    $eq = @{}
    foreach ($c in @(Get-LedgerEquityReconciliation -JournalPath $JournalPath -FiscalYear $FiscalYear)) {
        $eq[$c.Component] = [decimal]$c.ClosingBalance
    }
    $get = { param($h, $k) if ($h.ContainsKey($k)) { $h[$k] } else { [decimal]0 } }

    $row = { param($section, $group, $label, $value) [PSCustomObject]@{ Section = $section; Group = $group; Label = $label; Amount = [decimal]$value } }

    & $row 'Assets' 'FixedAssets' 'Anläggningstillgångar' (& $get $amount 'FixedAssets')
    & $row 'Assets' 'Inventory' 'Lager och pågående arbeten' (& $get $amount 'Inventory')
    & $row 'Assets' 'AccountsReceivable' 'Kundfordringar' (& $get $amount 'AccountsReceivable')
    & $row 'Assets' 'OtherReceivables' 'Övriga kortfristiga fordringar' (& $get $amount 'OtherReceivables')
    & $row 'Assets' 'CashAndBank' 'Likvida medel' (& $get $amount 'CashAndBank')
    & $row 'Assets' 'TotalAssets' 'Summa tillgångar' (& $get $amount 'TotalAssets')

    & $row 'EquityAndLiabilities' 'ShareCapital' 'Aktiekapital' (& $get $eq 'ShareCapital')
    & $row 'EquityAndLiabilities' 'RestrictedReserves' 'Bundna reserver' (& $get $eq 'RestrictedReserves')
    & $row 'EquityAndLiabilities' 'RetainedEarnings' 'Balanserat resultat' (& $get $eq 'RetainedEarnings')
    & $row 'EquityAndLiabilities' 'YearResult' 'Årets resultat' (& $get $eq 'YearResult')
    & $row 'EquityAndLiabilities' 'Equity' 'Summa eget kapital' (& $get $eq 'Total')
    & $row 'EquityAndLiabilities' 'UntaxedReserves' 'Obeskattade reserver och avsättningar' (-(& $get $amount 'UntaxedReserves'))
    & $row 'EquityAndLiabilities' 'LongTermLiabilities' 'Långfristiga skulder' (-(& $get $amount 'LongTermLiabilities'))
    & $row 'EquityAndLiabilities' 'CurrentTaxLiabilities' 'Aktuella skatteskulder' (-(& $get $amount 'CurrentTaxLiabilities'))
    & $row 'EquityAndLiabilities' 'OtherShortTermLiabilities' 'Övriga kortfristiga skulder' (-(& $get $amount 'OtherShortTermLiabilities'))
    & $row 'EquityAndLiabilities' 'TotalEquityAndLiabilities' 'Summa eget kapital och skulder' (-(& $get $amount 'TotalEquityAndLiabilities'))
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

        # Omit non-summary rows whose amounts are zero in every year shown.
        [Parameter()]
        [switch]$HideZero
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
        $isSum = $SumGroups -contains $r.Group
        $zero = ([decimal]$r.Amount -eq 0) -and (-not $hasComparison -or $null -eq $r.ComparisonAmount -or [decimal]$r.ComparisonAmount -eq 0)
        $isShown[$r.Group] = $isSum -or -not ($HideZero -and $zero)
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
