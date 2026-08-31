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
(positive for debit, negative for credit). The sum of all amounts must be zero.
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
    @{ Account = '2440'; Amount = -6400 }
    @{ Account = '2640'; Amount = -1600 }
)
Add-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Date '2024-03-20' -Description 'Hyra kontor' -Rows $rows -Attachment .\hyresfaktura.pdf, .\betalbevis.pdf -PassThru

Records an office rent invoice with VAT split across multiple accounts, attaches
two files to the verification, and returns the created verification object.

.EXAMPLE
New-LedgerEntryRow -Debit '1910' 5000
New-LedgerEntryRow -Credit '3010' 5000 |
    Add-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Date '2024-03-15' -Description 'Kontantförsäljning'

Builds rows with New-LedgerEntryRow and pipes them straight into Add-LedgerEntry,
avoiding the signed-amount hashtable syntax.
#>
function Add-LedgerEntry {
    [CmdletBinding()]
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

        $WriteEntry = {
            param([hashtable[]]$EntryRows)

            $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
            $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

            $YearDir = Join-Path $JournalPath $FiscalYear
            if (-not (Test-Path $YearDir -PathType Container)) {
                throw "Fiscal year not found: $FiscalYear"
            }

            # Check if fiscal year is closed and capture its date range. year.txt
            # must exist and carry a parseable StartDate/EndDate — otherwise we
            # fail closed rather than silently skipping the date-range check.
            $YearFile = Join-Path $YearDir 'year.txt'
            if (-not (Test-Path $YearFile -PathType Leaf)) {
                throw "Invalid fiscal year - year.txt not found in: $FiscalYear"
            }
            $YearStartDate = $null
            $YearEndDate = $null
            foreach ($Line in (Get-Content $YearFile)) {
                if ($Line -match '^Status:\s*Closed') {
                    throw "Fiscal year $FiscalYear is Closed. Cannot add entries."
                }
                elseif ($Line -match '^StartDate:\s*(.+)$') {
                    $parsed = [datetime]::MinValue
                    if ([datetime]::TryParse($Matches[1].Trim(), [ref]$parsed)) {
                        $YearStartDate = $parsed
                    }
                }
                elseif ($Line -match '^EndDate:\s*(.+)$') {
                    $parsed = [datetime]::MinValue
                    if ([datetime]::TryParse($Matches[1].Trim(), [ref]$parsed)) {
                        $YearEndDate = $parsed
                    }
                }
            }

            if (-not $YearStartDate -or -not $YearEndDate) {
                throw "Invalid fiscal year - StartDate/EndDate missing or unparseable in year.txt for $FiscalYear."
            }

            # Validate date within fiscal year range
            if ($Date -lt $YearStartDate -or $Date -gt $YearEndDate) {
                throw "Date $($Date.ToString('yyyy-MM-dd')) is outside fiscal year $FiscalYear ($($YearStartDate.ToString('yyyy-MM-dd')) to $($YearEndDate.ToString('yyyy-MM-dd')))."
            }

            # Validate balance (round to avoid floating-point accumulation errors)
            $Sum = ($EntryRows | ForEach-Object { $_.Amount }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            if ([Math]::Round($Sum, 2) -ne 0) {
                throw "Entry does not balance. Sum of rows: $Sum (must be 0)."
            }

            # Validate accounts against chart of accounts (if it exists)
            $KontoplanFile = Join-Path $JournalPath 'accounts.txt'
            if (Test-Path $KontoplanFile) {
                $ValidAccounts = @{}
                foreach ($Line in (Get-Content $KontoplanFile)) {
                    if ($Line -match '^(\d+)\t') {
                        $ValidAccounts[$Matches[1]] = $true
                    }
                }

                foreach ($Row in $EntryRows) {
                    if (-not $ValidAccounts.ContainsKey($Row.Account)) {
                        throw "Account $($Row.Account) does not exist in chart of accounts."
                    }
                }
            }

            # Validate attachment files exist before writing the verification
            if ($Attachment) {
                foreach ($attachmentPath in $Attachment) {
                    if (-not (Test-Path $attachmentPath -PathType Leaf)) {
                        throw "Attachment file not found: $attachmentPath"
                    }
                }
            }

            # Determine next verification number by scanning existing files
            $ExistingFiles = Get-ChildItem -Path $YearDir -Filter 'ver*.txt' -File -ErrorAction SilentlyContinue
            if ($ExistingFiles) {
                $MaxNum = $ExistingFiles |
                    ForEach-Object { if ($_.BaseName -match '^ver(\d+)$') { [int]$Matches[1] } } |
                    Measure-Object -Maximum |
                    Select-Object -ExpandProperty Maximum
                $NextNum = $MaxNum + 1
            }
            else {
                $NextNum = 1
            }

            $FileName = 'ver' + $NextNum.ToString('0000') + '.txt'
            $FilePath = Join-Path $YearDir $FileName

            # Build file content
            $Lines = @(
                "Date: $($Date.ToString('yyyy-MM-dd'))"
                "Description: $Description"
                ""
            )

            foreach ($Row in $EntryRows) {
                $line = "$($Row.Account)`t$($Row.Amount)"
                if ($Row.ContainsKey('Objects') -and $Row.Objects -and $Row.Objects.Count -gt 0) {
                    # Validate dimension and object references
                    foreach ($dimNum in $Row.Objects.Keys) {
                        $dim = Get-LedgerDimension -JournalPath $JournalPath -DimensionNumber $dimNum
                        if (-not $dim) {
                            throw "Dimension $dimNum does not exist."
                        }
                        $obj = Get-LedgerObject -JournalPath $JournalPath -DimensionNumber $dimNum -ObjectNumber $Row.Objects[$dimNum]
                        if (-not $obj) {
                            throw "Object '$($Row.Objects[$dimNum])' does not exist in dimension $dimNum."
                        }
                    }
                    $line += "`t$(Format-ObjectTag -Objects $Row.Objects)"
                }
                if ($Row.ContainsKey('Comment') -and $null -ne $Row.Comment) {
                    $commentText = ([string]$Row.Comment) -replace "[`t`r`n]+", ' '
                    $commentText = $commentText.Trim()
                    if ($commentText) {
                        $line += "`t$commentText"
                    }
                }
                $Lines += $line
            }

            $Lines | Set-Content -Path $FilePath -Encoding UTF8

            # Attach any supplied files to the new verification
            $attached = @()
            if ($Attachment) {
                $attached = Add-LedgerAttachment -JournalPath $JournalPath -FiscalYear $FiscalYear `
                    -VerificationNumber $NextNum -Path $Attachment
            }

            if ($PassThru) {
                [PSCustomObject]@{
                    VerificationNumber = $NextNum
                    FiscalYear         = $FiscalYear
                    Date               = $Date
                    Description        = $Description
                    Path               = $FilePath
                    Attachments        = @($attached | ForEach-Object { $_.FileName })
                }
            }
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

