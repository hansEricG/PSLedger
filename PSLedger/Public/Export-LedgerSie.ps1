<#
.SYNOPSIS
Exports a fiscal year to a SIE 4E file.

.DESCRIPTION
Writes a SIE 4 transaction file (typ 4E) containing the chart of accounts and
all verifications for a fiscal year. The file uses CP437 (PC-8) encoding as
required by the SIE standard, decimal amounts use a period as decimal
separator, and dates are written as yyyymmdd. All verifications are placed in
series 'A' with their existing numbers.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER Path
Destination path for the SIE file. Conventionally uses the .se or .sie
extension.

.PARAMETER Force
Overwrite the destination file if it already exists.

.EXAMPLE
Export-LedgerSie -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Path .\minfirma-2024.se

Exports a fiscal year to a SIE 4E file in the current directory.

.EXAMPLE
Export-LedgerSie -JournalPath .\Konsult.ledger -FiscalYear '2024-07_2025-06' -Path C:\Bokslut\konsult-rar.se -Force

Exports a broken fiscal year, overwriting any existing destination file.
#>
function Export-LedgerSie {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Force
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        if (-not (Test-Path $JournalPath -PathType Container)) {
            throw "Journal not found: $JournalPath"
        }

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        if ((Test-Path $Path) -and -not $Force) {
            throw "Destination file already exists: $Path. Use -Force to overwrite."
        }

        $journal = Get-LedgerJournal -Path $JournalPath
        $year = Get-LedgerFiscalYear -JournalPath $JournalPath | Where-Object { $_.Name -eq $FiscalYear }
        if (-not $year) {
            throw "Fiscal year year.txt missing for $FiscalYear"
        }

        $startDate = ([datetime]$year.StartDate).ToString('yyyyMMdd')
        $endDate = ([datetime]$year.EndDate).ToString('yyyyMMdd')

        $accounts = @(Get-LedgerAccount -JournalPath $JournalPath)
        $entries = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear | Sort-Object VerificationNumber)

        $today = (Get-Date).ToString('yyyyMMdd')
        $moduleVersion = (Get-Module PSLedger).Version.ToString()

        $sb = New-Object System.Text.StringBuilder
        $nl = "`r`n"
        $append = {
            param($line)
            [void]$sb.Append($line)
            [void]$sb.Append($nl)
        }

        & $append (Format-SieRecord -Tag 'FLAGGA' -Fields @('0'))
        & $append (Format-SieRecord -Tag 'PROGRAM' -Fields @('PSLedger', $moduleVersion))
        & $append (Format-SieRecord -Tag 'FORMAT' -Fields @('PC8'))
        & $append (Format-SieRecord -Tag 'GEN' -Fields @($today))
        & $append (Format-SieRecord -Tag 'SIETYP' -Fields @('4'))
        & $append (Format-SieRecord -Tag 'FNAMN' -Fields @($journal.Name))
        if ($journal.OrgNumber) {
            & $append (Format-SieRecord -Tag 'ORGNR' -Fields @($journal.OrgNumber))
        }
        & $append (Format-SieRecord -Tag 'RAR' -Fields @('0', $startDate, $endDate))

        # Dimensions and objects
        $dimensions = @(Get-LedgerDimension -JournalPath $JournalPath)
        foreach ($dim in $dimensions) {
            & $append (Format-SieRecord -Tag 'DIM' -Fields @([string]$dim.DimensionNumber, $dim.Name))
        }
        $objects = @(Get-LedgerObject -JournalPath $JournalPath)
        foreach ($obj in $objects) {
            & $append (Format-SieRecord -Tag 'OBJEKT' -Fields @([string]$obj.DimensionNumber, $obj.ObjectNumber, $obj.Name))
        }

        foreach ($a in $accounts) {
            & $append (Format-SieRecord -Tag 'KONTO' -Fields @($a.AccountNumber, $a.AccountName))
        }

        foreach ($e in $entries) {
            $entryDate = ([datetime]$e.Date).ToString('yyyyMMdd')
            & $append (Format-SieRecord -Tag 'VER' -Fields @('A', [string]$e.VerificationNumber, $entryDate, $e.Description))
            & $append '{'
            foreach ($row in $e.Rows) {
                $objList = ''
                if ($row.Objects -and $row.Objects.Count -gt 0) {
                    $objParts = foreach ($k in ($row.Objects.Keys | Sort-Object)) {
                        "$k `"$($row.Objects[$k])`""
                    }
                    $objList = $objParts -join ' '
                }
                & $append (Format-SieTransRecord -Account $row.Account -Amount ([decimal]$row.Amount) -ObjectList $objList)
            }
            & $append '}'
        }

        Write-SieText -Path $Path -Text $sb.ToString()
    }
}

