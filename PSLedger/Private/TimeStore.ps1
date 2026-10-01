# Helpers for time reporting (tidrapportering). Everything is stored as plain,
# tab-separated text under the journal's 'time/' directory:
#
#   time/resources.txt  ResourceId, Name, EmployeeNumber, SupplierNumber, CostRate, IsDefault
#   time/projects.txt   ProjectNumber, Name, CustomerNumber, HourlyRate, Status
#   time/yyyy-MM.txt    EntryId, Date, ResourceId, ProjectNumber, CustomerNumber,
#                       Hours, Billable, Rate, Text, InvoiceNumber
#
# Time entries are split into one file per month so the files stay small and
# readable. Entry ids are unique across all months. An entry is 'Invoiced'
# while the invoice it is linked to exists and is not credited; crediting the
# invoice makes the entry 'Open' again so it can be invoiced anew.

function Get-LedgerTimeDirectory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [switch]$Create
    )
    $dir = Join-Path $JournalPath 'time'
    if ($Create -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function ConvertTo-LedgerTimeField {
    <#
    .SYNOPSIS
    Makes a value safe for a tab-separated field (no tabs or line breaks).
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value
    )
    if ($null -eq $Value) { return '' }
    return ([string]$Value -replace '[\t\r\n]+', ' ').Trim()
}

function ConvertFrom-LedgerHours {
    <#
    .SYNOPSIS
    Parses hours written as a decimal ('7.5', '7,5') or as a duration
    ('7:30', '07:30:00').
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )
    $t = $Text.Trim() -replace '(?i)\s*(h|tim|timmar)$', ''
    if ($t -match '^(\d+):(\d{1,2})(?::(\d{1,2}))?$') {
        $seconds = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + $(if ($Matches[3]) { [int]$Matches[3] } else { 0 })
        return [Math]::Round([decimal]$seconds / 3600, 2)
    }
    $value = [decimal]0
    if ([decimal]::TryParse($t.Replace(',', '.'), [System.Globalization.NumberStyles]::AllowDecimalPoint,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
        return [Math]::Round($value, 2)
    }
    throw "Could not parse hours '$Text'."
}

function Test-LedgerHours {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [decimal]$Hours
    )
    if ($Hours -le 0 -or $Hours -gt 24) {
        throw "Hours must be greater than 0 and at most 24 (got $Hours)."
    }
}

function Read-LedgerTimeResources {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    $file = Join-Path (Get-LedgerTimeDirectory -JournalPath $JournalPath) 'resources.txt'
    if (-not (Test-Path $file)) { return }
    foreach ($line in (Get-Content -Path $file -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*;') { continue }
        $p = $line -split "`t"
        [PSCustomObject]@{
            ResourceId     = $p[0]
            Name           = if ($p.Count -ge 2) { $p[1] } else { '' }
            EmployeeNumber = if ($p.Count -ge 3) { $p[2] } else { '' }
            SupplierNumber = if ($p.Count -ge 4) { $p[3] } else { '' }
            CostRate       = if ($p.Count -ge 5 -and $p[4]) { ConvertFrom-LedgerInvoiceAmount -Text $p[4] } else { $null }
            IsDefault      = ($p.Count -ge 6 -and $p[5] -eq '1')
        }
    }
}

function Save-LedgerTimeResources {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Resources
    )
    $dir = Get-LedgerTimeDirectory -JournalPath $JournalPath -Create
    $lines = foreach ($r in $Resources) {
        $cost = if ($null -ne $r.CostRate) { Format-LedgerInvoiceAmount -Value ([decimal]$r.CostRate) } else { '' }
        @(
            (ConvertTo-LedgerTimeField $r.ResourceId)
            (ConvertTo-LedgerTimeField $r.Name)
            (ConvertTo-LedgerTimeField $r.EmployeeNumber)
            (ConvertTo-LedgerTimeField $r.SupplierNumber)
            $cost
            $(if ($r.IsDefault) { '1' } else { '' })
        ) -join "`t"
    }
    Set-LedgerFileContent -Path (Join-Path $dir 'resources.txt') -Value @($lines)
}

function Read-LedgerProjects {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    $file = Join-Path (Get-LedgerTimeDirectory -JournalPath $JournalPath) 'projects.txt'
    if (-not (Test-Path $file)) { return }
    foreach ($line in (Get-Content -Path $file -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*;') { continue }
        $p = $line -split "`t"
        [PSCustomObject]@{
            ProjectNumber  = $p[0]
            Name           = if ($p.Count -ge 2) { $p[1] } else { '' }
            CustomerNumber = if ($p.Count -ge 3) { $p[2] } else { '' }
            HourlyRate     = if ($p.Count -ge 4 -and $p[3]) { ConvertFrom-LedgerInvoiceAmount -Text $p[3] } else { $null }
            Status         = if ($p.Count -ge 5 -and $p[4]) { $p[4] } else { 'Active' }
        }
    }
}

function Save-LedgerProjects {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Projects
    )
    $dir = Get-LedgerTimeDirectory -JournalPath $JournalPath -Create
    $lines = foreach ($p in $Projects) {
        $rate = if ($null -ne $p.HourlyRate) { Format-LedgerInvoiceAmount -Value ([decimal]$p.HourlyRate) } else { '' }
        @(
            (ConvertTo-LedgerTimeField $p.ProjectNumber)
            (ConvertTo-LedgerTimeField $p.Name)
            (ConvertTo-LedgerTimeField $p.CustomerNumber)
            $rate
            $p.Status
        ) -join "`t"
    }
    Set-LedgerFileContent -Path (Join-Path $dir 'projects.txt') -Value @($lines)
}

