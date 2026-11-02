function Get-LedgerEntryAmountState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $sum = [decimal]0
    $firstExtra = $null
    foreach ($row in $Rows) {
        try { $amount = [decimal]$row.Amount }
        catch { throw "Row amount '$($row.Amount)' for account $($row.Account) is not a number." }
        if ($null -eq $firstExtra -and $amount -ne [Math]::Round($amount, 2)) {
            $firstExtra = $row
        }
        $sum += $amount
    }
    [PSCustomObject]@{ Sum = $sum; HasExtraDecimals = $null -ne $firstExtra; FirstExtra = $firstExtra }
}

function Assert-LedgerEntryAmounts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable[]]$Rows,

        [switch]$LegacyReversal
    )

    $state = Get-LedgerEntryAmountState -Rows $Rows
    if ($state.HasExtraDecimals -and -not $LegacyReversal) {
        $row = $state.FirstExtra
        throw "Row amount $($row.Amount) for account $($row.Account) has more than two decimals. Round it to whole öre."
    }
    if ($state.Sum -ne 0 -and -not ($LegacyReversal -and [Math]::Round($state.Sum, 2) -eq 0)) {
        throw "Entry does not balance. Sum of rows: $($state.Sum) (must be 0)."
    }
    if ($LegacyReversal -and $state.HasExtraDecimals) {
        Write-Warning "Reversing a legacy verification with more than two decimals exactly (reversal sum: $($state.Sum)). No amounts or original files were rounded or changed."
    }
}

function Assert-LedgerEntryDate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$YearDir,
        [Parameter(Mandatory)] [string]$FiscalYear,
        [Parameter(Mandatory)] [datetime]$Date
    )

    if (-not (Test-Path -LiteralPath $YearDir -PathType Container)) {
        throw "Fiscal year not found: $FiscalYear"
    }
    $yearFile = Join-Path $YearDir 'year.txt'
    if (-not (Test-Path -LiteralPath $yearFile -PathType Leaf)) {
        throw "Invalid fiscal year - year.txt not found in: $FiscalYear"
    }
    Assert-LedgerFiscalYearOpen -YearDir $YearDir -FiscalYear $FiscalYear -Action 'add entries'
    $start = $null
    $end = $null
    foreach ($line in (Get-Content -LiteralPath $yearFile)) {
        if ($line -match '^StartDate:\s*(.+)$') {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($Matches[1].Trim(), [ref]$parsed)) { $start = $parsed }
        }
        elseif ($line -match '^EndDate:\s*(.+)$') {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($Matches[1].Trim(), [ref]$parsed)) { $end = $parsed }
        }
    }
    if (-not $start -or -not $end) {
        throw "Invalid fiscal year - StartDate/EndDate missing or unparseable in year.txt for $FiscalYear."
    }
    if ($Date -lt $start -or $Date -gt $end) {
        throw "Date $($Date.ToString('yyyy-MM-dd')) is outside fiscal year $FiscalYear ($($start.ToString('yyyy-MM-dd')) to $($end.ToString('yyyy-MM-dd')))."
    }
}

