<#
.SYNOPSIS
Seals the verifications and attachments of a fiscal year in its integrity chain.

.DESCRIPTION
PSLedger seals each verification and attachment in the fiscal year's
integrity.txt when it is written, so this command is normally only needed for
journals created before tamper detection existed, or to accept a verification or
attachment that was added outside PSLedger.

Every verification and attachment in the year that the chain does not yet cover is
sealed, in verification-number order. Items already sealed are left as they are,
so a changed verification stays reported as Modified by Test-LedgerIntegrity.
Closed fiscal years can be sealed too; nothing in the bookkeeping changes.

Returns the Test-LedgerIntegrity result for the year, including the ChainHash to
save somewhere outside the journal.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year to seal. If omitted, uses the latest fiscal year.
Accepts pipeline input from fiscal year objects.

.EXAMPLE
Protect-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Seals all verifications and attachments of 2024 in Min Firma AB's journal.

.EXAMPLE
Get-LedgerFiscalYear -JournalPath .\Konsult.ledger | Protect-LedgerFiscalYear -JournalPath .\Konsult.ledger |
    Select-Object FiscalYear, Status, ChainHash

Seals every fiscal year of Konsult AB after upgrading PSLedger and lists the chain
hashes to keep.
#>
function Protect-LedgerFiscalYear {
    [OutputType([pscustomobject])]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $yearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path -LiteralPath $yearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        if ($PSCmdlet.ShouldProcess($FiscalYear, 'Seal verifications and attachments')) {
            $sealed = Protect-LedgerYearContent -YearDir $yearDir
            Write-Verbose "Sealed $sealed item(s) in $FiscalYear."
            Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear $FiscalYear
        }
    }
}
