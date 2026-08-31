# Shared PSLedger test fixtures.
#
# Many test files build the same starting point: a 'Faktura AB' journal with the
# BAS-Smaforetag chart, a 2024 fiscal year and one or more customers/suppliers,
# and then a posted invoice. These helpers centralise that setup so each test
# file's own fixture becomes a thin, intention-revealing wrapper instead of a
# copy of the same journal-building boilerplate.
#
# Dot-source this file from a test file's top-level BeforeAll:
#
#     . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')
#
# This file deliberately is NOT named *.Tests.ps1 so Pester does not run it as a
# test file.

function New-TestLedger {
    <#
    .SYNOPSIS
    Creates a journal for tests and returns its path.

    .DESCRIPTION
    Builds a journal with the BAS-Smaforetag chart and a 2024 fiscal year by
    default, optionally adding journal metadata, customers and suppliers. Every
    part can be overridden or skipped so a single helper covers the setups the
    test files currently duplicate.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Root,

        [string]$Name = 'Faktura AB',

        [string]$CompanyType = 'AB',

        # Skip importing a chart of accounts.
        [switch]$NoChart,

        [string]$ChartTemplate = 'BAS-Smaforetag',

        # Skip creating the fiscal year.
        [switch]$NoFiscalYear,

        [string]$StartDate = '2024-01-01',

        [string]$EndDate = '2024-12-31',

        [hashtable]$Metadata,

        # Customers to add. Each hashtable: @{ Number = '10'; Name = 'Volvo AB';
        # PaymentTermsDays = 30; OrgNumber = '556012-5790' }. Only Number and
        # Name are required.
        [hashtable[]]$Customers,

        # Suppliers to add. Each hashtable: @{ Number = '100'; Name = 'Alpha AB';
        # PaymentTermsDays = 30 }.
        [hashtable[]]$Suppliers
    )

    $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
    New-LedgerJournal -Path $path -Name $Name -CompanyType $CompanyType | Out-Null

    if (-not $NoChart) {
        Import-LedgerChart -JournalPath $path -Template $ChartTemplate
    }
    if (-not $NoFiscalYear) {
        New-LedgerFiscalYear -JournalPath $path -StartDate $StartDate -EndDate $EndDate
    }
    if ($Metadata) {
        Set-LedgerJournal -JournalPath $path -Metadata $Metadata | Out-Null
    }

    foreach ($c in $Customers) {
        $params = @{
            JournalPath      = $path
            CustomerNumber   = $c.Number
            Name             = $c.Name
            PaymentTermsDays = if ($c.ContainsKey('PaymentTermsDays')) { $c.PaymentTermsDays } else { 30 }
        }
        if ($c.ContainsKey('OrgNumber')) { $params.OrgNumber = $c.OrgNumber }
        Add-LedgerCustomer @params
    }

    foreach ($s in $Suppliers) {
        $params = @{
            JournalPath      = $path
            SupplierNumber   = $s.Number
            Name             = $s.Name
            PaymentTermsDays = if ($s.ContainsKey('PaymentTermsDays')) { $s.PaymentTermsDays } else { 30 }
        }
        Add-LedgerSupplier @params
    }

    return $path
}

function New-TestPostedInvoice {
    <#
    .SYNOPSIS
    Creates a customer invoice and (by default) posts it, returning its number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [string]$CustomerNumber = '10',

        [string]$Date = '2024-03-15',

        [decimal]$Net = 10000,

        [string]$Description = 'Tjänst',

        # Explicit invoice rows. Defaults to a single 3010 row with 25% VAT.
        [hashtable[]]$Rows,

        # Create the invoice as a draft without posting it.
        [switch]$NoPost
    )

    if (-not $Rows) {
        $Rows = @(@{ Account = '3010'; Amount = $Net; VatRate = 0.25; VatAccount = '2610' })
    }

    $inv = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber $CustomerNumber `
        -Date $Date -Description $Description -Rows $Rows -PassThru

    if (-not $NoPost) {
        Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber $inv.InvoiceNumber
    }

    return $inv.InvoiceNumber
}

function New-TestPostedSupplierInvoice {
    <#
    .SYNOPSIS
    Creates a supplier invoice and (by default) posts it, returning its number.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [string]$SupplierNumber = '100',

        [string]$Date = '2024-03-15',

        [decimal]$Net = 8000,

        [string]$Description = 'Kostnad',

        [hashtable[]]$Rows,

        [switch]$NoPost
    )

    if (-not $Rows) {
        $Rows = @(@{ Account = '5010'; Amount = $Net; VatRate = 0.25; VatAccount = '2640' })
    }

    $inv = New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber $SupplierNumber `
        -Date $Date -Description $Description -Rows $Rows -PassThru

    if (-not $NoPost) {
        Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath -InvoiceNumber $inv.InvoiceNumber
    }

    return $inv.InvoiceNumber
}
