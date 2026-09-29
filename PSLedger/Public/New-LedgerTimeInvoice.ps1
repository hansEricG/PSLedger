<#
.SYNOPSIS
Invoices a customer's reported time.

.DESCRIPTION
Collects the customer's open, billable time up to and including -Through and
creates a customer invoice (draft) with New-LedgerInvoice. By default there is
one invoice row per project, resource and hourly rate, e.g.
"Ny kundportal – Anna Andersson, mars 2024" with the hours as quantity, 'h' as
unit and the hourly rate as unit price. With -PerEntry there is one row per
time entry instead, with its date and text.

The time entries are linked to the invoice and become 'Invoiced'; they can no
longer be changed or removed. If the invoice is credited with
Add-LedgerCreditInvoice the entries become 'Open' again and can be invoiced
anew.

Post the invoice with Invoke-LedgerInvoicePosting and export it with
Export-LedgerInvoice as usual.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER CustomerNumber
The customer to invoice.

.PARAMETER Through
The last date of time to include. Defaults to today.

.PARAMETER From
Optional. The first date of time to include.

.PARAMETER Project
Optional. Only invoice time on these projects.

.PARAMETER Date
The invoice date. Defaults to today.

.PARAMETER DueDate
Optional due date; defaults to the invoice date plus the customer's payment
terms.

.PARAMETER Description
The invoice description. Defaults to 'Konsulttjänster <period>'.

.PARAMETER Account
The revenue account. Defaults to '3010'.

.PARAMETER VatRate
The VAT rate. Defaults to 0.25.

.PARAMETER VatAccount
The output VAT account. Defaults to '2610'.

.PARAMETER PerEntry
One invoice row per time entry instead of per project and resource.

.PARAMETER PassThru
Returns the created invoice.

.EXAMPLE
New-LedgerTimeInvoice -CustomerNumber 10 -Through 2024-03-31 -Date 2024-03-31

Invoices Volvo AB's open time up to the end of March.

.EXAMPLE
$inv = New-LedgerTimeInvoice -CustomerNumber 10 -Project 1001 -Through 2024-03-31 -PerEntry -PassThru
Invoke-LedgerInvoicePosting -InvoiceNumber $inv.InvoiceNumber
Export-LedgerInvoice -InvoiceNumber $inv.InvoiceNumber -Path ".\faktura-$($inv.InvoiceNumber).pdf"

