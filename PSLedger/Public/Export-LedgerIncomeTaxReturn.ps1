<#
.SYNOPSIS
Exports a fiscal year as a Skatteverket SRU income tax return (INK2) for an
aktiebolag.

.DESCRIPTION
Writes the two files Skatteverket's filöverföringstjänst expects — INFO.SRU
(submitter metadata) and BLANKETTER.SRU (the declaration blocks) — into a
destination directory. The submission contains three blankett blocks:

  INK2R  Räkenskapsschema — balance sheet and income statement, derived
         automatically from the trial balance via the official BAS-to-SRU
         mapping.
  INK2   Huvudblankett — the fiscal year dates and the surplus/deficit of
         business activity (överskott/underskott av näringsverksamhet).
  INK2S  Skattemässiga justeringar — årets resultat, the non-deductible booked
         income tax and the tax adjustments, ending in the surplus/deficit
         (4.15/4.16).

Field codes, rows and printed signs follow Skatteverket's fältnamnstabeller
for INK2/INK2R/INK2S and the account ranges follow BAS-kontogruppen's official
kopplingstabell. Amounts are written as they appear on the paper form: the
row's printed sign carries the direction, so costs, deductions and a loss are
positive. A negative amount only occurs where the value goes against the
printed sign, e.g. a booked tax income on 3.25 and 4.3a. Income statement rows
split into a (+) and a (-) field (3.2, 3.12-3.15, 3.23, 3.24) get the field
matching the row's net amount.

Amounts are reported in whole kronor (öre truncated per SFL 22:1), the
organisation number is written in the 12-digit form and the files use ISO-8859-1
encoding, all as the format requires. Årets resultat (3.26/3.27, and 4.1/4.2 on
INK2S) is the signed sum of the truncated income statement rows, and fritt eget
kapital (2.28) is the balancing figure of the truncated balance sheet, so both
statements tie out to the krona. Fritt eget kapital includes årets resultat
whether or not the closing entry (8999/2099) has been booked. A debit balance on
a skatteskulder account (25xx) is reported as a receivable (2.21) and a credit
balance on the skattekonto (163x) as a skatteskuld (2.49).

The surplus/deficit (INK2S 4.15/4.16 and INK2 1.1/1.2) is årets resultat plus
the booked income tax (4.3a) plus every INK2S adjustment with its printed sign;
the information-only rows 4.17-4.22 do not count. Adjustments that follow from
the BAS account itself are derived automatically:

  4.3c (7653)  non-deductible costs: 6072, 6982, 6992, 7622, 7632 and 8423
               (ränta på skattekontot)
  4.5c (7754)  non-taxable income: 8314 skattefria ränteintäkter
  4.3b (7652)  net write-downs of shares in other companies (8270-8289),
               assumed non-deductible; a net reversal goes to 4.5c (7754)

The write-down rule assumes kapitalplaceringsaktier and emits a warning
whenever it applies. Supply -TaxAdjustment to add further INK2S fields or to
replace a derived amount (an entry for the same field wins; give 0 to remove
it), or -NoAutomaticAdjustment to derive nothing. An explicit 4.15/4.16
overrides the computed surplus on both INK2S and the INK2 huvudblankett.

The returned object's Fields property lists every written field with its row
on the form (Box), SRU code, amount and description, so the values can be
copied straight onto the paper or e-service form.
Run this on a fiscal year either before or after the result has been
appropriated into equity (8999/2099); the export is the same in both cases.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12'). If omitted, uses the
current fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER Path
Destination directory for the INFO.SRU and BLANKETTER.SRU files. Created if it
does not exist.

.PARAMETER PostalCode
The submitter's postal code (postnummer). Required by INFO.SRU; falls back to the
journal metadata field 'PostalCode', and then to the postal code in the
metadata field 'Address' (e.g. 'Storgatan 1, 111 22 Stockholm, Sweden'), whose
street part is also written to INFO.SRU as #ADRESS.

.PARAMETER City
The submitter's city (postort). Required by INFO.SRU; falls back to the journal
metadata field 'City', and then to the city in the metadata field 'Address'.

.PARAMETER ContactPerson
Optional contact person written to INFO.SRU; falls back to the journal metadata
field 'ContactPerson'.

.PARAMETER Email
Optional contact e-mail written to INFO.SRU; falls back to the journal metadata
field 'Email'.