function Read-LedgerTimeEntries {
    <#
    .SYNOPSIS
    Reads the stored time entries from all month files, oldest first.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    $dir = Get-LedgerTimeDirectory -JournalPath $JournalPath
    if (-not (Test-Path $dir)) { return }
    $files = Get-ChildItem -Path $dir -File | Where-Object { $_.Name -match '^\d{4}-\d{2}\.txt$' } | Sort-Object Name
    $entries = foreach ($f in $files) {
        foreach ($line in (Get-Content -Path $f.FullName -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*;') { continue }
            $p = $line -split "`t"
            if ($p.Count -lt 6) { continue }
            [PSCustomObject]@{
                EntryId        = [int]$p[0]
                Date           = [datetime]::ParseExact($p[1], 'yyyy-MM-dd', $null)
                ResourceId     = $p[2]
                ProjectNumber  = $p[3]
                CustomerNumber = $p[4]
                Hours          = ConvertFrom-LedgerInvoiceAmount -Text $p[5]
                Billable       = ($p.Count -lt 7 -or $p[6] -ne '0')
                Rate           = if ($p.Count -ge 8 -and $p[7]) { ConvertFrom-LedgerInvoiceAmount -Text $p[7] } else { $null }
                Text           = if ($p.Count -ge 9) { $p[8] } else { '' }
                InvoiceNumber  = if ($p.Count -ge 10 -and $p[9]) { [int]$p[9] } else { $null }
            }
        }
    }
    @($entries) | Sort-Object Date, EntryId
}

function Save-LedgerTimeEntries {
    <#
    .SYNOPSIS
    Rewrites the month files for the given months from the full entry set.
    A month without entries has its file removed.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries,

        [Parameter(Mandatory)]
        [string[]]$Months
    )
    $dir = Get-LedgerTimeDirectory -JournalPath $JournalPath -Create
    foreach ($month in ($Months | Select-Object -Unique)) {
        $path = Join-Path $dir "$month.txt"
        $inMonth = @($Entries | Where-Object { $_.Date.ToString('yyyy-MM') -eq $month } | Sort-Object Date, EntryId)
        if (-not $inMonth) {
            if (Test-Path $path) { Remove-Item -LiteralPath $path -Force }
            continue
        }
        $lines = foreach ($e in $inMonth) {
            @(
                $e.EntryId
                $e.Date.ToString('yyyy-MM-dd')
                (ConvertTo-LedgerTimeField $e.ResourceId)
                (ConvertTo-LedgerTimeField $e.ProjectNumber)
                (ConvertTo-LedgerTimeField $e.CustomerNumber)
                (Format-LedgerInvoiceAmount -Value ([decimal]$e.Hours))
                $(if ($e.Billable) { '1' } else { '0' })
                $(if ($null -ne $e.Rate) { Format-LedgerInvoiceAmount -Value ([decimal]$e.Rate) } else { '' })
                (ConvertTo-LedgerTimeField $e.Text)
                $(if ($e.InvoiceNumber) { $e.InvoiceNumber } else { '' })
            ) -join "`t"
        }
        Set-LedgerFileContent -Path $path -Value @($lines)
    }
}

function Get-LedgerTimeInvoiceStatusMap {
    <#
    .SYNOPSIS
    Returns a hashtable of invoice number -> status for resolving entry status.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    $map = @{}
    foreach ($inv in @(Get-LedgerInvoice -JournalPath $JournalPath)) { $map[[int]$inv.InvoiceNumber] = $inv.Status }
    return $map
}

function Test-LedgerTimeEntryInvoiced {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Entry,

        [Parameter(Mandatory)]
        [hashtable]$InvoiceStatus
    )
    return [bool]($Entry.InvoiceNumber -and $InvoiceStatus.ContainsKey([int]$Entry.InvoiceNumber) -and
        $InvoiceStatus[[int]$Entry.InvoiceNumber] -ne 'Credited')
}

function Resolve-LedgerTimeRate {
    <#
    .SYNOPSIS
    Returns the hourly rate for time on a project/customer: the project's rate,
    otherwise the customer's rate, otherwise $null.
    #>
    [CmdletBinding()]
    param (
        [psobject]$Project,
        [psobject]$Customer
    )
    if ($Project -and $null -ne $Project.HourlyRate) { return [decimal]$Project.HourlyRate }
    if ($Customer -and $Customer.PSObject.Properties['HourlyRate'] -and $null -ne $Customer.HourlyRate) { return [decimal]$Customer.HourlyRate }
    return $null
}

