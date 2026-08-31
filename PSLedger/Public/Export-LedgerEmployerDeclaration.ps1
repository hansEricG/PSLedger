<#
.SYNOPSIS
Exports an employer declaration on individual level (arbetsgivardeklaration på
individnivå, AGI) as a Skatteverket XML file.

.DESCRIPTION
Aggregates the posted payslips whose pay date falls in a reporting period (a
calendar month, YYYYMM) and writes an AGI XML file that can be uploaded in
Skatteverket's e-service for employer declarations (Lämna arbetsgivardeklaration
via fil).

The file conforms to Skatteverket's AGI schema. It contains an <Avsandare>
(sender) block, a <Blankettgemensamt> (employer) block, one HU (huvuduppgift)
form with the period totals and one IU (individuppgift) form per employee:

  HU  SummaSkatteavdr (faltkod 497)  — total withheld preliminary tax
      SummaArbAvgSlf  (faltkod 487)  — total employer contributions
  IU  BetalningsmottagarId    (215)  — the employee's personal number
      Specifikationsnummer    (570)  — a per-employee specification number
      KontantErsattningUlagAG (011)  — gross cash salary
      AvdrPrelSkatt           (001)  — withheld preliminary tax

Amounts are reported in whole kronor (truncated), and the HU totals are the sum
of the per-employee whole-krona amounts so the declaration reconciles. Only
payslips with the status Booked are included; an employee must have a personal
number in the employee register (Add-LedgerEmployee -PersonalNumber). The file is
written with UTF-8 encoding.

The sender and contact details default to the journal's OrgNumber and the
ContactName, ContactPhone and ContactEmail metadata fields (set them with
Set-LedgerJournal), and can be overridden with the corresponding parameters.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Period
The reporting period as YYYYMM (e.g. '202403'). Payslips whose pay date is in this
month are included.

.PARAMETER Path
Destination path for the AGI XML file. Conventionally uses the .xml extension.

.PARAMETER ContactName
The contact person's name. Defaults to the journal's ContactName metadata field.

.PARAMETER ContactPhone
The contact person's phone number. Defaults to the journal's ContactPhone
metadata field.

.PARAMETER ContactEmail
The contact person's e-mail address. Defaults to the journal's ContactEmail
metadata field.

.PARAMETER ProgramName
The program name reported to Skatteverket. Defaults to 'PSLedger'.

.PARAMETER Force
Overwrite the destination file if it already exists.

.EXAMPLE
Export-LedgerEmployerDeclaration -JournalPath .\MinFirma.ledger -Period '202403' -Path .\agi-2024-03.xml

Exports the March 2024 employer declaration for all employees paid that month.

.EXAMPLE
Export-LedgerEmployerDeclaration -Period '202406' -Path C:\AGI\konsult-2024-06.xml -ContactName 'Anna Andersson' -ContactPhone '08-123456' -ContactEmail 'anna@konsult.se' -Force

