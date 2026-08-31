<#
.SYNOPSIS
Exports a VAT declaration (momsdeklaration) as a Skatteverket eSKD file.

.DESCRIPTION
Builds the VAT report for a period (via Get-LedgerVatReport) and writes it as an
electronic tax declaration file (eSKD) that can be uploaded in Skatteverket's
e-service for VAT (Lämna momsdeklaration via fil).

The file is XML with an <eSKDUpload Version="6.0"> root, the company organisation
number and a <Moms> section holding the declaration period and one element per
declaration box (ruta). Amounts are reported in whole kronor (rounded). The
following boxes are written:

  Ruta 05 (ForsMomsEjAnnan) — Momspliktig försäljning
  Ruta 10 (MomsUtgHog)      — Utgående moms 25 %
  Ruta 11 (MomsUtgMedel)    — Utgående moms 12 %
  Ruta 12 (MomsUtgLag)      — Utgående moms 6 %
  Ruta 48 (MomsIngaende)    — Ingående moms
  Ruta 49 (MomsBetala)      — Moms att betala eller få tillbaka

Box 49 (MomsBetala) is computed from the rounded box values as
(10 + 11 + 12) - 48, matching how Skatteverket sums the declaration. A positive
value is VAT to pay; a negative value is VAT to reclaim.

The file is written with ISO-8859-1 encoding, as required by the eSKD format.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER FromDate
Start of the VAT reporting period (inclusive).

.PARAMETER ToDate
End of the VAT reporting period (inclusive).

.PARAMETER Path
Destination path for the eSKD file. Conventionally uses the .xml extension.

.PARAMETER Period
The declaration period as YYYYMM (e.g. '202403'). Defaults to the month of
-ToDate.

.PARAMETER Force
Overwrite the destination file if it already exists.

.EXAMPLE
Export-LedgerVatDeclaration -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -FromDate '2024-01-01' -ToDate '2024-03-31' -Path .\moms-2024-q1.xml

Exports the Q1 2024 VAT declaration as an eSKD file.

.EXAMPLE
Export-LedgerVatDeclaration -JournalPath .\Konsult.ledger -FiscalYear '2024-01_2024-12' -FromDate '2024-06-01' -ToDate '2024-06-30' -Period '202406' -Path C:\Moms\konsult-2024-06.xml -Force

Exports the June 2024 declaration with an explicit period, overwriting any
existing file.
#>
function Export-LedgerVatDeclaration {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [datetime]$FromDate,

        [Parameter(Mandatory)]
        [datetime]$ToDate,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidatePattern('^\d{6}$')]
        [string]$Period,

        [switch]$Force
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        if ($ToDate -lt $FromDate) {
            throw "ToDate ($($ToDate.ToString('yyyy-MM-dd'))) must not be earlier than FromDate ($($FromDate.ToString('yyyy-MM-dd')))."
        }

        $DestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if ((Test-Path -LiteralPath $DestPath) -and -not $Force) {
            throw "Destination file already exists: $DestPath. Use -Force to overwrite."
        }

        $journal = Get-LedgerJournal -Path $JournalPath
        $orgNr = $journal.OrgNumber
        if (-not $orgNr) {
            throw "Journal has no OrgNumber; set one with Set-LedgerJournal before exporting a VAT declaration."
        }

        if (-not $Period) {
            $Period = $ToDate.ToString('yyyyMM')
        }

        $report = @(Get-LedgerVatReport -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -FromDate $FromDate -ToDate $ToDate)

        # Round every box to whole kronor (Skatteverket declarations use integers).
        $boxAmount = @{}
        foreach ($box in $report) {
            $boxAmount[[int]$box.Box] = [long][Math]::Round([decimal]$box.Amount, 0, [System.MidpointRounding]::AwayFromZero)
        }

        # Box 49 is derived from the rounded output/input boxes so it always
        # reconciles with the individual rows the way Skatteverket sums them.
        $outputVat = 0L
        foreach ($b in 10, 11, 12) {
            if ($boxAmount.ContainsKey($b)) { $outputVat += $boxAmount[$b] }
        }
        $inputVat = if ($boxAmount.ContainsKey(48)) { $boxAmount[48] } else { 0L }
        $boxAmount[49] = $outputVat - $inputVat

        $tagMap = Get-VatEskdTagMap

        $sb = New-Object System.Text.StringBuilder
        $nl = "`r`n"
        $append = {
            param($line)
            [void]$sb.Append($line)
            [void]$sb.Append($nl)
        }

        & $append '<?xml version="1.0" encoding="ISO-8859-1"?>'
        & $append '<eSKDUpload Version="6.0">'
        & $append "  <OrgNr>$orgNr</OrgNr>"
        & $append '  <Moms>'
        & $append "    <Period>$Period</Period>"
        foreach ($map in $tagMap) {
            $box = [int]$map.Box
            $value = if ($boxAmount.ContainsKey($box)) { $boxAmount[$box] } else { 0L }
            & $append "    <$($map.Tag)>$value</$($map.Tag)>"
        }
        & $append '  </Moms>'
        & $append '</eSKDUpload>'

        $encoding = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
        [System.IO.File]::WriteAllText($DestPath, $sb.ToString(), $encoding)

        [PSCustomObject]@{
            Path      = $DestPath
            OrgNumber = $orgNr
            Period    = $Period
            Boxes     = [PSCustomObject]@{
                '05' = $boxAmount[5]
                '10' = $boxAmount[10]
                '11' = $boxAmount[11]
                '12' = $boxAmount[12]
                '48' = $boxAmount[48]
                '49' = $boxAmount[49]
            }
        }
    }
}