.PARAMETER TaxAdjustment
Optional hashtable of additional INK2S fields to whole-krona amount. Each key
is either the row on the form, e.g. '4.3b' or '4.6a', or its SRU code, e.g.
'7652'. Rows split into a (+) and a (-) field need the suffix: '4.13+' or
'4.13-'. Example: @{ '4.6a' = 1200; '4.5c' = 395 }. Each entry replaces any
automatically derived amount for the same field (use 0 to remove a derived
field). Give amounts as they appear on the form (positive); fields that
Skatteverket only accepts as positive throw on a negative amount. Årets
resultat (4.1/4.2) always comes from the books and cannot be supplied.

.PARAMETER NoAutomaticAdjustment
Do not derive any INK2S adjustments from the trial balance; only årets
resultat, the booked tax (4.3a) and -TaxAdjustment are used.

.PARAMETER ConsultantAssisted
Answers the INK2S question whether an uppdragstagare (e.g. a
redovisningskonsult) has assisted in preparing the annual report: $true
writes Ja (SRU 8040), $false writes Nej (SRU 8041). Omit to leave the question
unanswered.

.PARAMETER Audited
Answers the INK2S question whether the annual report has been audited
(varit föremål för revision): $true writes Ja (SRU 8044), $false writes Nej
(SRU 8045). Omit to leave the question unanswered.

.PARAMETER Force
Overwrite existing INFO.SRU / BLANKETTER.SRU files in the destination directory.

.EXAMPLE
Export-LedgerIncomeTaxReturn -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Path .\sru -PostalCode '11122' -City 'Stockholm'

Writes .\sru\INFO.SRU and .\sru\BLANKETTER.SRU for the 2024 income year.

.EXAMPLE
Export-LedgerIncomeTaxReturn -JournalPath .\Konsult.ledger -FiscalYear '2024-01_2024-12' -Path C:\Deklaration -TaxAdjustment @{ '4.6a' = 940 } -Force

Exports the return, adding a schablonintäkt på periodiseringsfonder (INK2S
4.6a, SRU 7654) of 940 kr to the tax adjustments and overwriting any existing files.

.EXAMPLE
Export-LedgerIncomeTaxReturn -JournalPath .\AktiehandelNord.ledger -FiscalYear '2024-01_2024-12' -Path .\sru -TaxAdjustment @{ '4.3b' = 0 }

Aktiehandel Nord AB trades in shares, so the write-down booked on 8271 concerns
lageraktier and is deductible; the automatically derived 4.3b add-back
(SRU 7652) is removed.

.EXAMPLE
(Export-LedgerIncomeTaxReturn -JournalPath .\MinFirma.ledger -FiscalYear '2025-09_2026-08' -Path .\sru -Force).Fields | Format-Table

Exports the return and lists every field with its row on the form (e.g. 3.7,
4.3a, 4.15), SRU code and amount, ready to copy onto the declaration.

.EXAMPLE
Export-LedgerIncomeTaxReturn -JournalPath .\Grönlund.ledger -FiscalYear '2025-09_2026-08' -Path .\sru -ConsultantAssisted $false -Audited $false

