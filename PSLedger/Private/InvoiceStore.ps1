# Helpers for reading and writing invoice files under a journal's 'invoices/'
# directory. An invoice is stored as a plain-text file (inv0001.txt) with tab-
# separated "Key:\tValue" metadata lines, a 'Rows:' section (one revenue row per
# line: Account, NetAmount, VatRate, VatAccount) and a 'Payments:' section (one
# payment per line: Date, Amount, Verification, FiscalYear). Amounts are written
# and read with the invariant culture so the tab-separated numeric columns round
# -trip regardless of the machine's regional settings.

$script:LedgerInvoiceStatuses = @('Draft', 'Booked', 'Partial', 'Paid', 'Credited')

function Format-LedgerInvoiceAmount {
    <#
    .SYNOPSIS
    Formats a decimal for storage using the invariant culture (dot decimal
    separator) so tab-separated numeric columns are never split by a locale comma.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [decimal]$Value
    )
    return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-LedgerInvoiceAmount {
    <#
    .SYNOPSIS
    Parses a stored amount string back to a decimal using the invariant culture.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return [decimal]0 }
    return [decimal]::Parse($Text, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-LedgerInvoiceDirectory {
    <#
    .SYNOPSIS
    Returns the path to a journal's invoices directory, optionally creating it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [switch]$Create
    )
    $dir = Join-Path $JournalPath 'invoices'
    if ($Create -and -not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory | Out-Null
    }
    return $dir
}

function Get-LedgerInvoiceFileName {
    <#
    .SYNOPSIS
    Returns the file name (inv0001.txt) for a given invoice number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$InvoiceNumber
    )
    return 'inv' + $InvoiceNumber.ToString('0000') + '.txt'
}

function ConvertTo-LedgerInvoiceObject {
    <#
    .SYNOPSIS
    Parses the lines of an invoice file into a rich invoice object with computed
    NetTotal, VatTotal, Total, PaidAmount and RemainingAmount.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Content,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $meta = @{}
    $rows = @()
    $payments = @()
    $charges = @()
    $section = 'meta'

    foreach ($line in $Content) {
        if ($line -match '^\s*;') { continue }
        if ($line -eq 'Rows:') { $section = 'rows'; continue }
        if ($line -eq 'Payments:') { $section = 'payments'; continue }
        if ($line -eq 'Charges:') { $section = 'charges'; continue }

        switch ($section) {
            'rows' {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $parts = $line -split "`t"
                if ($parts.Count -ge 2) {
                    $vatRate = if ($parts.Count -ge 3 -and $parts[2]) { ConvertFrom-LedgerInvoiceAmount -Text $parts[2] } else { [decimal]0 }
                    $net = ConvertFrom-LedgerInvoiceAmount -Text $parts[1]
                    $rows += [PSCustomObject]@{
                        Account    = $parts[0]
                        Amount     = $net
                        VatRate    = $vatRate
                        VatAccount = if ($parts.Count -ge 4) { $parts[3] } else { '' }
                        VatAmount  = [Math]::Round($net * $vatRate, 2)
                    }
                }
            }
            'payments' {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $parts = $line -split "`t"
                if ($parts.Count -ge 2) {
                    $payments += [PSCustomObject]@{
                        Date               = [datetime]::ParseExact($parts[0], 'yyyy-MM-dd', $null)
                        Amount             = ConvertFrom-LedgerInvoiceAmount -Text $parts[1]
                        VerificationNumber = if ($parts.Count -ge 3 -and $parts[2]) { [int]$parts[2] } else { $null }
                        FiscalYear         = if ($parts.Count -ge 4) { $parts[3] } else { '' }
                    }
                }
            }
            'charges' {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $parts = $line -split "`t"
                if ($parts.Count -ge 3) {
                    $charges += [PSCustomObject]@{
                        Date               = [datetime]::ParseExact($parts[0], 'yyyy-MM-dd', $null)
                        Type               = $parts[1]
                        Amount             = ConvertFrom-LedgerInvoiceAmount -Text $parts[2]
                        Account            = if ($parts.Count -ge 4) { $parts[3] } else { '' }
                        VerificationNumber = if ($parts.Count -ge 5 -and $parts[4]) { [int]$parts[4] } else { $null }
                        FiscalYear         = if ($parts.Count -ge 6) { $parts[5] } else { '' }
                    }
                }
            }
            default {
                $parts = $line -split "`t", 2
                if ($parts.Count -ge 2) {
                    $meta[$parts[0].TrimEnd(':')] = $parts[1]
                }
            }
        }
    }

    $netTotal = ($rows | Measure-Object -Property Amount -Sum).Sum
    if (-not $netTotal) { $netTotal = [decimal]0 }
    $vatTotal = [decimal]0
    foreach ($r in $rows) { $vatTotal += $r.VatAmount }
    $chargesTotal = ($charges | Measure-Object -Property Amount -Sum).Sum
    if (-not $chargesTotal) { $chargesTotal = [decimal]0 }
    $total = [Math]::Round($netTotal + $vatTotal + $chargesTotal, 2)

    $paidAmount = ($payments | Measure-Object -Property Amount -Sum).Sum
    if (-not $paidAmount) { $paidAmount = [decimal]0 }

    [PSCustomObject]@{
        InvoiceNumber      = [int]$meta['InvoiceNumber']
        CustomerNumber     = $meta['CustomerNumber']
        InvoiceDate        = if ($meta['InvoiceDate']) { [datetime]::ParseExact($meta['InvoiceDate'], 'yyyy-MM-dd', $null) } else { $null }
        DueDate            = if ($meta['DueDate']) { [datetime]::ParseExact($meta['DueDate'], 'yyyy-MM-dd', $null) } else { $null }
        Description        = $meta['Description']
        Status             = $meta['Status']
        ReceivableAccount  = $meta['ReceivableAccount']
        BookedVerification = if ($meta['BookedVerification']) { [int]$meta['BookedVerification'] } else { $null }
        BookedFiscalYear   = $meta['BookedFiscalYear']
        OcrReference       = if ($meta['InvoiceNumber']) { Get-LedgerOcrReference -BaseNumber ([string]$meta['InvoiceNumber']) } else { '' }
        ReminderCount      = if ($meta['ReminderCount']) { [int]$meta['ReminderCount'] } else { 0 }
        LastReminderDate   = if ($meta['LastReminderDate']) { [datetime]::ParseExact($meta['LastReminderDate'], 'yyyy-MM-dd', $null) } else { $null }
        Rows               = $rows
        Payments           = $payments
        Charges            = $charges
        NetTotal           = [Math]::Round([decimal]$netTotal, 2)
        VatTotal           = [Math]::Round($vatTotal, 2)
        ChargesTotal       = [Math]::Round([decimal]$chargesTotal, 2)
        Total              = $total
        PaidAmount         = [Math]::Round([decimal]$paidAmount, 2)
        RemainingAmount    = [Math]::Round($total - $paidAmount, 2)
        FilePath           = $FilePath
    }
}

