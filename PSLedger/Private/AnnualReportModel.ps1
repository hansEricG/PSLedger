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
        @{ Label = 'Andra långfristiga värdepappersinnehav'; CostFrom = 1350; CostTo = 1359; DepFrom = $null; DepTo = $null }
    )

    $fixedAssetNotes = @()
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
    $blocks += @{ Type = 'Title'; Text = 'Årsredovisning' }
    $blocks += @{ Type = 'Paragraph'; Text = $heading }
    $blocks += @{ Type = 'Paragraph'; Text = "för räkenskapsåret $dateRange" }

    # Förvaltningsberättelse
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Förvaltningsberättelse' }
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
        $blocks += @{ Type = 'Table'; Header = @('', $currentLabel); Align = @('left', 'right'); Rows = $dispRows }
        $blocks += @{ Type = 'Paragraph'; Text = 'Styrelsen föreslår att medlen disponeras så att:' }
        $propRows = @()
        $propRows += , @('Utdelning', (& $fmt $disp.ProposedDividend))
        $propRows += , @('Balanseras i ny räkning', (& $fmt $disp.CarriedForward))
        $propRows += , @('Summa', (& $fmt $disp.TotalDisposable))
        $blocks += @{ Type = 'Table'; Header = @('', $currentLabel); Align = @('left', 'right'); Rows = $propRows }
        if ($null -ne $disp.DividendPerShare) {
            $blocks += @{ Type = 'Paragraph'; Text = ("Föreslagen utdelning per aktie: {0} kr (antal aktier: {1})." -f (& $fmt $disp.DividendPerShare), $disp.NumberOfShares) }
        }
    }

    # ---- Resultaträkning --------------------------------------------------------
    $income = @(Get-LedgerAnnualReport -JournalPath $JournalPath -FiscalYear $FiscalYear -NoComparison:$NoComparison |
            Where-Object { $_.Statement -eq 'IncomeStatement' })
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Resultaträkning' }
    $blocks += (New-LedgerStatementTable -Rows $income -CurrentLabel $currentLabel -ComparisonLabel $comparisonLabel -Fmt $fmt -NoteMap @{})

    # ---- Balansräkning (detailed) ----------------------------------------------
    $balCurrent = @(Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $FiscalYear -Detailed)
    $balPrev = @{}
    if ($comparisonYear) {
        foreach ($r in @(Get-LedgerBalanceSheet -JournalPath $JournalPath -FiscalYear $comparisonYear -Detailed)) {
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
        foreach ($eg in 'Equity', 'ShareCapital', 'RestrictedReserves', 'RetainedEarnings', 'BookedYearResult') {
            $balNoteMap[$eg] = $equityNoteNo
        }
    }
    $blocks += @{ Type = 'Heading'; Level = 1; Text = 'Balansräkning' }
    $blocks += (New-LedgerStatementTable -Rows $balRows -CurrentLabel $currentLabel -ComparisonLabel $comparisonLabel -Fmt $fmt -NoteMap $balNoteMap)

    # ---- Noter / Tilläggsupplysningar ------------------------------------------
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
            $rows += , @('Ingående avskrivningar', (& $fmt $n.OpeningDepreciation))
            $rows += , @('Årets avskrivningar', (& $fmt $n.YearDepreciation))
            $rows += , @('Utgående avskrivningar', (& $fmt $n.ClosingDepreciation))
        }
        $rows += , @('Redovisat värde', (& $fmt $n.BookValue))
        $blocks += @{ Type = 'Table'; Header = @('', $currentLabel); Align = @('left', 'right'); Rows = $rows }
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
        $blocks += @{ Type = 'Table'; Header = @('', 'Ingående balans', 'Förändring', 'Utgående balans'); Align = @('left', 'right', 'right', 'right'); Rows = $eqRows }
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
        foreach ($m in $profile.BoardMembers) {
            $blocks += @{ Type = 'Paragraph'; Text = $m }
        }
    }

    $blocks += @{ Type = 'Heading'; Level = 2; Text = 'Fastställelseintyg' }
    $blocks += @{ Type = 'Paragraph'; Text = 'Undertecknad intygar att resultaträkningen och balansräkningen har fastställts på årsstämma och att stämman beslutade godkänna styrelsens förslag till resultatdisposition.' }

    $blocks
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
        [hashtable]$NoteMap = @{}
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

    $tableRows = @()
    foreach ($r in $Rows) {
        $noteRef = if ($NoteMap.ContainsKey($r.Group)) { [string]$NoteMap[$r.Group] } else { '' }
        if ($hasComparison) {
            $tableRows += , @($r.Label, $noteRef, (& $Fmt $r.Amount), (& $Fmt $r.ComparisonAmount))
        }
        else {
            $tableRows += , @($r.Label, $noteRef, (& $Fmt $r.Amount))
        }
    }

    @{ Type = 'Table'; Header = $header; Align = $align; Rows = $tableRows }
}