Grönlund Konsult AB prepared its annual report itself and has no auditor, so
Nej is answered to both questions at the bottom of INK2S (SRU 8041 and 8045).
#>
function Export-LedgerIncomeTaxReturn {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$PostalCode,

        [Parameter()]
        [string]$City,

        [Parameter()]
        [string]$ContactPerson,

        [Parameter()]
        [string]$Email,

        [Parameter()]
        [hashtable]$TaxAdjustment,

        [switch]$NoAutomaticAdjustment,

        [Parameter()]
        [Nullable[bool]]$ConsultantAssisted,

        [Parameter()]
        [Nullable[bool]]$Audited,

        [switch]$Force
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $journal = Get-LedgerJournal -Path $JournalPath
        if (-not $journal.OrgNumber) {
            throw "Journal has no OrgNumber; set one with Set-LedgerJournal before exporting an SRU return."
        }
        $orgNr = ConvertTo-SruOrgNr -OrgNumber $journal.OrgNumber

        $year = Get-LedgerFiscalYear -JournalPath $JournalPath | Where-Object { $_.Name -eq $FiscalYear }
        if (-not $year) {
            throw "Fiscal year year.txt missing for $FiscalYear"
        }
        $startDate = [datetime]$year.StartDate
        $endDate = [datetime]$year.EndDate

        # Submitter metadata: parameters win, otherwise fall back to free-form
        # journal metadata. Postal code and city are mandatory in INFO.SRU;
        # when 'PostalCode'/'City' are not set they are parsed from 'Address'
        # (e.g. 'Storgatan 1, 111 22 Stockholm, Sweden'), whose street part is
        # also written as the optional #ADRESS.
        $street = $null
        $address = [string]$journal.Metadata['Address']
        if ($address) {
            $segments = @($address -split ',' | ForEach-Object Trim | Where-Object { $_ })
            for ($i = 0; $i -lt $segments.Count; $i++) {
                if ($segments[$i] -match '^(?:SE-?\s?)?(\d{3}\s?\d{2})\s+(.+)$') {
                    if (-not $PostalCode -and -not $journal.Metadata['PostalCode']) { $PostalCode = $Matches[1] }
                    if (-not $City -and -not $journal.Metadata['City']) { $City = $Matches[2] }
                    if ($i -gt 0) { $street = $segments[0..($i - 1)] -join ', ' }
                    break
                }
            }
        }
        if (-not $PostalCode) { $PostalCode = [string]$journal.Metadata['PostalCode'] }
        if (-not $City) { $City = [string]$journal.Metadata['City'] }
        if (-not $ContactPerson) { $ContactPerson = [string]$journal.Metadata['ContactPerson'] }
        if (-not $Email) { $Email = [string]$journal.Metadata['Email'] }
        if (-not $PostalCode -or -not $City) {
            throw "INFO.SRU requires a postal code and city. Supply -PostalCode and -City, or set 'PostalCode' and 'City' (or an 'Address' such as 'Storgatan 1, 111 22 Stockholm') in the journal metadata."
        }

        # Whole kronor, öre truncated toward zero.
        function Format-SruAmount {
            param([decimal]$Value)
            [long][Math]::Truncate($Value)
        }

        $fieldDefs = @(Get-SruFieldDefinitions)
        $fieldByCode = @{}
        foreach ($f in $fieldDefs) { $fieldByCode[$f.Code] = $f }
        $rowOf = { param($code) $fieldByCode[[int]$code].Box.TrimEnd('+', '-') }

        # Aggregate the trial balance: balance sheet accounts per SRU code,
        # income statement accounts per form row (income positive).
        $rules = @(Get-SruAccountRules)
        $balance = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)

        $sru = @{}
        $addSru = {
            param($code, $amount)
            $key = [int]$code
            if (-not $sru.ContainsKey($key)) { $sru[$key] = [decimal]0 }
            $sru[$key] += [decimal]$amount
        }

        $incomeRows = [ordered]@{}
        $bookedTax = [decimal]0   # debit balance of income-tax accounts (8900-8989)
        foreach ($row in $balance) {
            $acct = 0
            if (-not [int]::TryParse($row.AccountNumber, [ref]$acct)) { continue }
            $bal = [decimal]$row.Balance

            if ($acct -ge 8900 -and $acct -le 8989) { $bookedTax += $bal }

            $rule = Resolve-SruAccountRule -Account $acct -Rules $rules
            if (-not $rule) { continue }
            switch ($rule.Kind) {
                'Asset' {
                    # debit-positive as-is; a credit balance may move to AltSru
                    if ($rule.AltSru -and $bal -lt 0) { & $addSru $rule.AltSru (-$bal) }
                    else { & $addSru $rule.Sru $bal }
                }
                'Debt' {
                    # credit -> positive; a debit balance may move to AltSru
                    if ($rule.AltSru -and $bal -gt 0) { & $addSru $rule.AltSru $bal }
                    else { & $addSru $rule.Sru (-$bal) }
                }
                'Income' {
                    $rowKey = & $rowOf $(if ($rule.Sru) { $rule.Sru } else { $rule.MinusSru })
                    if (-not $incomeRows.Contains($rowKey)) {
                        $incomeRows[$rowKey] = [PSCustomObject]@{ Plus = $null; Minus = $null; Net = [decimal]0 }
                    }
                    $line = $incomeRows[$rowKey]
                    if ($rule.Sru -and -not $line.Plus) { $line.Plus = $rule.Sru }
                    if ($rule.MinusSru -and -not $line.Minus) { $line.Minus = $rule.MinusSru }
                    $line.Net += (-$bal)
                }
            }
        }

        # Each income statement row is reported as it appears on the form:
        # the net goes to the row's (+) field when positive and to its (-)
        # field as a positive amount when negative. A row with a single field
        # reports the net against that field's printed sign.
        foreach ($line in $incomeRows.Values) {
            $net = [decimal](Format-SruAmount -Value $line.Net)
            if ($net -eq 0) { continue }
            if ($line.Plus -and ($net -gt 0 -or -not $line.Minus)) { & $addSru $line.Plus $net }
            else { & $addSru $line.Minus (-$net) }
        }

        # Report whole kronor per field, and derive the totals from the
        # truncated lines so the form ties out exactly: årets resultat is the
        # signed sum of the income statement rows, and fritt eget kapital (7302)
        # is the balancing figure of the balance sheet. That includes årets
        # resultat whether or not the closing entry 8999/2099 has been booked.
        $codes = @($sru.Keys)
        foreach ($code in $codes) { $sru[$code] = [decimal](Format-SruAmount -Value $sru[$code]) }
        $netResult = [decimal]0
        $assetTotal = [decimal]0
        $otherEquityLiab = [decimal]0
        foreach ($code in $codes) {
            if ($code -ge 7400) {
                if ($fieldByCode[$code].Sign -eq '-') { $netResult -= $sru[$code] }
                else { $netResult += $sru[$code] }
            }
            elseif ($code -lt 7300) { $assetTotal += $sru[$code] }
            elseif ($code -ne 7302) { $otherEquityLiab += $sru[$code] }
        }
        $freeEquity = $assetTotal - $otherEquityLiab
        if ($freeEquity -ne 0) { $sru[7302] = $freeEquity }
        else { $sru.Remove(7302) }

        # Årets resultat is also the closing line of the INK2R income statement
        # (3.26 vinst / 3.27 förlust), both reported as positive amounts.
        if ($netResult -gt 0) { & $addSru 7450 $netResult }
        elseif ($netResult -lt 0) { & $addSru 7550 (-$netResult) }

        # The booked income tax (non-deductible) is added back on INK2S 4.3a;
        # a booked tax income gives a negative 4.3a.
        $tax = [decimal](Format-SruAmount -Value $bookedTax)

        # The caller's -TaxAdjustment keys may be a row on the form ('4.3b')
        # or an SRU code ('7652').
        $explicit = @{}
        if ($TaxAdjustment) {
            foreach ($k in $TaxAdjustment.Keys) {
                $field = Resolve-SruInk2sField -Key ([string]$k) -Fields $fieldDefs
                $explicit[[int]$field.Code] = [decimal]$TaxAdjustment[$k]
            }
        }

        # INK2S adjustments derived from the trial balance (unless disabled),
        # then the caller's entries, which replace the derived amount for the
        # same field.
        $userAdjustments = @{}
        if (-not $NoAutomaticAdjustment) {
            $adjRules = @(Get-SruTaxAdjustmentRules)
            $ruleNet = @{}
            foreach ($row in $balance) {
                $acct = 0
                if (-not [int]::TryParse($row.AccountNumber, [ref]$acct)) { continue }
                foreach ($adjRule in $adjRules) {
                    if ($acct -ge $adjRule.Min -and $acct -le $adjRule.Max) {
                        if (-not $ruleNet.ContainsKey($adjRule)) { $ruleNet[$adjRule] = [decimal]0 }
                        $ruleNet[$adjRule] += [decimal]$row.Balance
                        break
                    }
                }
            }
            foreach ($adjRule in $adjRules) {
                if (-not $ruleNet.ContainsKey($adjRule)) { continue }
                $net = $ruleNet[$adjRule]
                $code = if ($net -gt 0) { $adjRule.DebitSru } elseif ($net -lt 0) { $adjRule.CreditSru } else { $null }
                if (-not $code) { continue }
                $amount = [decimal](Format-SruAmount -Value ([Math]::Abs($net)))
                if ($amount -eq 0) { continue }
                if ($adjRule.Assumption -and -not $explicit.ContainsKey([int]$code)) {
                    $box = $fieldByCode[[int]$code].Box
                    $what = if ($net -gt 0) { "write-downs of $amount kr treated as non-deductible (INK2S $box, SRU $code)" }
                    else { "reversals of $amount kr treated as non-taxable (INK2S $box, SRU $code)" }
                    Write-Warning ("Accounts $($adjRule.Min)-$($adjRule.Max) ($($adjRule.Label)): $what. " +
                        'This assumes the shares are kapitalplaceringsaktier. For lageraktier or other deductible ' +
                        "write-downs, override with -TaxAdjustment @{ '$box' = <amount> } or use -NoAutomaticAdjustment.")
                }
                if (-not $userAdjustments.ContainsKey([int]$code)) { $userAdjustments[[int]$code] = [decimal]0 }
                $userAdjustments[[int]$code] += $amount
            }
        }
        foreach ($code in $explicit.Keys) {
            if ($code -eq 7651) { $tax = $explicit[$code] }
            else { $userAdjustments[$code] = $explicit[$code] }
        }

        # INK2S surplus/deficit: result + booked tax (4.3a) + every adjustment
        # with its printed sign. Information-only fields (4.17-4.22) do not
        # count. An explicit 4.15/4.16 (7670/7770) overrides the computation.
        $surplus = $netResult + $tax
        foreach ($code in $userAdjustments.Keys) {
            if ($code -in 7670, 7770) { continue }
            switch ($fieldByCode[$code].Sign) {
                '+' { $surplus += $userAdjustments[$code] }
                '-' { $surplus -= $userAdjustments[$code] }
            }
        }
        if ($userAdjustments.ContainsKey(7670) -or $userAdjustments.ContainsKey(7770)) {
            $surplus = [decimal]0
            if ($userAdjustments.ContainsKey(7670)) { $surplus += $userAdjustments[7670] }
            if ($userAdjustments.ContainsKey(7770)) { $surplus -= $userAdjustments[7770] }
        }

        # Assemble every field per blankett, in form order.
        $ink2 = @{}
        if ($surplus -gt 0) { $ink2[7104] = $surplus }
        elseif ($surplus -lt 0) { $ink2[7114] = -$surplus }

        $ink2s = @{}
        if ($netResult -gt 0) { $ink2s[7650] = $netResult }
        elseif ($netResult -lt 0) { $ink2s[7750] = -$netResult }
        $ink2s[7651] = $tax
        foreach ($code in $userAdjustments.Keys) {
            if ($code -notin 7670, 7770) { $ink2s[$code] = $userAdjustments[$code] }
        }
        if ($surplus -gt 0) { $ink2s[7670] = $surplus }
        elseif ($surplus -lt 0) { $ink2s[7770] = -$surplus }

        $formValues = @{ INK2 = $ink2; INK2R = $sru; INK2S = $ink2s }
        $fields = foreach ($def in $fieldDefs) {
            $values = $formValues[$def.Form]
            if (-not $values.ContainsKey($def.Code)) { continue }
            $amount = [long](Format-SruAmount -Value $values[$def.Code])
            if ($amount -eq 0) { continue }
            if ($def.NonNegative -and $amount -lt 0) {
                throw "$($def.Form) $($def.Box) (SRU $($def.Code), $($def.Description)) cannot be negative ($amount); Skatteverket only accepts positive amounts in this field."
            }
            [PSCustomObject]@{
                Form        = $def.Form
                Box         = $def.Box
                SruCode     = $def.Code
                Amount      = $amount
                Description = $def.Description
            }
        }
        $fields = @($fields)

        # Ja/Nej questions at the bottom of INK2S, reported as the value 'X'
        # in the field for the chosen answer (data type Str_X).
        $question = 'Uppdragstagare (t.ex. redovisningskonsult) har biträtt vid upprättandet av årsredovisningen'
        if ($null -ne $ConsultantAssisted) {
            $fields += [PSCustomObject]@{
                Form = 'INK2S'; Box = ''; SruCode = $(if ($ConsultantAssisted) { 8040 } else { 8041 }); Amount = 'X'
                Description = "${question}: $(if ($ConsultantAssisted) { 'Ja' } else { 'Nej' })"
            }
        }
        if ($null -ne $Audited) {
            $fields += [PSCustomObject]@{
                Form = 'INK2S'; Box = ''; SruCode = $(if ($Audited) { 8044 } else { 8045 }); Amount = 'X'
                Description = "Årsredovisningen har varit föremål för revision: $(if ($Audited) { 'Ja' } else { 'Nej' })"
            }
        }

        $stamp = Get-Date
        $genDate = $stamp.ToString('yyyyMMdd')
        $genTime = $stamp.ToString('HHmmss')
        $startStr = $startDate.ToString('yyyyMMdd')
        $endStr = $endDate.ToString('yyyyMMdd')
        $incomeYear = $endDate.Year
        $period = "$incomeYear$(Get-SruPeriodSuffix -EndMonth $endDate.Month)"
        $moduleVersion = (Get-Module PSLedger).Version.ToString()
        $name = $journal.Name

        $nl = "`r`n"

        # --- INFO.SRU --------------------------------------------------------
        $info = New-Object System.Text.StringBuilder
        $addInfo = { param($line) [void]$info.Append($line); [void]$info.Append($nl) }
        & $addInfo '#DATABESKRIVNING_START'
        & $addInfo '#PRODUKT SRU'
        & $addInfo "#SKAPAD $genDate $genTime"
        & $addInfo "#PROGRAM PSLedger $moduleVersion"
        & $addInfo '#FILNAMN BLANKETTER.SRU'
        & $addInfo '#DATABESKRIVNING_SLUT'
        & $addInfo '#MEDIELEV_START'
        & $addInfo "#ORGNR $orgNr"
        & $addInfo "#NAMN $name"
        if ($street) { & $addInfo "#ADRESS $street" }
        & $addInfo "#POSTNR $($PostalCode -replace '\s', '')"
        & $addInfo "#POSTORT $City"
        if ($ContactPerson) { & $addInfo "#KONTAKT $ContactPerson" }
        if ($Email) { & $addInfo "#EMAIL $Email" }
        & $addInfo '#MEDIELEV_SLUT'

        # --- BLANKETTER.SRU --------------------------------------------------
        $blk = New-Object System.Text.StringBuilder
        $addBlk = { param($line) [void]$blk.Append($line); [void]$blk.Append($nl) }
        $addUppgift = {
            param($code, $value)
            $v = Format-SruAmount -Value $value
            if ($v -ne 0) { & $addBlk "#UPPGIFT $code $v" }
        }
        $openBlock = {
            param($blankettType)
            & $addBlk "#BLANKETT $blankettType"
            & $addBlk "#IDENTITET $orgNr $genDate $genTime"
            & $addBlk "#NAMN $name"
            & $addBlk "#UPPGIFT 7011 $startStr"
            & $addBlk "#UPPGIFT 7012 $endStr"
        }

        foreach ($form in 'INK2', 'INK2R', 'INK2S') {
            & $openBlock "$form-$period"
            foreach ($f in ($fields | Where-Object Form -eq $form | Sort-Object SruCode)) {
                if ($f.Amount -is [string]) { & $addBlk "#UPPGIFT $($f.SruCode) $($f.Amount)" }
                else { & $addUppgift $f.SruCode $f.Amount }
            }
            & $addBlk '#BLANKETTSLUT'
        }
        & $addBlk '#FIL_SLUT'

        # --- Write both files ------------------------------------------------
        $DestDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not (Test-Path -LiteralPath $DestDir)) {
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        }
        $infoPath = Join-Path $DestDir 'INFO.SRU'
        $blkPath = Join-Path $DestDir 'BLANKETTER.SRU'
        foreach ($p in $infoPath, $blkPath) {
            if ((Test-Path -LiteralPath $p) -and -not $Force) {
                throw "Destination file already exists: $p. Use -Force to overwrite."
            }
        }

        $encoding = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
        [System.IO.File]::WriteAllText($infoPath, $info.ToString(), $encoding)
        [System.IO.File]::WriteAllText($blkPath, $blk.ToString(), $encoding)

        [PSCustomObject]@{
            InfoPath        = $infoPath
            BlanketterPath  = $blkPath
            OrgNumber       = $orgNr
            Period          = $period
            NetResult       = [long][Math]::Truncate($netResult)
            SurplusDeficit  = [long][Math]::Truncate($surplus)
            TaxAdjustments  = $userAdjustments
            Fields          = $fields
        }
    }
}