function Read-LedgerInvoiceFile {
    <#
    .SYNOPSIS
    Reads and parses a single invoice file, returning an invoice object.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Invoice file not found: $Path"
    }
    $content = @(Get-Content -Path $Path -Encoding UTF8)
    return ConvertTo-LedgerInvoiceObject -Content $content -FilePath $Path
}

function Save-LedgerInvoiceFile {
    <#
    .SYNOPSIS
    Serialises an invoice object back to its file.

    .DESCRIPTION
    Writes the metadata, 'Rows:' and 'Payments:' sections. Accepts either an
    object produced by ConvertTo-LedgerInvoiceObject or a PSCustomObject with the
    same properties. The FilePath property determines the destination.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Invoice
    )

    $lines = @(
        '; PSLedger Invoice'
        "InvoiceNumber:`t$($Invoice.InvoiceNumber)"
        "CustomerNumber:`t$($Invoice.CustomerNumber)"
        "InvoiceDate:`t$($Invoice.InvoiceDate.ToString('yyyy-MM-dd'))"
        "DueDate:`t$($Invoice.DueDate.ToString('yyyy-MM-dd'))"
        "Description:`t$($Invoice.Description)"
        "Status:`t$($Invoice.Status)"
        "ReceivableAccount:`t$($Invoice.ReceivableAccount)"
        "BookedVerification:`t$(if ($null -ne $Invoice.BookedVerification) { $Invoice.BookedVerification } else { '' })"
        "BookedFiscalYear:`t$($Invoice.BookedFiscalYear)"
        "ReminderCount:`t$(if ($Invoice.PSObject.Properties['ReminderCount'] -and $Invoice.ReminderCount) { $Invoice.ReminderCount } else { 0 })"
        "LastReminderDate:`t$(if ($Invoice.PSObject.Properties['LastReminderDate'] -and $Invoice.LastReminderDate) { $Invoice.LastReminderDate.ToString('yyyy-MM-dd') } else { '' })"
        'Rows:'
    )

    foreach ($row in $Invoice.Rows) {
        $lines += "$($row.Account)`t$(Format-LedgerInvoiceAmount -Value ([decimal]$row.Amount))`t$(Format-LedgerInvoiceAmount -Value ([decimal]$row.VatRate))`t$($row.VatAccount)"
    }

    $lines += 'Payments:'
    foreach ($p in $Invoice.Payments) {
        $veriField = if ($null -ne $p.VerificationNumber) { $p.VerificationNumber } else { '' }
        $lines += "$($p.Date.ToString('yyyy-MM-dd'))`t$(Format-LedgerInvoiceAmount -Value ([decimal]$p.Amount))`t$veriField`t$($p.FiscalYear)"
    }

    $lines += 'Charges:'
    if ($Invoice.PSObject.Properties['Charges']) {
        foreach ($c in $Invoice.Charges) {
            $veriField = if ($null -ne $c.VerificationNumber) { $c.VerificationNumber } else { '' }
            $lines += "$($c.Date.ToString('yyyy-MM-dd'))`t$($c.Type)`t$(Format-LedgerInvoiceAmount -Value ([decimal]$c.Amount))`t$($c.Account)`t$veriField`t$($c.FiscalYear)"
        }
    }

    Set-LedgerFileContent -Path $Invoice.FilePath -Value $lines
}

