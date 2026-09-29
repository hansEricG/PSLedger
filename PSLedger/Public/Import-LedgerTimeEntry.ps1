<#
.SYNOPSIS
Imports time from a CSV file, e.g. an export from Excel, Toggl or Harvest.

.DESCRIPTION
Reads a CSV file with one time entry per row and adds the entries to the
journal. The header row, delimiter (';', ',' or tab) and encoding are detected
automatically, and columns are recognised from common Swedish and English
names:

- Date: Datum, Date, Start date, Startdatum, Dag
- Hours: Timmar, Tid, Antal timmar, Hours, Duration (decimal or h:mm[:ss])
- Project: Projekt, Projektnummer, Project (number or name)
- Customer: Kund, Kundnummer, Client, Customer (number or name)
- Resource: Resurs, Person, Konsult, Medarbetare, User (id or name)
- Text: Beskrivning, Text, Aktivitet, Kommentar, Description, Notes, Task
- Billable: Debiterbar, Fakturerbar, Billable, Billable? (ja/nej, yes/no, 1/0)

Override a column with the matching -*Column parameter. Rows without a
resource get -Resource or the default resource; rows without a project or
customer get -Project.

The import is all or nothing: if any row cannot be imported (unknown project,
missing hourly rate, invalid hours, ...) nothing is imported and all problems
are reported. Rows that are already imported (same date, resource, project,
customer, hours and text) are skipped, so an overlapping export can be
imported again safely.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Path
The CSV file to import.

.PARAMETER Resource
Resource for rows without a resource column value.

.PARAMETER Project
Project for rows without a project or customer.

.PARAMETER Delimiter
The field delimiter, if not detected correctly.

.PARAMETER Encoding
The file encoding (e.g. 'utf-8', 'windows-1252'), if not detected correctly.

.PARAMETER DateFormat
The date format (e.g. 'dd/MM/yyyy'), if not ISO.

.PARAMETER DateColumn
Name of the date column.

.PARAMETER HoursColumn
Name of the hours column.

.PARAMETER ProjectColumn
Name of the project column.

.PARAMETER CustomerColumn
Name of the customer column.

.PARAMETER ResourceColumn
Name of the resource column.

.PARAMETER TextColumn
Name of the text column.

.PARAMETER BillableColumn
Name of the billable column.

.EXAMPLE
Import-LedgerTimeEntry -Path .\tid-mars.csv

Imports a file with the columns Datum;Projekt;Timmar;Beskrivning for the
default resource.

.EXAMPLE
Import-LedgerTimeEntry -Path .\toggl.csv -ResourceColumn 'User' -WhatIf

