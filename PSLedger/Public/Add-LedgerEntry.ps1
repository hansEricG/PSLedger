<#
.SYNOPSIS
Creates a new verification (journal entry) in a fiscal year.

.DESCRIPTION
Creates a sequentially numbered verification file (ver0001.txt, ver0002.txt, etc.)
in the specified fiscal year directory. Enforces double-entry bookkeeping by
requiring that the sum of all row amounts equals zero.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year identifier (e.g. '2024-01_2024-12'). Must match an existing
fiscal year directory.

.PARAMETER Date
The date of the transaction.

.PARAMETER Description
A description of the transaction.

.PARAMETER Rows
An array of hashtables, each with 'Account' (account number) and 'Amount'
(positive for debit, negative for credit). The sum of all amounts must be zero,
and each amount may have at most two decimals (whole öre).
Each row may optionally include a 'Comment' key with free-text describing that
specific row. Rows can be supplied as an array or piped in (for example from
New-LedgerEntryRow); piped rows are collected into a single verification.

.PARAMETER Attachment
One or more paths to files to attach to the newly created verification (e.g. a
receipt or invoice). All files must exist; they are validated before the
verification is written. Delegates to Add-LedgerAttachment.

.PARAMETER PassThru
If specified, returns an object describing the created verification, including
its number, fiscal year, file path and any attached files. By default the
command produces no output.

.EXAMPLE
$rows = @(
    @{ Account = '1910'; Amount = 5000 }
    @{ Account = '3010'; Amount = -5000 }
)
Add-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Date '2024-03-15' -Description 'Kontantförsäljning' -Rows $rows

Records a cash sale: debit 1910 (Kassa), credit 3010 (Försäljning).

.EXAMPLE
$rows = @(
    @{ Account = '5010'; Amount = 8000 }
    @{ Account = '2640'; Amount = 2000 }
    @{ Account = '2440'; Amount = -10000 }
)
Add-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Date '2024-03-20' -Description 'Hyra kontor' -Rows $rows -Attachment .\hyresfaktura.pdf, .\betalbevis.pdf -PassThru

Records a supplier invoice for office rent (8000 plus 25 % VAT): debit 5010
(Lokalhyra) and 2640 (Ingående moms), credit 2440 (Leverantörsskulder). Attaches
two files to the verification and returns the created verification object.

.EXAMPLE
@(
    New-LedgerEntryRow -Debit  '1910' 5000
    New-LedgerEntryRow -Credit '3010' 5000
) |
    Add-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Date '2024-03-15' -Description 'Kontantförsäljning'

Builds rows with New-LedgerEntryRow and pipes them straight into Add-LedgerEntry,
avoiding the signed-amount hashtable syntax.
#>
function Add-LedgerEntry {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Write-LedgerVerification performs validation and ShouldProcess; WhatIf and Confirm are forwarded.')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter(Mandatory)]
        [datetime]$Date,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory, ValueFromPipeline)]
        [hashtable[]]$Rows,

        [Parameter()]
        [string[]]$Attachment,

        [Parameter()]
        [switch]$PassThru
    )
    begin {
        # Rows supplied on the command line are present in $PSBoundParameters
        # during begin; rows arriving via the pipeline are not yet bound, so this
        # flag distinguishes "New-LedgerEntryRow | Add-LedgerEntry" (accumulate
        # into one verification) from the parameter/fiscal-year-pipeline usage.
        $RowsFromPipeline = -not $PSBoundParameters.ContainsKey('Rows')
        $RowBuffer = [System.Collections.Generic.List[hashtable]]::new()
        $WriterOptions = @{}
        foreach ($option in 'WhatIf', 'Confirm') {
            if ($PSBoundParameters.ContainsKey($option)) { $WriterOptions[$option] = $PSBoundParameters[$option] }
        }

        $WriteEntry = {
            param([hashtable[]]$EntryRows)

            Write-LedgerVerification -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date $Date -Description $Description -Rows $EntryRows -Attachment $Attachment -PassThru:$PassThru @WriterOptions
        }
    }
    process {
        if ($RowsFromPipeline) {
            foreach ($Row in $Rows) {
                $RowBuffer.Add($Row)
            }
        }
        else {
            & $WriteEntry $Rows
        }
    }
    end {
        if ($RowsFromPipeline) {
            & $WriteEntry $RowBuffer.ToArray()
        }
    }
}