Exports the June 2024 declaration with explicit contact details, overwriting any
existing file.
#>
function Export-LedgerEmployerDeclaration {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{6}$')]
        [string]$Period,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$ContactName,

        [Parameter()]
        [string]$ContactPhone,

        [Parameter()]
        [string]$ContactEmail,

        [Parameter()]
        [string]$ProgramName = 'PSLedger',

        [switch]$Force
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    $DestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ((Test-Path -LiteralPath $DestPath) -and -not $Force) {
        throw "Destination file already exists: $DestPath. Use -Force to overwrite."
    }

    $journal = Get-LedgerJournal -Path $JournalPath
    if (-not $journal.OrgNumber) {
        throw "Journal has no OrgNumber; set one with Set-LedgerJournal before exporting an employer declaration."
    }

    # Normalise an org number or personal number to Skatteverket's 12-digit
    # IDENTITET form: 12 digits are used as-is, a 10-digit org number is prefixed
    # with '16' as Skatteverket requires for Swedish companies.
    $toIdentitet = {
        param($raw, $label)
        $digits = ($raw -replace '\D', '')
        switch ($digits.Length) {
            12 { return $digits }
            10 { return "16$digits" }
            default { throw "Invalid $label '$raw': expected a Swedish org number or personal number (10 or 12 digits)." }
        }
    }

    $orgIdentitet = & $toIdentitet $journal.OrgNumber 'organisationsnummer'

    if (-not $ContactName) { $ContactName = [string]$journal.Metadata['ContactName'] }
    if (-not $ContactPhone) { $ContactPhone = [string]$journal.Metadata['ContactPhone'] }
    if (-not $ContactEmail) { $ContactEmail = [string]$journal.Metadata['ContactEmail'] }

    # Collect the posted payslips for the period and aggregate per employee.
    $payslips = @(Get-LedgerPayslip -JournalPath $JournalPath -Status Booked |
        Where-Object { $_.PayDate -and $_.PayDate.ToString('yyyyMM') -eq $Period })
    if ($payslips.Count -eq 0) {
        throw "No booked payslips found with a pay date in period $Period."
    }

    $employees = @{}
    foreach ($e in @(Get-LedgerEmployee -JournalPath $JournalPath)) {
        $employees[$e.EmployeeNumber] = $e
    }

    $truncate = { param($v) [long][Math]::Truncate([decimal]$v) }

    $individuals = New-Object System.Collections.Generic.List[object]
    foreach ($group in ($payslips | Group-Object EmployeeNumber | Sort-Object Name)) {
        $employee = $employees[$group.Name]
        if (-not $employee) {
            throw "Payslip refers to unknown employee '$($group.Name)'. Add the employee with Add-LedgerEmployee before exporting."
        }
        if (-not $employee.PersonalNumber) {
            throw "Employee '$($group.Name)' ($($employee.Name)) has no personal number. Set one with Set-LedgerEmployee -PersonalNumber before exporting."
        }

        $gross = ($group.Group | Measure-Object -Property GrossSalary -Sum).Sum
        $tax = ($group.Group | Measure-Object -Property TaxAmount -Sum).Sum
        $employer = ($group.Group | Measure-Object -Property EmployerContribution -Sum).Sum

        $individuals.Add([PSCustomObject]@{
            EmployeeNumber       = $group.Name
            PersonalNumber       = & $toIdentitet $employee.PersonalNumber "personnummer for employee '$($group.Name)'"
            GrossSalary          = & $truncate $gross
            TaxWithheld          = & $truncate $tax
            EmployerContribution = & $truncate $employer
            SpecificationNumber  = $individuals.Count + 1
        })
    }

    # HU totals reconcile with the per-employee whole-krona amounts.
    $totalTax = ($individuals | Measure-Object -Property TaxWithheld -Sum).Sum
    $totalEmployer = ($individuals | Measure-Object -Property EmployerContribution -Sum).Sum

    $instansNs = 'http://xmls.skatteverket.se/se/skatteverket/da/instans/schema/1.1'
    $komponentNs = 'http://xmls.skatteverket.se/se/skatteverket/da/komponent/schema/1.1'
    $createdAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')

    $escapeXml = {
        param($text)
        [System.Security.SecurityElement]::Escape([string]$text)
    }

    $sb = New-Object System.Text.StringBuilder
    $nl = "`r`n"
    $append = {
        param($line)
        [void]$sb.Append($line)
        [void]$sb.Append($nl)
    }

    & $append '<?xml version="1.0" encoding="UTF-8"?>'
    & $append "<Skatteverket omrade=""Arbetsgivardeklaration"" xmlns=""$instansNs"" xmlns:gem=""$komponentNs"">"

    # Sender (Avsandare).
    & $append '  <gem:Avsandare>'
    & $append "    <gem:Programnamn>$(& $escapeXml $ProgramName)</gem:Programnamn>"
    & $append "    <gem:Organisationsnummer>$orgIdentitet</gem:Organisationsnummer>"
    & $append '    <gem:TekniskKontaktperson>'
    & $append "      <gem:Namn>$(& $escapeXml $ContactName)</gem:Namn>"
    & $append "      <gem:Telefon>$(& $escapeXml $ContactPhone)</gem:Telefon>"
    & $append "      <gem:Epostadress>$(& $escapeXml $ContactEmail)</gem:Epostadress>"
    & $append '    </gem:TekniskKontaktperson>'
    & $append "    <gem:Skapad>$createdAt</gem:Skapad>"
    & $append '  </gem:Avsandare>'

    # Employer common data (Blankettgemensamt).
    & $append '  <gem:Blankettgemensamt>'
    & $append '    <gem:Arbetsgivare>'
    & $append "      <gem:AgRegistreradId>$orgIdentitet</gem:AgRegistreradId>"
    & $append '      <gem:Kontaktperson>'
    & $append "        <gem:Namn>$(& $escapeXml $ContactName)</gem:Namn>"
    & $append "        <gem:Telefon>$(& $escapeXml $ContactPhone)</gem:Telefon>"
    & $append "        <gem:Epostadress>$(& $escapeXml $ContactEmail)</gem:Epostadress>"
    & $append '      </gem:Kontaktperson>'
    & $append '    </gem:Arbetsgivare>'
    & $append '  </gem:Blankettgemensamt>'

    # Huvuduppgift (HU): the period totals.
    & $append '  <gem:Blankett>'
    & $append '    <gem:Arendeinformation>'
    & $append "      <gem:Arendeagare>$orgIdentitet</gem:Arendeagare>"
    & $append "      <gem:Period>$Period</gem:Period>"
    & $append '    </gem:Arendeinformation>'
    & $append '    <gem:Blankettinnehall>'
    & $append '      <gem:HU>'
    & $append '        <gem:ArbetsgivareHUGROUP>'
    & $append "          <gem:AgRegistreradId faltkod=""201"">$orgIdentitet</gem:AgRegistreradId>"
    & $append '        </gem:ArbetsgivareHUGROUP>'
    & $append "        <gem:RedovisningsPeriod faltkod=""006"">$Period</gem:RedovisningsPeriod>"
    & $append "        <gem:SummaSkatteavdr faltkod=""497"">$totalTax</gem:SummaSkatteavdr>"
    & $append "        <gem:SummaArbAvgSlf faltkod=""487"">$totalEmployer</gem:SummaArbAvgSlf>"
    & $append '      </gem:HU>'
    & $append '    </gem:Blankettinnehall>'
    & $append '  </gem:Blankett>'

    # Individuppgift (IU): one per employee.
    foreach ($iu in $individuals) {
        & $append '  <gem:Blankett>'
        & $append '    <gem:Arendeinformation>'
        & $append "      <gem:Arendeagare>$orgIdentitet</gem:Arendeagare>"
        & $append "      <gem:Period>$Period</gem:Period>"
        & $append '    </gem:Arendeinformation>'
        & $append '    <gem:Blankettinnehall>'
        & $append '      <gem:IU>'
        & $append '        <gem:ArbetsgivareIUGROUP>'
        & $append "          <gem:AgRegistreradId faltkod=""201"">$orgIdentitet</gem:AgRegistreradId>"
        & $append '        </gem:ArbetsgivareIUGROUP>'
        & $append '        <gem:BetalningsmottagareIUGROUP>'
        & $append '          <gem:BetalningsmottagareIDChoice>'
        & $append "            <gem:BetalningsmottagarId faltkod=""215"">$($iu.PersonalNumber)</gem:BetalningsmottagarId>"
        & $append '          </gem:BetalningsmottagareIDChoice>'
        & $append '        </gem:BetalningsmottagareIUGROUP>'
        & $append "        <gem:RedovisningsPeriod faltkod=""006"">$Period</gem:RedovisningsPeriod>"
        & $append "        <gem:Specifikationsnummer faltkod=""570"">$($iu.SpecificationNumber)</gem:Specifikationsnummer>"
        & $append "        <gem:KontantErsattningUlagAG faltkod=""011"">$($iu.GrossSalary)</gem:KontantErsattningUlagAG>"
        & $append "        <gem:AvdrPrelSkatt faltkod=""001"">$($iu.TaxWithheld)</gem:AvdrPrelSkatt>"
        & $append '      </gem:IU>'
        & $append '    </gem:Blankettinnehall>'
        & $append '  </gem:Blankett>'
    }

    & $append '</Skatteverket>'

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($DestPath, $sb.ToString(), $encoding)

    [PSCustomObject]@{
        Path                 = $DestPath
        OrgNumber            = $orgIdentitet
        Period               = $Period
        EmployeeCount        = $individuals.Count
        TotalGrossSalary     = ($individuals | Measure-Object -Property GrossSalary -Sum).Sum
        TotalTaxWithheld     = $totalTax
        TotalEmployerContribution = $totalEmployer
    }
}