Previews an import of a Toggl export where the user column holds the resource
names.
#>
function Import-LedgerTimeEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Resource,

        [Parameter()]
        [string]$Project,

        [Parameter()]
        [ValidateSet(';', ',', "`t")]
        [string]$Delimiter,

        [Parameter()]
        [string]$Encoding,

        [Parameter()]
        [string]$DateFormat,

        [string]$DateColumn,
        [string]$HoursColumn,
        [string]$ProjectColumn,
        [string]$CustomerColumn,
        [string]$ResourceColumn,
        [string]$TextColumn,
        [string]$BillableColumn
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }

    $candidates = [ordered]@{
        Date     = @('Datum', 'Date', 'Start date', 'Startdatum', 'Dag')
        Hours    = @('Timmar', 'Tid', 'Antal timmar', 'Hours', 'Duration')
        Project  = @('Projekt', 'Projektnummer', 'Project')
        Customer = @('Kund', 'Kundnummer', 'Client', 'Customer')
        Resource = @('Resurs', 'Person', 'Konsult', 'Medarbetare', 'User')
        Text     = @('Beskrivning', 'Text', 'Aktivitet', 'Kommentar', 'Description', 'Notes', 'Task')
        Billable = @('Debiterbar', 'Fakturerbar', 'Billable', 'Billable?')
    }
    $explicit = @{
        Date = $DateColumn; Hours = $HoursColumn; Project = $ProjectColumn; Customer = $CustomerColumn
        Resource = $ResourceColumn; Text = $TextColumn; Billable = $BillableColumn
    }

    $lines = (Read-LedgerBankTextFile -Path $Path -Encoding $Encoding) -split "\r?\n"
    $delimiters = if ($Delimiter) { @($Delimiter) } else { @(';', ',', "`t") }
    $headerIndex = -1; $columns = $null; $delim = $null
    for ($i = 0; $i -lt [Math]::Min($lines.Count, 50) -and $headerIndex -lt 0; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        foreach ($d in $delimiters) {
            $header = Split-LedgerCsvLine -Line $lines[$i] -Delimiter $d
            $map = @{}
            foreach ($key in $candidates.Keys) {
                $names = if ($explicit[$key]) { @($explicit[$key]) } else { $candidates[$key] }
                foreach ($name in $names) {
                    $idx = [array]::FindIndex([string[]]$header, [Predicate[string]] { param($h) $h -ieq $name })
                    if ($idx -ge 0) { $map[$key] = $idx; break }
                }
            }
            if ($map.ContainsKey('Date') -and $map.ContainsKey('Hours')) {
                $headerIndex = $i; $columns = $map; $delim = $d
                break
            }
        }
    }
    if ($headerIndex -lt 0) {
        throw "No header row with a date and an hours column found in '$Path'. Use -DateColumn and -HoursColumn."
    }

    $context = Get-LedgerTimeContext -JournalPath $JournalPath
    $findBy = {
        param($list, $idProperty, $value)
        $hit = @($list | Where-Object $idProperty -eq $value)
        if (-not $hit) { $hit = @($list | Where-Object { $_.Name -ieq $value }) }
        if ($hit.Count -gt 1) { throw "'$value' matches several entries." }
        if ($hit) { $hit[0].$idProperty } else { $null }
    }
    $field = {
        param($parts, $key)
        if ($columns.ContainsKey($key) -and $columns[$key] -lt $parts.Count) { $parts[$columns[$key]] } else { '' }
    }

    $existing = @(Read-LedgerTimeEntries -JournalPath $JournalPath)
    $fingerprint = {
        param($e)
        '{0}|{1}|{2}|{3}|{4}|{5}' -f $e.Date.ToString('yyyy-MM-dd'), $e.ResourceId, $e.ProjectNumber, $e.CustomerNumber,
            (Format-LedgerInvoiceAmount -Value ([decimal]$e.Hours)), (ConvertTo-LedgerTimeField $e.Text)
    }
    $existingCount = @{}
    foreach ($e in $existing) { $k = & $fingerprint $e; $existingCount[$k] = 1 + [int]$existingCount[$k] }

    $errors = [System.Collections.Generic.List[string]]::new()
    $new = [System.Collections.Generic.List[object]]::new()
    $seenCount = @{}
    $skipped = 0
    $nextId = if ($existing) { ($existing | Measure-Object -Property EntryId -Maximum).Maximum + 1 } else { 1 }

    for ($i = $headerIndex + 1; $i -lt $lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        $parts = Split-LedgerCsvLine -Line $lines[$i] -Delimiter $delim
        $rowNo = $i + 1
        try {
            $dateText = & $field $parts 'Date'
            if (-not $dateText) { throw 'Missing date.' }
            $date = ConvertFrom-LedgerBankDate -Text $dateText -DateFormat $DateFormat
            $hours = ConvertFrom-LedgerHours -Text (& $field $parts 'Hours')
            Test-LedgerHours -Hours $hours

            $resourceValue = & $field $parts 'Resource'
            $resourceId = if ($resourceValue) {
                $r = & $findBy $context.Resources 'ResourceId' $resourceValue
                if (-not $r) { throw "Unknown resource '$resourceValue'." }
                $r
            } else { $Resource }

            $projectValue = & $field $parts 'Project'
            $customerValue = & $field $parts 'Customer'
            $projectNumber = if ($projectValue) {
                $p = & $findBy $context.Projects 'ProjectNumber' $projectValue
                if (-not $p) { throw "Unknown project '$projectValue'." }
                $p
            } elseif (-not $customerValue) { $Project } else { '' }
            $customerNumber = ''
            if ($customerValue -and -not $projectValue) {
                $customerNumber = & $findBy $context.Customers 'CustomerNumber' $customerValue
                if (-not $customerNumber) { throw "Unknown customer '$customerValue'." }
            }

            $billableText = (& $field $parts 'Billable').Trim()
            $billable = switch -Regex ($billableText) {
                '^(?i)(ja|yes|true|1|x|j|y)$' { $true; break }
                '^(?i)(nej|no|false|0|n)$' { $false; break }
                '^$' { $true; break }
                default { throw "Unknown billable value '$billableText'." }
            }

            $target = Resolve-LedgerTimeEntryTarget -Context $context -ResourceId $resourceId -ProjectNumber $projectNumber `
                -CustomerNumber $customerNumber -Billable $billable
            $entry = [PSCustomObject]@{
                EntryId        = 0
                Date           = $date
                ResourceId     = $target.ResourceId
                ProjectNumber  = $target.ProjectNumber
                CustomerNumber = $target.CustomerNumber
                Hours          = $hours
                Billable       = $target.Billable
                Rate           = $target.Rate
                Text           = ConvertTo-LedgerTimeField (& $field $parts 'Text')
                InvoiceNumber  = $null
            }

            $k = & $fingerprint $entry
            $seenCount[$k] = 1 + [int]$seenCount[$k]
            if ($seenCount[$k] -le [int]$existingCount[$k]) { $skipped++; continue }
            $new.Add($entry)
        }
        catch {
            $errors.Add("Row ${rowNo}: $($_.Exception.Message)")
        }
    }

    if ($errors.Count) {
        throw "Nothing was imported from '$Path':`n$($errors -join "`n")"
    }

    $totalHours = [decimal]0
    foreach ($e in $new) { $e.EntryId = [int]$nextId; $nextId++; $totalHours += $e.Hours }
    if ($skipped) { Write-Verbose "$skipped already imported rows skipped." }

    $summary = [PSCustomObject]@{
        Path     = $Path
        Imported = $new.Count
        Skipped  = $skipped
        Hours    = $totalHours
    }
    if ($new.Count -and $PSCmdlet.ShouldProcess([System.IO.Path]::GetFileName($Path), "Import $($new.Count) time entries ($totalHours h)")) {
        $months = @($new | ForEach-Object { $_.Date.ToString('yyyy-MM') } | Select-Object -Unique)
        Save-LedgerTimeEntries -JournalPath $JournalPath -Entries (@($existing) + $new.ToArray()) -Months $months
    }
    $summary
}
