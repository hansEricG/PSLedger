# Helpers for reading and writing supplier invoice files under a journal's
# 'supplierinvoices/' directory. A supplier invoice (leverantörsfaktura) is the
# accounts-payable mirror of a customer invoice: cost accounts are debited (net)
# together with input VAT, and the payable account (2440 Leverantörsskulder) is
# credited with the gross total. Files are stored as sup0001.txt with the same
# tab-separated layout as customer invoices (metadata + 'Rows:' + 'Payments:').

function Get-LedgerSupplierInvoiceDirectory {
    <#
    .SYNOPSIS
    Returns the path to a journal's supplier invoices directory, optionally
    creating it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [switch]$Create
    )
    $dir = Join-Path $JournalPath 'supplierinvoices'
    if ($Create -and -not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory | Out-Null
    }
    return $dir
}

function Get-LedgerSupplierInvoiceFileName {
    <#
    .SYNOPSIS
    Returns the file name (sup0001.txt) for a given supplier invoice number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$InvoiceNumber
    )
    return 'sup' + $InvoiceNumber.ToString('0000') + '.txt'
}

function ConvertTo-LedgerSupplierInvoiceObject {
    <#
    .SYNOPSIS
    Parses the lines of a supplier invoice file into a rich object with computed
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
    $section = 'meta'

    foreach ($line in $Content) {
        if ($line -match '^\s*;') { continue }
        if ($line -eq 'Rows:') { $section = 'rows'; continue }
        if ($line -eq 'Payments:') { $section = 'payments'; continue }

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
    $total = [Math]::Round($netTotal + $vatTotal, 2)

    $paidAmount = ($payments | Measure-Object -Property Amount -Sum).Sum
    if (-not $paidAmount) { $paidAmount = [decimal]0 }

    [PSCustomObject]@{
        InvoiceNumber      = [int]$meta['InvoiceNumber']
        SupplierNumber     = $meta['SupplierNumber']
        SupplierInvoiceNo  = $meta['SupplierInvoiceNo']
        InvoiceDate        = if ($meta['InvoiceDate']) { [datetime]::ParseExact($meta['InvoiceDate'], 'yyyy-MM-dd', $null) } else { $null }
        DueDate            = if ($meta['DueDate']) { [datetime]::ParseExact($meta['DueDate'], 'yyyy-MM-dd', $null) } else { $null }
        Description        = $meta['Description']
        Status             = $meta['Status']
        PayableAccount     = $meta['PayableAccount']
        Reference          = $meta['Reference']
        BookedVerification = if ($meta['BookedVerification']) { [int]$meta['BookedVerification'] } else { $null }
        BookedFiscalYear   = $meta['BookedFiscalYear']
        Rows               = $rows
        Payments           = $payments
        NetTotal           = [Math]::Round([decimal]$netTotal, 2)
        VatTotal           = [Math]::Round($vatTotal, 2)
        Total              = $total
        PaidAmount         = [Math]::Round([decimal]$paidAmount, 2)
        RemainingAmount    = [Math]::Round($total - $paidAmount, 2)
        FilePath           = $FilePath
    }
}

function Read-LedgerSupplierInvoiceFile {
    <#
    .SYNOPSIS
    Reads and parses a single supplier invoice file, returning an object.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Supplier invoice file not found: $Path"
    }
    $content = @(Get-Content -Path $Path -Encoding UTF8)
    return ConvertTo-LedgerSupplierInvoiceObject -Content $content -FilePath $Path
}

function Save-LedgerSupplierInvoiceFile {
    <#
    .SYNOPSIS
    Serialises a supplier invoice object back to its file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Invoice
    )

    $lines = @(
        '; PSLedger Supplier Invoice'
        "InvoiceNumber:`t$($Invoice.InvoiceNumber)"
        "SupplierNumber:`t$($Invoice.SupplierNumber)"
        "SupplierInvoiceNo:`t$($Invoice.SupplierInvoiceNo)"
        "InvoiceDate:`t$($Invoice.InvoiceDate.ToString('yyyy-MM-dd'))"
        "DueDate:`t$($Invoice.DueDate.ToString('yyyy-MM-dd'))"
        "Description:`t$($Invoice.Description)"
        "Status:`t$($Invoice.Status)"
        "PayableAccount:`t$($Invoice.PayableAccount)"
        "Reference:`t$($Invoice.Reference)"
        "BookedVerification:`t$(if ($null -ne $Invoice.BookedVerification) { $Invoice.BookedVerification } else { '' })"
        "BookedFiscalYear:`t$($Invoice.BookedFiscalYear)"
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

    $lines | Set-Content -Path $Invoice.FilePath -Encoding UTF8
}