function Resolve-LedgerTimeEntryTarget {
    <#
    .SYNOPSIS
    Validates resource, project and customer for a new or changed time entry
    and resolves the customer, billable flag and rate.

    .DESCRIPTION
    The customer follows the project. Time on a project without a customer is
    internal and never billable. Billable time needs an hourly rate: the given
    rate, the project's rate or the customer's rate.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [string]$ResourceId,
        [string]$ProjectNumber,
        [string]$CustomerNumber,
        [bool]$Billable = $true,
        [Nullable[decimal]]$Rate
    )
    if (-not $ResourceId) {
        $default = @($Context.Resources | Where-Object IsDefault | Select-Object -First 1)
        if (-not $default) {
            if (-not $Context.Resources) { throw 'No time resources exist. Add yourself with Add-LedgerTimeResource first.' }
            throw 'No default time resource. Specify -Resource or mark one with Set-LedgerTimeResource -Default.'
        }
        $ResourceId = $default[0].ResourceId
    }
    elseif (-not ($Context.Resources | Where-Object ResourceId -eq $ResourceId)) {
        throw "Time resource '$ResourceId' does not exist."
    }

    $project = $null
    if ($ProjectNumber) {
        $project = $Context.Projects | Where-Object ProjectNumber -eq $ProjectNumber | Select-Object -First 1
        if (-not $project) { throw "Project '$ProjectNumber' does not exist." }
        if ($project.Status -eq 'Closed') { throw "Project '$ProjectNumber' is closed." }
        if ($CustomerNumber -and $project.CustomerNumber -and $CustomerNumber -ne $project.CustomerNumber) {
            throw "Project '$ProjectNumber' belongs to customer $($project.CustomerNumber), not $CustomerNumber."
        }
        $CustomerNumber = $project.CustomerNumber
    }
    elseif (-not $CustomerNumber) {
        throw 'Specify -Project or -CustomerNumber.'
    }

    $customer = $null
    if ($CustomerNumber) {
        $customer = $Context.Customers | Where-Object CustomerNumber -eq $CustomerNumber | Select-Object -First 1
        if (-not $customer) { throw "Customer '$CustomerNumber' does not exist." }
    }
    else {
        $Billable = $false
    }

    if ($null -eq $Rate) { $Rate = Resolve-LedgerTimeRate -Project $project -Customer $customer }
    if ($Billable -and $null -eq $Rate) {
        $where = if ($project) { "project $ProjectNumber or customer $CustomerNumber" } else { "customer $CustomerNumber" }
        throw "No hourly rate for $where. Specify -Rate, or set it with Set-LedgerProject/Set-LedgerCustomer -HourlyRate."
    }

    return @{
        ResourceId     = $ResourceId
        ProjectNumber  = [string]$ProjectNumber
        CustomerNumber = [string]$CustomerNumber
        Billable       = $Billable
        Rate           = $Rate
    }
}

function Get-LedgerTimeContext {
    <#
    .SYNOPSIS
    Loads the registers needed to validate and describe time entries.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$JournalPath
    )
    return @{
        Resources = @(Read-LedgerTimeResources -JournalPath $JournalPath)
        Projects  = @(Read-LedgerProjects -JournalPath $JournalPath)
        Customers = @(Get-LedgerCustomer -JournalPath $JournalPath)
    }
}

function ConvertTo-LedgerTimeEntryOutput {
    <#
    .SYNOPSIS
    Turns a stored entry into the public output object with names, amount and
    status resolved.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Entry,

        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [hashtable]$InvoiceStatus
    )
    $resource = $Context.Resources | Where-Object ResourceId -eq $Entry.ResourceId | Select-Object -First 1
    $project = if ($Entry.ProjectNumber) { $Context.Projects | Where-Object ProjectNumber -eq $Entry.ProjectNumber | Select-Object -First 1 }
    $customer = if ($Entry.CustomerNumber) { $Context.Customers | Where-Object CustomerNumber -eq $Entry.CustomerNumber | Select-Object -First 1 }
    $invoiced = Test-LedgerTimeEntryInvoiced -Entry $Entry -InvoiceStatus $InvoiceStatus
    $amount = if ($Entry.Billable -and $null -ne $Entry.Rate) { [Math]::Round([decimal]$Entry.Hours * [decimal]$Entry.Rate, 2) } else { [decimal]0 }
    [PSCustomObject]@{
        EntryId        = $Entry.EntryId
        Date           = $Entry.Date
        ResourceId     = $Entry.ResourceId
        ResourceName   = if ($resource) { $resource.Name } else { '' }
        ProjectNumber  = $Entry.ProjectNumber
        ProjectName    = if ($project) { $project.Name } else { '' }
        CustomerNumber = $Entry.CustomerNumber
        CustomerName   = if ($customer) { $customer.Name } else { '' }
        Hours          = $Entry.Hours
        Billable       = $Entry.Billable
        Rate           = $Entry.Rate
        Amount         = $amount
        Text           = $Entry.Text
        Status         = if ($invoiced) { 'Invoiced' } else { 'Open' }
        InvoiceNumber  = if ($invoiced) { $Entry.InvoiceNumber } else { $null }
    }
}
