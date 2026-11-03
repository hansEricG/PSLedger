<#
.SYNOPSIS
Closes a fiscal year, booking the net result and preventing further entries.

.DESCRIPTION
Performs the year-end closing of a fiscal year. Unless -SkipResultEntry is used,
the net result for the year (the sum of the profit and loss accounts, classes
3-8) is booked as a normal verification transferring it to equity: debit the
result account (8999 Årets resultat by default) and credit the equity account for
a profit, and the reverse for a loss. The equity account defaults to the one that
matches the journal's CompanyType (2099 for AB, 2019 for EF) and can be overridden
with -EquityAccount.

Booking the result as a real verification means it appears in the ledger and in
SIE exports, and it consumes a verification number. When there is no result to
book (the profit and loss accounts net to zero) no verification is created and the
year is simply flagged as closed.

After any result entry has been written the Status field in year.txt is set to
'Closed'. Once closed, Add-LedgerEntry refuses to create new verifications in that
fiscal year.

Closing is safely resumable. Before anything is written, an immutable plan in
<year>/closing.txt records the result amount and accounts and reserves the
result verification number. If the command is interrupted, run it again with the
same options: it completes the saved closing without booking the result twice.
Recovery stops if the year's result has changed since the plan was saved. The
plan is removed once the year is closed and sealed.

Finally every verification and attachment in the year that is not yet in the
integrity chain is sealed (see Protect-LedgerFiscalYear), and the command returns
an object with FiscalYear, ResultVerification (the result entry's number, or
empty) and ChainHash. Save the ChainHash outside the journal, for example in the
annual report archive, and check it later with
Test-LedgerIntegrity -ExpectedHash.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12').

.PARAMETER EquityAccount
The equity account the net result is transferred to. When omitted it is derived
from the journal's CompanyType (AB -> 2099, EF -> 2019). Required for other
company forms (HB, KB) or journals without a CompanyType when there is a result to
book.

.PARAMETER ResultAccount
The profit and loss closing account debited/credited against equity. Defaults to
'8999' (Årets resultat).

.PARAMETER SkipResultEntry
Closes the year by only setting its status, without booking the net result. Use
this to keep the legacy behaviour where the result is carried forward
synthetically by Copy-LedgerOpeningBalance instead of being booked.

.EXAMPLE
Close-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Books the 2024 net result to equity (using the journal's CompanyType to pick the
account), closes the year so no more entries can be added and returns the chain
hash to keep.

.EXAMPLE
Close-LedgerFiscalYear -JournalPath .\Enskild.ledger -FiscalYear '2024-01_2024-12' -EquityAccount '2019'

Closes an enskild firma year, transferring the result to account 2019 (Årets
resultat, eget kapital).

.EXAMPLE
Get-LedgerFiscalYear -JournalPath .\MinFirma.ledger |
    Where-Object { $_.Status -eq 'Open' } |
    ForEach-Object { Close-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear $_.Name -SkipResultEntry }