Invoices one project with a row per entry, posts the invoice and exports it.
#>
function New-LedgerTimeInvoice {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$CustomerNumber,

        [Parameter()]
        [datetime]$Through = (Get-Date).Date,

        [Parameter()]
        [datetime]$From,

        [Parameter()]
        [string[]]$Project,

        [Parameter()]
        [datetime]$Date = (Get-Date).Date,

        [Parameter()]
        [datetime]$DueDate,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Account = '3010',

        [Parameter()]
        [ValidateRange(0, 1)]
        [decimal]$VatRate = 0.25,

        [Parameter()]
        [string]$VatAccount = '2610',

        [Parameter()]
        [switch]$PerEntry,

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    if (-not (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber $CustomerNumber)) {
        throw "Customer '$CustomerNumber' does not exist."
    }

    $entries = @(Read-LedgerTimeEntries -JournalPath $JournalPath)
    $context = Get-LedgerTimeContext -JournalPath $JournalPath
    $invoiceStatus = Get-LedgerTimeInvoiceStatusMap -JournalPath $JournalPath

    $selected = @($entries | Where-Object {
            $_.CustomerNumber -eq $CustomerNumber -and $_.Billable -and $_.Date -le $Through.Date -and
            (-not $PSBoundParameters.ContainsKey('From') -or $_.Date -ge $From.Date) -and
            (-not $Project -or $_.ProjectNumber -in $Project) -and
            -not (Test-LedgerTimeEntryInvoiced -Entry $_ -InvoiceStatus $invoiceStatus)
        })
    if (-not $selected) {
        Write-Warning "Customer $CustomerNumber has no open billable time up to $($Through.ToString('yyyy-MM-dd'))."
        return
    }
    $missingRate = @($selected | Where-Object { $null -eq $_.Rate })
    if ($missingRate) {
        throw "Time entries without an hourly rate: $(($missingRate.EntryId) -join ', '). Set one with Set-LedgerTimeEntry -Rate."
    }

    $sv = [System.Globalization.CultureInfo]::GetCultureInfo('sv-SE')
    $periodText = {
        param($items)
        $min = ($items | Measure-Object -Property Date -Minimum).Minimum
        $max = ($items | Measure-Object -Property Date -Maximum).Maximum
        if ($min.ToString('yyyy-MM') -eq $max.ToString('yyyy-MM')) { $min.ToString('MMMM yyyy', $sv) }
        else { "$($min.ToString('yyyy-MM-dd')) – $($max.ToString('yyyy-MM-dd'))" }
    }
    $nameOf = {
        param($list, $key, $value)
        $item = $list | Where-Object $key -eq $value | Select-Object -First 1
        if ($item -and $item.Name) { $item.Name } else { $value }
    }

    $baseRow = @{ Account = $Account; Unit = 'h' }
    if ($VatRate -gt 0) { $baseRow.VatRate = $VatRate; $baseRow.VatAccount = $VatAccount }

    $rows = [System.Collections.Generic.List[hashtable]]::new()
    if ($PerEntry) {
        foreach ($e in ($selected | Sort-Object Date, EntryId)) {
            $who = & $nameOf $context.Resources 'ResourceId' $e.ResourceId
            $label = if ($e.ProjectNumber) { "$(& $nameOf $context.Projects 'ProjectNumber' $e.ProjectNumber), $who" } else { $who }
            $text = "$($e.Date.ToString('yyyy-MM-dd')) $label"
            if ($e.Text) { $text += ": $($e.Text)" }
            $row = $baseRow.Clone()
            $row.Description = $text; $row.Quantity = $e.Hours; $row.UnitPrice = $e.Rate
            $rows.Add($row)
        }
    }
    else {
        $groups = $selected | Group-Object ProjectNumber, ResourceId, { Format-LedgerInvoiceAmount -Value ([decimal]$_.Rate) }
        $ordered = $groups | Sort-Object { $_.Group[0].ProjectNumber }, { & $nameOf $context.Resources 'ResourceId' $_.Group[0].ResourceId }, { [decimal]$_.Group[0].Rate }
        foreach ($g in $ordered) {
            $first = $g.Group[0]
            $who = & $nameOf $context.Resources 'ResourceId' $first.ResourceId
            $label = if ($first.ProjectNumber) { "$(& $nameOf $context.Projects 'ProjectNumber' $first.ProjectNumber) – $who" } else { $who }
            $hours = [decimal]0
            foreach ($e in $g.Group) { $hours += [decimal]$e.Hours }
            $row = $baseRow.Clone()
            $row.Description = "$label, $(& $periodText $g.Group)"
            $row.Quantity = $hours; $row.UnitPrice = [decimal]$first.Rate
            $rows.Add($row)
        }
    }

    if (-not $Description) { $Description = "Konsulttjänster $(& $periodText $selected)" }
    $totalHours = ($selected | Measure-Object -Property Hours -Sum).Sum
    if (-not $PSCmdlet.ShouldProcess("Customer $CustomerNumber", "Invoice $totalHours h in $($selected.Count) time entries")) { return }

    $invoiceParams = @{
        JournalPath    = $JournalPath
        CustomerNumber = $CustomerNumber
        Date           = $Date
        Description    = $Description
        Rows           = $rows.ToArray()
        PassThru       = $true
        WhatIf         = $false
        Confirm        = $false
    }
    if ($PSBoundParameters.ContainsKey('DueDate')) { $invoiceParams.DueDate = $DueDate }
    $invoice = New-LedgerInvoice @invoiceParams

    try {
        foreach ($e in $selected) { $e.InvoiceNumber = [int]$invoice.InvoiceNumber }
        $months = @($selected | ForEach-Object { $_.Date.ToString('yyyy-MM') } | Select-Object -Unique)
        Save-LedgerTimeEntries -JournalPath $JournalPath -Entries $entries -Months $months
    }
    catch {
        # Without the link the time would be invoiced twice; undo the invoice.
        Remove-Item -LiteralPath $invoice.FilePath -Force -ErrorAction SilentlyContinue
        throw
    }

    if ($PassThru) { $invoice }
}
