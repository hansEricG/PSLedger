# Helpers for reading and writing payslip files under a journal's 'payslips/'
# directory. A payslip (lönespecifikation) is the payroll counterpart of an
# invoice: it records an employee's gross salary, the preliminary tax withheld
# and the employer's social security contributions for a pay period. Posting a
# payslip creates a verification that debits the salary cost account with the
# gross pay, credits the tax liability (2710) with the withheld tax, credits
# bank (1930) with the net pay, and books the employer contribution as both a
# cost (7510) and a liability (2730).
#
# Files are stored as pay0001.txt with the same tab-separated "Key:\tValue"
# metadata layout as the invoice stores. Amounts are written and read with the
# invariant culture (via Format-/ConvertFrom-LedgerInvoiceAmount) so the
# tab-separated numeric columns round-trip regardless of the machine's regional
# settings.

$script:LedgerPayslipStatuses = @('Draft', 'Booked')

function Get-LedgerPayslipDirectory {
    <#
    .SYNOPSIS
    Returns the path to a journal's payslips directory, optionally creating it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [switch]$Create
    )
    $dir = Join-Path $JournalPath 'payslips'
    if ($Create -and -not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory | Out-Null
    }
    return $dir
}

function Get-LedgerPayslipFileName {
    <#
    .SYNOPSIS
    Returns the file name (pay0001.txt) for a given payslip number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$PayslipNumber
    )
    return 'pay' + $PayslipNumber.ToString('0000') + '.txt'
}

function ConvertTo-LedgerPayslipObject {
    <#
    .SYNOPSIS
    Parses the lines of a payslip file into a rich object with computed NetPay,
    EmployerContribution and TotalEmployerCost.
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
    foreach ($line in $Content) {
        if ($line -match '^\s*;') { continue }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -ge 2) {
            $meta[$parts[0].TrimEnd(':')] = $parts[1]
        }
    }

    $parseDate = {
        param($text)
        if ($text) { [datetime]::ParseExact($text, 'yyyy-MM-dd', $null) } else { $null }
    }

    $gross = ConvertFrom-LedgerInvoiceAmount -Text $meta['GrossSalary']
    $tax = ConvertFrom-LedgerInvoiceAmount -Text $meta['TaxAmount']
    $rate = ConvertFrom-LedgerInvoiceAmount -Text $meta['EmployerContributionRate']

    $netPay = [Math]::Round($gross - $tax, 2)
    $employerContribution = [Math]::Round($gross * $rate, 2)
    $totalEmployerCost = [Math]::Round($gross + $employerContribution, 2)

    [PSCustomObject]@{
        PayslipNumber                        = [int]$meta['PayslipNumber']
        EmployeeNumber                       = $meta['EmployeeNumber']
        PayDate                              = & $parseDate $meta['PayDate']
        PeriodStart                          = & $parseDate $meta['PeriodStart']
        PeriodEnd                            = & $parseDate $meta['PeriodEnd']
        Description                          = $meta['Description']
        Status                               = $meta['Status']
        GrossSalary                          = [Math]::Round($gross, 2)
        TaxAmount                            = [Math]::Round($tax, 2)
        EmployerContributionRate             = $rate
        NetPay                               = $netPay
        EmployerContribution                 = $employerContribution
        TotalEmployerCost                    = $totalEmployerCost
        SalaryAccount                        = $meta['SalaryAccount']
        TaxLiabilityAccount                  = $meta['TaxLiabilityAccount']
        NetPayAccount                        = $meta['NetPayAccount']
        EmployerContributionAccount          = $meta['EmployerContributionAccount']
        EmployerContributionLiabilityAccount = $meta['EmployerContributionLiabilityAccount']
        BookedVerification                   = if ($meta['BookedVerification']) { [int]$meta['BookedVerification'] } else { $null }
        BookedFiscalYear                     = $meta['BookedFiscalYear']
        FilePath                             = $FilePath
    }
}

function Read-LedgerPayslipFile {
    <#
    .SYNOPSIS
    Reads and parses a single payslip file, returning an object.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Payslip file not found: $Path"
    }
    $content = @(Get-Content -Path $Path -Encoding UTF8)
    return ConvertTo-LedgerPayslipObject -Content $content -FilePath $Path
}

function Save-LedgerPayslipFile {
    <#
    .SYNOPSIS
    Serialises a payslip object back to its file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Payslip
    )

    $periodStart = if ($Payslip.PeriodStart) { $Payslip.PeriodStart.ToString('yyyy-MM-dd') } else { '' }
    $periodEnd = if ($Payslip.PeriodEnd) { $Payslip.PeriodEnd.ToString('yyyy-MM-dd') } else { '' }

    $lines = @(
        '; PSLedger Payslip'
        "PayslipNumber:`t$($Payslip.PayslipNumber)"
        "EmployeeNumber:`t$($Payslip.EmployeeNumber)"
        "PayDate:`t$($Payslip.PayDate.ToString('yyyy-MM-dd'))"
        "PeriodStart:`t$periodStart"
        "PeriodEnd:`t$periodEnd"
        "Description:`t$($Payslip.Description)"
        "Status:`t$($Payslip.Status)"
        "GrossSalary:`t$(Format-LedgerInvoiceAmount -Value ([decimal]$Payslip.GrossSalary))"
        "TaxAmount:`t$(Format-LedgerInvoiceAmount -Value ([decimal]$Payslip.TaxAmount))"
        "EmployerContributionRate:`t$(Format-LedgerInvoiceAmount -Value ([decimal]$Payslip.EmployerContributionRate))"
        "SalaryAccount:`t$($Payslip.SalaryAccount)"
        "TaxLiabilityAccount:`t$($Payslip.TaxLiabilityAccount)"
        "NetPayAccount:`t$($Payslip.NetPayAccount)"
        "EmployerContributionAccount:`t$($Payslip.EmployerContributionAccount)"
        "EmployerContributionLiabilityAccount:`t$($Payslip.EmployerContributionLiabilityAccount)"
        "BookedVerification:`t$(if ($null -ne $Payslip.BookedVerification) { $Payslip.BookedVerification } else { '' })"
        "BookedFiscalYear:`t$($Payslip.BookedFiscalYear)"
    )

    Set-LedgerFileContent -Path $Payslip.FilePath -Value $lines
}