Closes all open fiscal years without booking a result verification.
#>
function Close-LedgerFiscalYear {
    [OutputType([pscustomobject])]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [string]$EquityAccount,

        [Parameter()]
        [string]$ResultAccount = '8999',

        [Parameter()]
        [switch]$SkipResultEntry
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $journalLock = $null
        try {
            $journalLock = Enter-LedgerJournalLock -JournalPath $JournalPath
            Assert-LedgerJournalSchema -Path $JournalPath -Write
            $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

            $YearDir = Join-Path $JournalPath $FiscalYear
            if (-not (Test-Path $YearDir -PathType Container)) {
                throw "Fiscal year not found: $FiscalYear"
            }

            $YearFile = Join-Path $YearDir 'year.txt'
            if (-not (Test-Path $YearFile)) {
                throw "Invalid fiscal year - year.txt not found in: $FiscalYear"
            }

            $Lines = Get-Content $YearFile

            # Check current status and capture the year's end date for the result entry.
            $EndDate = $null
            $closed = $false
            foreach ($Line in $Lines) {
                if ($Line -match '^Status:\s*Closed') {
                    $closed = $true
                }
                elseif ($Line -match '^EndDate:\s*(.+)$') {
                    $EndDate = [datetime]$Matches[1]
                }
            }

            $closingPath = Get-LedgerYearClosingPath -JournalPath $JournalPath -FiscalYear $FiscalYear
            $operation = if (Test-Path -LiteralPath $closingPath) { Read-LedgerYearClosing -Path $closingPath } else { $null }
            $entryParameters = $null
            $existingVerification = $false

            if ($closed) {
                # A closing interrupted after the status change only lacks its final seal.
                $check = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
                if (-not $operation) {
                    throw "Fiscal year $FiscalYear is already closed."
                }
                if (@($check.Issues | Where-Object Problem -ne 'Unsealed').Count) {
                    throw "Fiscal year $FiscalYear was closed but has integrity issues; recovery stopped: $(@($check.Issues | ForEach-Object Detail) -join ' ')"
                }
            }
            else {
                if (Test-Path -LiteralPath (Get-LedgerSieImportPath -JournalPath $JournalPath -FiscalYear $FiscalYear)) {
                    throw "Fiscal year $FiscalYear has an unfinished SIE import. Repeat Import-LedgerSie with the same file to complete it before closing the year."
                }
                if ($operation) {
                    if ([bool]$SkipResultEntry -ne $operation.SkipResultEntry) {
                        throw "Fiscal year $FiscalYear has a closing plan $(if ($operation.SkipResultEntry) { 'without' } else { 'with' }) a result entry. Repeat Close-LedgerFiscalYear with the same options to complete it."
                    }
                    if ($operation.VerificationNumber -gt 0 -and
                        (($EquityAccount -and $EquityAccount -ne $operation.EquityAccount) -or
                        ($PSBoundParameters.ContainsKey('ResultAccount') -and $ResultAccount -ne $operation.ResultAccount))) {
                        throw "Fiscal year $FiscalYear has a closing plan booking $($operation.ResultAccount) against $($operation.EquityAccount). Repeat Close-LedgerFiscalYear without other accounts to complete it."
                    }
                }

                # The net result of the profit and loss accounts (classes 3-8); negative for a profit.
                $getResult = {
                    $resultRows = @(Get-LedgerBalance -JournalPath $JournalPath -FiscalYear $FiscalYear |
                            Where-Object { $_.AccountNumber -match '^[3-8]' })
                    $sum = if ($resultRows) { ($resultRows | Measure-Object -Property Balance -Sum).Sum } else { 0 }
                    [Math]::Round([decimal]$sum, 2)
                }

                if (-not $operation) {
                    $operation = [pscustomobject]@{
                        OperationId = [guid]::NewGuid(); FiscalYear = $FiscalYear; VerificationNumber = 0
                        SkipResultEntry = [bool]$SkipResultEntry; ResultAmount = [decimal]0
                        ResultAccount = $null; EquityAccount = $null; VerificationHash = $null
                    }
                    # Book the net result to equity unless explicitly skipped. When the profit
                    # and loss accounts net to zero there is nothing to book, so the year is
                    # simply flagged as closed (this also keeps legacy no-result years working).
                    if (-not $SkipResultEntry) {
                        $operation.ResultAmount = & $getResult
                        if ($operation.ResultAmount -ne 0) {
                            $operation.EquityAccount = if ($EquityAccount) { $EquityAccount } else { Resolve-LedgerEquityAccount -JournalPath $JournalPath }
                            $operation.ResultAccount = $ResultAccount
                            if (-not $EndDate) {
                                throw "Cannot determine the result date - EndDate missing from year.txt in $FiscalYear."
                            }
                            # Debit the result account and credit equity for a profit; the raw
                            # balance of the P&L accounts is negative for a profit, so negating
                            # it gives the debit amount on the result account.
                            $entryParameters = Get-LedgerYearClosingEntry -JournalPath $JournalPath -Operation $operation -Date $EndDate
                            Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear -Label 'Fiscal year closing'
                            $verificationLines = @(Get-LedgerVerificationLines @entryParameters)
                            $operation.VerificationHash = Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($verificationLines -join "`n") + "`n"))
                            $operation.VerificationNumber = Get-LedgerNextVerificationNumber -JournalPath $JournalPath -FiscalYear $FiscalYear
                        }
                    }
                }
                elseif (-not $operation.SkipResultEntry) {
                    $current = & $getResult
                    if ($operation.VerificationNumber -gt 0) {
                        if (-not $EndDate) {
                            throw "Cannot determine the result date - EndDate missing from year.txt in $FiscalYear."
                        }
                        $entryParameters = Get-LedgerYearClosingEntry -JournalPath $JournalPath -Operation $operation -Date $EndDate
                        $verificationPath = Join-Path $YearDir ('ver{0:D4}.txt' -f $operation.VerificationNumber)
                        $existingVerification = Test-Path -LiteralPath $verificationPath
                        if ($existingVerification) {
                            Assert-LedgerInvoicePostingVerification -Path $verificationPath -Operation $operation -Label 'fiscal year closing'
                            foreach ($row in $entryParameters.Rows) {
                                if ($row.Account -match '^[3-8]') { $current -= $row.Amount }
                            }
                        }
                    }
                    if ($current -ne $operation.ResultAmount) {
                        throw "The result of fiscal year $FiscalYear has changed since its closing plan was saved ($($operation.ResultAmount) planned, $current now). Recovery stopped; inspect the entries added after the interruption."
                    }
                    if ($operation.VerificationNumber -gt 0) {
                        $unsealedNumber = if ($existingVerification) { $operation.VerificationNumber } else { 0 }
                        Assert-LedgerInvoicePostingIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear `
                            -UnsealedVerification $unsealedNumber -Label 'Fiscal year closing'
                        if (-not $existingVerification) {
                            $verificationLines = @(Get-LedgerVerificationLines @entryParameters)
                            if ((Get-LedgerSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes(($verificationLines -join "`n") + "`n"))) -ne $operation.VerificationHash) {
                                throw "Fiscal year $FiscalYear no longer produces the saved result verification. Recovery stopped."
                            }
                        }
                    }
                }
            }

            if (-not $PSCmdlet.ShouldProcess($FiscalYear, 'Close fiscal year and book net result')) {
                return
            }

            if (-not (Test-Path -LiteralPath $closingPath)) {
                Save-LedgerYearClosing -Path $closingPath -Operation $operation
            }
            try {
                if (-not $closed) {
                    if ($operation.VerificationNumber -gt 0) {
                        if (-not $existingVerification) {
                            Write-LedgerVerification @entryParameters -ReservedNumber $operation.VerificationNumber -Confirm:$false
                        }
                        Complete-LedgerInvoicePostingVerification -JournalPath $JournalPath -Operation $operation -Label 'fiscal year closing'
                    }

                    # Rewrite year.txt with updated status.
                    $NewLines = foreach ($Line in $Lines) {
                        if ($Line -match '^Status:\s*') {
                            'Status: Closed'
                        }
                        else {
                            $Line
                        }
                    }
                    Set-LedgerFileContent -Path $YearFile -Value $NewLines
                }

                [void](Protect-LedgerYearContent -YearDir $YearDir)
                # The plan only marks an unfinished close; a completed year needs no reservation.
                Remove-Item -LiteralPath $closingPath -Force
            }
            catch {
                throw [InvalidOperationException]::new(
                    "Could not confirm completion of closing fiscal year $FiscalYear. Keep '$closingPath'; rerun Close-LedgerFiscalYear -JournalPath '$JournalPath' -FiscalYear '$FiscalYear' to recover safely. $($_.Exception.Message)",
                    $_.Exception)
            }
            $integrity = Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
            if (-not $integrity.IsValid) {
                Write-Warning "Fiscal year $FiscalYear has integrity issues: $(@($integrity.Issues | ForEach-Object Detail) -join ' ')"
            }

            [PSCustomObject]@{
                FiscalYear         = $FiscalYear
                ResultVerification = if ($operation.VerificationNumber -gt 0) { $operation.VerificationNumber } else { $null }
                ChainHash          = $integrity.ChainHash
            }
        }
        finally { Exit-LedgerJournalLock -Lock $journalLock }
    }
}