function Get-LedgerVerificationLines {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [string]$FiscalYear,
        [Parameter(Mandatory)] [datetime]$Date,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Description,
        [Parameter(Mandatory)] [hashtable[]]$Rows,
        [string[]]$Attachment,
        [switch]$LegacyReversal,
        [guid]$OperationId = [guid]::Empty
    )

    $YearDir = Join-Path $JournalPath $FiscalYear
    Assert-LedgerEntryDate -YearDir $YearDir -FiscalYear $FiscalYear -Date $Date
    Assert-LedgerEntryAmounts -Rows $Rows -LegacyReversal:$LegacyReversal

    $KontoplanFile = Join-Path $JournalPath 'accounts.txt'
    if (Test-Path $KontoplanFile) {
        $ValidAccounts = @{}
        foreach ($Line in (Get-Content $KontoplanFile)) {
            if ($Line -match '^(\d+)\t') {
                $ValidAccounts[$Matches[1]] = $true
            }
        }
        foreach ($Row in $Rows) {
            if (-not $ValidAccounts.ContainsKey($Row.Account)) {
                throw "Account $($Row.Account) does not exist in chart of accounts."
            }
        }
    }

    if ($Attachment) {
        foreach ($attachmentPath in $Attachment) {
            if (-not (Test-Path $attachmentPath -PathType Leaf)) {
                throw "Attachment file not found: $attachmentPath"
            }
        }
    }

    $Lines = @(
        "Date: $($Date.ToString('yyyy-MM-dd'))"
        "Description: $(ConvertTo-LedgerTextField $Description)"
    )
    if ($OperationId -ne [guid]::Empty) { $Lines += "OperationId: $OperationId" }
    $Lines += ''
    foreach ($Row in $Rows) {
        $line = "$($Row.Account)`t$($Row.Amount)"
        if ($Row.ContainsKey('Objects') -and $Row.Objects -and $Row.Objects.Count -gt 0) {
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
    $Lines
}

function Get-LedgerNextVerificationNumber {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$JournalPath,
        [Parameter(Mandatory)] [string]$FiscalYear
    )
    $numbers = @(Get-ChildItem -LiteralPath (Join-Path $JournalPath $FiscalYear) -Filter 'ver*.txt' -File -ErrorAction Stop |
            ForEach-Object { if ($_.BaseName -match '^ver(\d+)$') { [int]$Matches[1] } })
    $numbers += @(Get-LedgerInvoicePostingReservation -JournalPath $JournalPath -FiscalYear $FiscalYear)
    $numbers += @(Get-LedgerBankPostingOperation -JournalPath $JournalPath | Where-Object FiscalYear -eq $FiscalYear | ForEach-Object VerificationNumber)
    if ($numbers.Count) { [int]($numbers | Measure-Object -Maximum).Maximum + 1 } else { 1 }
}

function Write-LedgerVerification {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$JournalPath,
        [string]$FiscalYear,
        [Parameter(Mandatory)] [datetime]$Date,
        [Parameter(Mandatory)] [string]$Description,
        [Parameter(Mandatory)] [hashtable[]]$Rows,
        [string[]]$Attachment,
        [switch]$PassThru,
        # Only Add-LedgerReversal uses the old precision rule, on mirrored rows.
        [switch]$LegacyReversal,
        [guid]$OperationId = [guid]::Empty,
        [ValidateRange(0, [int]::MaxValue)] [int]$ReservedNumber = 0
    )

    $Description = ConvertTo-LedgerTextField $Description
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
    $journalLock = $null
    try {
        $journalLock = Enter-LedgerJournalLock -JournalPath $JournalPath
        Assert-LedgerJournalSchema -Path $JournalPath -Write
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath
        $YearDir = Join-Path $JournalPath $FiscalYear
        $Lines = @(Get-LedgerVerificationLines -JournalPath $JournalPath -FiscalYear $FiscalYear `
                -Date $Date -Description $Description -Rows $Rows -Attachment $Attachment `
                -LegacyReversal:$LegacyReversal -OperationId $OperationId)

        if ($ReservedNumber -and $OperationId -eq [guid]::Empty) {
            throw 'A reserved verification number requires an operation identity.'
        }
        $NextNum = if ($ReservedNumber) { $ReservedNumber } else {
            Get-LedgerNextVerificationNumber -JournalPath $JournalPath -FiscalYear $FiscalYear
        }
        $FileName = 'ver' + $NextNum.ToString('0000') + '.txt'
        $FilePath = Join-Path $YearDir $FileName
        if (-not $PSCmdlet.ShouldProcess($FiscalYear, "Add verification $FileName")) {
            return
        }
        Set-LedgerFileContent -Path $FilePath -Value $Lines -NoClobber
        try {
            Register-LedgerIntegrityItem -YearDir $YearDir -Kind Verification -Key "$NextNum" -Path $FilePath

            $attached = @()
            if ($Attachment) {
                $attached = Add-LedgerAttachment -JournalPath $JournalPath -FiscalYear $FiscalYear `
                    -VerificationNumber $NextNum -Path $Attachment -PassThru
            }
        }
        catch {
            throw [System.InvalidOperationException]::new(
                "Verification '$FilePath' was saved, but sealing or attachment registration failed. Do not post it again. Inspect the saved verification and run Test-LedgerIntegrity before taking recovery action. $($_.Exception.Message)",
                $_.Exception)
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
    finally { Exit-LedgerJournalLock -Lock $journalLock }
}
