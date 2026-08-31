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
         income tax and any tax adjustments you supply, ending in the
         surplus/deficit (fields 8020/8021).

Amounts are reported in whole kronor (öre truncated per SFL 22:1), the
organisation number is written in the 12-digit form and the files use ISO-8859-1
encoding, all as the format requires. Årets resultat and total equity are
computed from the full account range, so the bottom line always ties out even
if an unusual account is not classified onto a specific räkenskapsschema line.

The surplus/deficit (INK2S 8020/8021 and INK2 7113/7114) defaults to
årets resultat plus the booked income tax. Supply -TaxAdjustment to add further
INK2S fields; each entry is written verbatim and, unless you specify 8020 or
8021 yourself, is added (with the sign you give) when computing the surplus.

Run this on a fiscal year whose result has not yet been appropriated into equity
(the normal workflow), the same way Get-LedgerIncomeStatement reports the
unclosed result.

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
journal metadata field 'PostalCode' when omitted.

.PARAMETER City
The submitter's city (postort). Required by INFO.SRU; falls back to the journal
metadata field 'City' when omitted.

.PARAMETER ContactPerson
Optional contact person written to INFO.SRU; falls back to the journal metadata
field 'ContactPerson'.

.PARAMETER Email
Optional contact e-mail written to INFO.SRU; falls back to the journal metadata
field 'Email'.

.PARAMETER TaxAdjustment
Optional hashtable of additional INK2S fields as SRU code to whole-krona amount,
e.g. @{ '7654' = 1200; '7663' = -5000 }. Each entry is written as an INK2S
#UPPGIFT line. Unless you include 8020 or 8021 yourself, the amounts are summed
(with their sign) into the surplus/deficit computation.

.PARAMETER Force
Overwrite existing INFO.SRU / BLANKETTER.SRU files in the destination directory.

.EXAMPLE
Export-LedgerIncomeTaxReturn -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Path .\sru -PostalCode '11122' -City 'Stockholm'

Writes .\sru\INFO.SRU and .\sru\BLANKETTER.SRU for the 2024 income year.

.EXAMPLE
Export-LedgerIncomeTaxReturn -JournalPath .\Konsult.ledger -FiscalYear '2024-01_2024-12' -Path C:\Deklaration -TaxAdjustment @{ '7654' = 940 } -Force

Exports the return, adding a schablonintäkt på periodiseringsfonder (SRU 7654)
of 940 kr to the tax adjustments and overwriting any existing files.
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
        # journal metadata. Postal code and city are mandatory in INFO.SRU.
        if (-not $PostalCode) { $PostalCode = [string]$journal.Metadata['PostalCode'] }
        if (-not $City) { $City = [string]$journal.Metadata['City'] }
        if (-not $ContactPerson) { $ContactPerson = [string]$journal.Metadata['ContactPerson'] }
        if (-not $Email) { $Email = [string]$journal.Metadata['Email'] }
        if (-not $PostalCode -or -not $City) {
            throw "INFO.SRU requires a postal code and city. Supply -PostalCode and -City, or set 'PostalCode' and 'City' in the journal metadata."
        }

        # Aggregate the trial balance into SRU field codes.
        $rules = @(Get-SruAccountRules)
        $balance = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)

        $sru = @{}
        $addSru = {
            param($code, $amount)
            $key = [int]$code
            if (-not $sru.ContainsKey($key)) { $sru[$key] = [decimal]0 }
            $sru[$key] += [decimal]$amount
        }

        $resultRaw = [decimal]0   # raw sum of P&L accounts (3000-8998)
        $bookedTax = [decimal]0   # raw sum of income-tax accounts (8900-8989)
        foreach ($row in $balance) {
            $acct = 0
            if (-not [int]::TryParse($row.AccountNumber, [ref]$acct)) { continue }
            $bal = [decimal]$row.Balance

            if ($acct -ge 3000 -and $acct -le 8998) { $resultRaw += $bal }
            if ($acct -ge 8900 -and $acct -le 8989) { $bookedTax += $bal }

            $rule = Resolve-SruAccountRule -Account $acct -Rules $rules
            if (-not $rule) { continue }
            switch ($rule.Kind) {
                'Asset' { & $addSru $rule.Sru $bal }       # debit-positive as-is
                'Debt' { & $addSru $rule.Sru (-$bal) }     # credit -> positive
                'Income' { & $addSru $rule.Sru (-$bal) }   # revenue+ / cost-
            }
        }

        # Årets resultat (profit positive) and the booked income tax add-back.
        $netResult = -$resultRaw
        $tax = $bookedTax

        # Fold the year's result into fritt eget kapital (7302) so the balance
        # sheet reflects total equity including årets resultat.
        if ($netResult -ne 0) { & $addSru 7302 $netResult }

        # INK2S surplus/deficit. Default: result + non-deductible booked tax.
        $userAdjustments = @{}
        if ($TaxAdjustment) {
            foreach ($k in $TaxAdjustment.Keys) {
                $userAdjustments[[int]$k] = [decimal]$TaxAdjustment[$k]
            }
        }
        $surplus = $netResult + $tax
        $explicitSurplus = $userAdjustments.Contains(8020) -or $userAdjustments.Contains(8021)
        if (-not $explicitSurplus) {
            foreach ($k in $userAdjustments.Keys) { $surplus += $userAdjustments[$k] }
        }

        # Whole kronor, öre truncated toward zero.
        function Format-SruAmount {
            param([decimal]$Value)
            [long][Math]::Truncate($Value)
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

        # INK2 huvudblankett
        & $openBlock "INK2-$period"
        if ($surplus -gt 0) { & $addUppgift 7113 $surplus }
        elseif ($surplus -lt 0) { & $addUppgift 7114 (-$surplus) }
        & $addBlk '#BLANKETTSLUT'

        # INK2R räkenskapsschema
        & $openBlock "INK2R-$period"
        foreach ($code in ($sru.Keys | Sort-Object)) {
            & $addUppgift $code $sru[$code]
        }
        & $addBlk '#BLANKETTSLUT'

        # INK2S skattemässiga justeringar
        & $openBlock "INK2S-$period"
        if ($netResult -gt 0) { & $addUppgift 7650 $netResult }
        elseif ($netResult -lt 0) { & $addUppgift 7750 (-$netResult) }
        & $addUppgift 7651 $tax
        foreach ($code in ($userAdjustments.Keys | Sort-Object)) {
            if ($code -eq 8020 -or $code -eq 8021) { continue }
            & $addUppgift $code $userAdjustments[$code]
        }
        if ($explicitSurplus) {
            if ($userAdjustments.Contains(8020)) { & $addUppgift 8020 $userAdjustments[8020] }
            if ($userAdjustments.Contains(8021)) { & $addUppgift 8021 $userAdjustments[8021] }
        }
        else {
            if ($surplus -gt 0) { & $addUppgift 8020 $surplus }
            elseif ($surplus -lt 0) { & $addUppgift 8021 (-$surplus) }
        }
        & $addBlk '#BLANKETTSLUT'
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
        }
    }
}
