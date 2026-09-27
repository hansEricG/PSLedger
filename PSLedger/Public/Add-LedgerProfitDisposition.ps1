<#
.SYNOPSIS
Books the appropriation of profit (resultatdisposition) decided by the annual
general meeting.

.DESCRIPTION
After the årsstämma has adopted the annual report, the previous fiscal year's
result standing on the result account (2099 Årets resultat) is carried to
retained earnings (2091 Balanserad vinst eller förlust), and any dividend decided
is booked as a liability (2898 Outtagen vinstutdelning). This command creates that
verification in the fiscal year in which the meeting is held:

    2099  -<result balance>      (clears the result account)
    2898  -<dividend>            (dividend liability, only when a dividend is decided)
    2091  <result balance + dividend>

The result amount is the current balance of the result account in -FiscalYear,
i.e. the result carried into it by Copy-LedgerOpeningBalance. The dividend and
meeting date default to the ProposedDividend and AnnualMeetingDate recorded with
Set-LedgerReportInput for the year being disposed (-FromFiscalYear).

The command refuses to run when the result account has no balance (the
disposition has most likely been booked already) or when the dividend exceeds the
disposable free equity.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER FiscalYear
The fiscal year in which the annual general meeting is held and the disposition
is booked (normally the year after the one being disposed). If omitted, uses the
current fiscal year set via Set-LedgerCurrentFiscalYear.

.PARAMETER FromFiscalYear
The fiscal year whose result is disposed. Defaults to the fiscal year preceding
-FiscalYear.

.PARAMETER Date
The date of the annual general meeting. Defaults to the AnnualMeetingDate recorded
for -FromFiscalYear.

.PARAMETER Dividend
The dividend decided by the meeting. Defaults to the ProposedDividend recorded for
-FromFiscalYear (0 when not recorded).

.PARAMETER Description
Description for the verification. Defaults to 'Resultatdisposition enligt
årsstämma <date>'.

.PARAMETER ResultAccount
The result account to clear. Defaults to the journal's result account (2099 for
an AB).

.PARAMETER RetainedEarningsAccount
The retained earnings account. Defaults to 2091.

.PARAMETER DividendAccount
The dividend liability account. Defaults to 2898.

.EXAMPLE
Add-LedgerProfitDisposition -JournalPath .\HEG.ledger -FiscalYear '2025-09_2026-08'

Books the disposition of the 2024/25 result on the recorded årsstämma date with
the recorded proposed dividend.

.EXAMPLE
Add-LedgerProfitDisposition -JournalPath .\Konsult.ledger -FiscalYear '2025-01_2025-12' `
    -Date '2025-05-15' -Dividend 80000 -WhatIf

Previews carrying last year's profit to 2091 and booking an 80 000 kr dividend
liability on 2898.
#>
function Add-LedgerProfitDisposition {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [string]$FromFiscalYear,

        [Parameter()]
        [datetime]$Date,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [decimal]$Dividend,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidatePattern('^\d+$')]
        [string]$ResultAccount,

        [Parameter()]
        [ValidatePattern('^\d+$')]
        [string]$RetainedEarningsAccount = '2091',

        [Parameter()]
        [ValidatePattern('^\d+$')]
        [string]$DividendAccount = '2898'
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $Years = @(Get-LedgerFiscalYear -JournalPath $JournalPath | Sort-Object StartDate)
        $Names = @($Years | ForEach-Object { $_.Name })
        if ($Names -notcontains $FiscalYear) {
            throw "Fiscal year not found: $FiscalYear"
        }
        if (-not $FromFiscalYear) {
            $Index = $Names.IndexOf($FiscalYear)
            if ($Index -lt 1) {
                throw "No fiscal year precedes $FiscalYear. Specify -FromFiscalYear."
            }
            $FromFiscalYear = $Names[$Index - 1]
        }
        elseif ($Names -notcontains $FromFiscalYear) {
            throw "Fiscal year not found: $FromFiscalYear"
        }

        $ReportInput = Get-LedgerReportInput -JournalPath $JournalPath -FiscalYear $FromFiscalYear
        if (-not $PSBoundParameters.ContainsKey('Date')) {
            if (-not $ReportInput.AnnualMeetingDate) {
                throw "No AnnualMeetingDate recorded for $FromFiscalYear. Specify -Date or record it with Set-LedgerReportInput."
            }
            $Date = [datetime]::ParseExact($ReportInput.AnnualMeetingDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        if (-not $PSBoundParameters.ContainsKey('Dividend')) {
            $Dividend = if ($ReportInput.ProposedDividend) { [decimal]$ReportInput.ProposedDividend } else { [decimal]0 }
        }
        $Dividend = [Math]::Round([decimal]$Dividend, 2)
        if (-not $ResultAccount) {
            $ResultAccount = Resolve-LedgerResultCarryAccount -JournalPath $JournalPath
        }
        if (-not $Description) {
            $Description = "Resultatdisposition enligt årsstämma $($Date.ToString('yyyy-MM-dd'))"
        }

        $Balance = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear)
        $ResultRow = $Balance | Where-Object { $_.AccountNumber -eq $ResultAccount } | Select-Object -First 1
        $ResultBalance = if ($ResultRow) { [Math]::Round([decimal]$ResultRow.Balance, 2) } else { [decimal]0 }
        if ($ResultBalance -eq 0) {
            throw "Result account $ResultAccount has no balance in $FiscalYear. The disposition has probably been booked already (or the opening balance has not been copied)."
        }

        # The balance on the result account should be the disposed year's result.
        $FromResult = @(Get-LedgerEquityReconciliation -JournalPath $JournalPath -FiscalYear $FromFiscalYear |
            Where-Object { $_.Component -eq 'YearResult' })[0].ClosingBalance
        if ($null -ne $FromResult -and [Math]::Round([decimal]$FromResult, 2) -ne -$ResultBalance) {
            Write-Warning "The balance on $ResultAccount ($(-$ResultBalance) as a result) differs from the result of $FromFiscalYear ($FromResult)."
        }

        if ($Dividend -gt 0) {
            $Disposable = (Get-LedgerProfitDisposition -JournalPath $JournalPath -FiscalYear $FromFiscalYear -Dividend $Dividend).TotalDisposable
            if ($Dividend -gt $Disposable) {
                throw "Dividend $Dividend exceeds the disposable free equity of $FromFiscalYear ($Disposable)."
            }
        }

        $Rows = @(
            @{ Account = $ResultAccount; Amount = -$ResultBalance }
            @{ Account = $RetainedEarningsAccount; Amount = $ResultBalance + $Dividend }
        )
        if ($Dividend -gt 0) {
            $Rows += @{ Account = $DividendAccount; Amount = -$Dividend }
        }
        $Rows = @($Rows | Where-Object { $_.Amount -ne 0 })

        $Result = -$ResultBalance
        $Action = "Book resultatdisposition of $FromFiscalYear (result $Result, dividend $Dividend)"
        if (-not $PSCmdlet.ShouldProcess($FiscalYear, $Action)) {
            return
        }

        $Entry = Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date $Date `
            -Description $Description -Rows $Rows -PassThru

        [PSCustomObject]@{
            FiscalYear         = $FiscalYear
            FromFiscalYear     = $FromFiscalYear
            VerificationNumber = $Entry.VerificationNumber
            Date               = $Date
            Description        = $Description
            Result             = $Result
            Dividend           = $Dividend
            CarriedForward     = $Result - $Dividend
        }
    }
}
