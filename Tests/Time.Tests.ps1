BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    # Journal with two customers, two resources, a billable project with its
    # own rate and an internal project. Customer 20 has an hourly rate.
    function New-TimeTestJournal {
        param([string]$Root)
        $j = New-TestLedger -Root $Root -Customers @(
            @{ Number = '10'; Name = 'Volvo AB' },
            @{ Number = '20'; Name = 'Scania AB' }
        )
        Set-LedgerCustomer -JournalPath $j -CustomerNumber 20 -HourlyRate 900
        Add-LedgerTimeResource -JournalPath $j -ResourceId 'HEG' -Name 'Hans-Eric'
        Add-LedgerTimeResource -JournalPath $j -ResourceId 'KON' -Name 'Konsult Kalle' -CostRate 700
        Add-LedgerProject -JournalPath $j -ProjectNumber 'P1' -Name 'Webbshop' -CustomerNumber 10 -HourlyRate 1100
        Add-LedgerProject -JournalPath $j -ProjectNumber 'INT' -Name 'Intern admin'
        return $j
    }
}

Describe 'Time commands metadata' {
    It '<_> is an advanced function' -ForEach @(
        'Add-LedgerTimeResource', 'Get-LedgerTimeResource', 'Set-LedgerTimeResource',
        'Add-LedgerProject', 'Get-LedgerProject', 'Set-LedgerProject',
        'Add-LedgerTimeEntry', 'Get-LedgerTimeEntry', 'Set-LedgerTimeEntry', 'Remove-LedgerTimeEntry',
        'Import-LedgerTimeEntry', 'Get-LedgerTimeReport', 'New-LedgerTimeInvoice'
    ) {
        Test-TDDCmdletBinding (Get-Command -Name $_) | Should -BeTrue
    }

    It '<Command> has a mandatory <Parameter> parameter' -ForEach @(
        @{ Command = 'Add-LedgerTimeResource'; Parameter = 'ResourceId' }
        @{ Command = 'Add-LedgerTimeResource'; Parameter = 'Name' }
        @{ Command = 'Add-LedgerProject'; Parameter = 'ProjectNumber' }
        @{ Command = 'Add-LedgerProject'; Parameter = 'Name' }
        @{ Command = 'Add-LedgerTimeEntry'; Parameter = 'Hours' }
        @{ Command = 'Set-LedgerTimeEntry'; Parameter = 'EntryId' }
        @{ Command = 'Remove-LedgerTimeEntry'; Parameter = 'EntryId' }
        @{ Command = 'Import-LedgerTimeEntry'; Parameter = 'Path' }
        @{ Command = 'New-LedgerTimeInvoice'; Parameter = 'CustomerNumber' }
    ) {
        (Get-Command $Command).Parameters[$Parameter].Attributes.Mandatory | Should -Contain $true
    }
}

Describe 'Customer hourly rate' {
    BeforeEach {
        $script:J = New-TestLedger -Root $TestDrive -Customers @(@{ Number = '10'; Name = 'Volvo AB' })
    }

    It 'Has no hourly rate by default' {
        (Get-LedgerCustomer -JournalPath $J -CustomerNumber 10).HourlyRate | Should -BeNullOrEmpty
    }

    It 'Sets the hourly rate with Add-LedgerCustomer' {
        Add-LedgerCustomer -JournalPath $J -CustomerNumber 11 -Name 'Saab AB' -HourlyRate 1250.50
        (Get-LedgerCustomer -JournalPath $J -CustomerNumber 11).HourlyRate | Should -Be 1250.50
    }

    It 'Keeps the hourly rate when other fields change and clears it with 0' {
        Set-LedgerCustomer -JournalPath $J -CustomerNumber 10 -HourlyRate 1000
        Set-LedgerCustomer -JournalPath $J -CustomerNumber 10 -Email 'faktura@volvo.se'
        (Get-LedgerCustomer -JournalPath $J -CustomerNumber 10).HourlyRate | Should -Be 1000
        Set-LedgerCustomer -JournalPath $J -CustomerNumber 10 -HourlyRate 0
        (Get-LedgerCustomer -JournalPath $J -CustomerNumber 10).HourlyRate | Should -BeNullOrEmpty
    }
}

Describe 'Time resources and projects' {
    BeforeEach {
        $script:J = New-TimeTestJournal -Root $TestDrive
    }

    It 'Makes the first resource the default' {
        $r = Get-LedgerTimeResource -JournalPath $J
        ($r | Where-Object IsDefault).ResourceId | Should -Be 'HEG'
    }

    It 'Moves the default with Set-LedgerTimeResource -Default' {
        Set-LedgerTimeResource -JournalPath $J -ResourceId 'KON' -Default
        @(Get-LedgerTimeResource -JournalPath $J | Where-Object IsDefault).ResourceId | Should -Be @('KON')
    }

    It 'Rejects a duplicate resource' {
        { Add-LedgerTimeResource -JournalPath $J -ResourceId 'HEG' -Name 'X' } | Should -Throw
    }

    It 'Rejects a project for an unknown customer' {
        { Add-LedgerProject -JournalPath $J -ProjectNumber 'P9' -Name 'X' -CustomerNumber 99 } | Should -Throw
    }

    It 'Filters projects by customer and status' {
        Set-LedgerProject -JournalPath $J -ProjectNumber 'INT' -Status Closed
        (Get-LedgerProject -JournalPath $J -CustomerNumber 10).ProjectNumber | Should -Be 'P1'
        (Get-LedgerProject -JournalPath $J -Status Closed).ProjectNumber | Should -Be 'INT'
    }

    It 'Refuses to change the customer of a project with time' {
        Add-LedgerTimeEntry -JournalPath $J -Hours 1 -ProjectNumber P1 -Date 2024-03-04
        { Set-LedgerProject -JournalPath $J -ProjectNumber 'P1' -CustomerNumber 20 } | Should -Throw
    }
}

Describe 'Add-LedgerTimeEntry' {
    BeforeEach {
        $script:J = New-TimeTestJournal -Root $TestDrive
    }

    It 'Parses hours given as <Text>' -ForEach @(
        @{ Text = '7:30'; Expected = 7.5 }
        @{ Text = '7,5'; Expected = 7.5 }
        @{ Text = '1.25'; Expected = 1.25 }
        @{ Text = '2h'; Expected = 2 }
        @{ Text = '0:45:00'; Expected = 0.75 }
    ) {
        $e = Add-LedgerTimeEntry -JournalPath $J -Hours $Text -ProjectNumber P1 -Date 2024-03-04 -PassThru
        $e.Hours | Should -Be $Expected
    }

    It 'Rejects <_> hours' -ForEach @('0', '25', 'abc') {
        { Add-LedgerTimeEntry -JournalPath $J -Hours $_ -ProjectNumber P1 -Date 2024-03-04 } | Should -Throw
    }

    It 'Uses the default resource and the project rate' {
        $e = Add-LedgerTimeEntry -JournalPath $J -Hours 2 -ProjectNumber P1 -Date 2024-03-04 -PassThru
        $e.ResourceId | Should -Be 'HEG'
        $e.CustomerNumber | Should -Be '10'
        $e.Rate | Should -Be 1100
        $e.Amount | Should -Be 2200
    }

    It 'Uses the customer rate without a project' {
        (Add-LedgerTimeEntry -JournalPath $J -Hours 1 -CustomerNumber 20 -Date 2024-03-04 -PassThru).Rate | Should -Be 900
    }

    It 'Lets an explicit rate override the project rate' {
        (Add-LedgerTimeEntry -JournalPath $J -Hours 1 -ProjectNumber P1 -Rate 1500 -Date 2024-03-04 -PassThru).Rate | Should -Be 1500
    }

    It 'Throws for billable time without any rate' {
        { Add-LedgerTimeEntry -JournalPath $J -Hours 1 -CustomerNumber 10 -Date 2024-03-04 } | Should -Throw '*hourly rate*'
    }

    It 'Accepts non-billable time without a rate' {
        (Add-LedgerTimeEntry -JournalPath $J -Hours 1 -CustomerNumber 10 -NonBillable -Date 2024-03-04 -PassThru).Billable | Should -BeFalse
    }

    It 'Makes time on an internal project non-billable' {
        (Add-LedgerTimeEntry -JournalPath $J -Hours 1 -ProjectNumber INT -Date 2024-03-04 -PassThru).Billable | Should -BeFalse
    }

    It 'Rejects time on a closed project' {
        Set-LedgerProject -JournalPath $J -ProjectNumber 'P1' -Status Closed
        { Add-LedgerTimeEntry -JournalPath $J -Hours 1 -ProjectNumber P1 -Date 2024-03-04 } | Should -Throw '*closed*'
    }

    It 'Stores entries in one file per month with increasing ids' {
        Add-LedgerTimeEntry -JournalPath $J -Hours 1 -ProjectNumber P1 -Date 2024-03-04
        Add-LedgerTimeEntry -JournalPath $J -Hours 1 -ProjectNumber P1 -Date 2024-04-02
        Join-Path $J 'time' '2024-03.txt' | Should -Exist
        Join-Path $J 'time' '2024-04.txt' | Should -Exist
        (Get-LedgerTimeEntry -JournalPath $J).EntryId | Should -Be @(1, 2)
    }

    It 'Stores the rate on the entry so later rate changes do not affect it' {
        Add-LedgerTimeEntry -JournalPath $J -Hours 1 -ProjectNumber P1 -Date 2024-03-04
        Set-LedgerProject -JournalPath $J -ProjectNumber 'P1' -HourlyRate 2000
        (Get-LedgerTimeEntry -JournalPath $J -EntryId 1).Rate | Should -Be 1100
    }
}

Describe 'Get-, Set- and Remove-LedgerTimeEntry' {
    BeforeEach {
        $script:J = New-TimeTestJournal -Root $TestDrive
        Add-LedgerTimeEntry -JournalPath $J -Hours 2 -ProjectNumber P1 -Date 2024-03-04
        Add-LedgerTimeEntry -JournalPath $J -Hours 3 -ProjectNumber P1 -Date 2024-03-20 -ResourceId KON
        Add-LedgerTimeEntry -JournalPath $J -Hours 1 -CustomerNumber 20 -Date 2024-04-02
    }

    It 'Filters by date, resource and customer' {
        (Get-LedgerTimeEntry -JournalPath $J -FromDate 2024-03-10 -ToDate 2024-03-31).EntryId | Should -Be 2
        (Get-LedgerTimeEntry -JournalPath $J -ResourceId KON).EntryId | Should -Be 2
        (Get-LedgerTimeEntry -JournalPath $J -CustomerNumber 20).EntryId | Should -Be 3
    }

    It 'Moves an entry to another month file when its date changes' {
        Set-LedgerTimeEntry -JournalPath $J -EntryId 3 -Date 2024-05-02
        Join-Path $J 'time' '2024-04.txt' | Should -Not -Exist
        Join-Path $J 'time' '2024-05.txt' | Should -Exist
        (Get-LedgerTimeEntry -JournalPath $J -EntryId 3).Date | Should -Be ([datetime]'2024-05-02')
    }

    It 'Re-resolves the rate when the customer changes' {
        Set-LedgerTimeEntry -JournalPath $J -EntryId 1 -ProjectNumber '' -CustomerNumber 20
        $e = Get-LedgerTimeEntry -JournalPath $J -EntryId 1
        $e.CustomerNumber | Should -Be '20'
        $e.Rate | Should -Be 900
    }

    It 'Removes an entry' {
        Remove-LedgerTimeEntry -JournalPath $J -EntryId 2 -Confirm:$false
        (Get-LedgerTimeEntry -JournalPath $J).EntryId | Should -Be @(1, 3)
    }

    It 'Locks invoiced entries and unlocks them when the invoice is credited' {
        $inv = New-LedgerTimeInvoice -JournalPath $J -CustomerNumber 10 -Date 2024-04-01 -PassThru
        (Get-LedgerTimeEntry -JournalPath $J -EntryId 1).Status | Should -Be 'Invoiced'
        { Set-LedgerTimeEntry -JournalPath $J -EntryId 1 -Hours 5 } | Should -Throw
        { Remove-LedgerTimeEntry -JournalPath $J -EntryId 1 -Confirm:$false } | Should -Throw

        Invoke-LedgerInvoicePosting -JournalPath $J -InvoiceNumber $inv.InvoiceNumber | Out-Null
        Add-LedgerCreditInvoice -JournalPath $J -InvoiceNumber $inv.InvoiceNumber -Date 2024-04-05 | Out-Null

        (Get-LedgerTimeEntry -JournalPath $J -EntryId 1).Status | Should -Be 'Open'
        Set-LedgerTimeEntry -JournalPath $J -EntryId 1 -Hours 5
        (Get-LedgerTimeEntry -JournalPath $J -EntryId 1).Hours | Should -Be 5
    }
}

Describe 'New-LedgerTimeInvoice' {
    BeforeEach {
        $script:J = New-TimeTestJournal -Root $TestDrive
        Add-LedgerTimeEntry -JournalPath $J -Hours 2 -ProjectNumber P1 -Date 2024-03-04 -Text 'Design'
        Add-LedgerTimeEntry -JournalPath $J -Hours 1.5 -ProjectNumber P1 -Date 2024-03-05
        Add-LedgerTimeEntry -JournalPath $J -Hours 3 -ProjectNumber P1 -Date 2024-03-20 -ResourceId KON
        Add-LedgerTimeEntry -JournalPath $J -Hours 1 -ProjectNumber P1 -Date 2024-03-21 -NonBillable
        Add-LedgerTimeEntry -JournalPath $J -Hours 4 -ProjectNumber P1 -Date 2024-04-02
    }

    It 'Groups open billable time per project, resource and rate' {
        $inv = New-LedgerTimeInvoice -JournalPath $J -CustomerNumber 10 -Through 2024-03-31 -Date 2024-04-01 -PassThru
        $inv.Rows.Count | Should -Be 2
        $heg = $inv.Rows | Where-Object Description -like '*Hans-Eric*'
        $heg.Description | Should -Be 'Webbshop – Hans-Eric, mars 2024'
        $heg.Quantity | Should -Be 3.5
        $heg.Unit | Should -Be 'h'
        $heg.UnitPrice | Should -Be 1100
        $heg.Amount | Should -Be 3850
        $heg.Account | Should -Be '3010'
        $inv.NetTotal | Should -Be 7150
    }

    It 'Links the invoiced entries and leaves the rest open' {
        $inv = New-LedgerTimeInvoice -JournalPath $J -CustomerNumber 10 -Through 2024-03-31 -Date 2024-04-01 -PassThru
        (Get-LedgerTimeEntry -JournalPath $J -Status Invoiced).EntryId | Should -Be @(1, 2, 3)
        (Get-LedgerTimeEntry -JournalPath $J -EntryId 1).InvoiceNumber | Should -Be $inv.InvoiceNumber
        (Get-LedgerTimeEntry -JournalPath $J -Status Open).EntryId | Should -Be @(4, 5)
    }

    It 'Uses a date range in the description when time spans several months' {
        $inv = New-LedgerTimeInvoice -JournalPath $J -CustomerNumber 10 -Date 2024-04-10 -PassThru
        ($inv.Rows | Where-Object Description -like '*Hans-Eric*').Description | Should -Be 'Webbshop – Hans-Eric, 2024-03-04 – 2024-04-02'
    }

    It 'Creates one row per entry with -PerEntry' {
        $inv = New-LedgerTimeInvoice -JournalPath $J -CustomerNumber 10 -Through 2024-03-31 -Date 2024-04-01 -PerEntry -PassThru
        $inv.Rows.Count | Should -Be 3
        $inv.Rows[0].Description | Should -Be '2024-03-04 Webbshop, Hans-Eric: Design'
    }

    It 'Does not invoice the same time twice' {
        New-LedgerTimeInvoice -JournalPath $J -CustomerNumber 10 -Through 2024-03-31 -Date 2024-04-01
        New-LedgerTimeInvoice -JournalPath $J -CustomerNumber 10 -Through 2024-03-31 -Date 2024-04-01 -PassThru -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
        @(Get-LedgerInvoice -JournalPath $J).Count | Should -Be 1
    }

    It 'Creates nothing with -WhatIf' {
        New-LedgerTimeInvoice -JournalPath $J -CustomerNumber 10 -Date 2024-04-01 -WhatIf
        Get-LedgerInvoice -JournalPath $J | Should -BeNullOrEmpty
        Get-LedgerTimeEntry -JournalPath $J -Status Invoiced | Should -BeNullOrEmpty
    }
}

Describe 'Get-LedgerTimeReport' {
    BeforeEach {
        $script:J = New-TimeTestJournal -Root $TestDrive
        Add-LedgerTimeEntry -JournalPath $J -Hours 2 -ProjectNumber P1 -Date 2024-03-04
        Add-LedgerTimeEntry -JournalPath $J -Hours 3 -ProjectNumber P1 -Date 2024-03-12 -ResourceId KON
        Add-LedgerTimeEntry -JournalPath $J -Hours 1 -ProjectNumber INT -Date 2024-03-12
        Add-LedgerTimeEntry -JournalPath $J -Hours 2 -CustomerNumber 20 -Date 2024-04-02
    }

    It 'Summarises per customer' {
        $r = Get-LedgerTimeReport -JournalPath $J -GroupBy Customer
        $volvo = $r | Where-Object CustomerNumber -eq '10'
        $volvo.Hours | Should -Be 5
        $volvo.BillableAmount | Should -Be 5500
        $volvo.OpenAmount | Should -Be 5500
    }

    It 'Computes cost and margin from the resource cost rate' {
        $kon = Get-LedgerTimeReport -JournalPath $J -GroupBy Resource | Where-Object ResourceId -eq 'KON'
        $kon.Cost | Should -Be 2100
        $kon.Margin | Should -Be 1200
    }

    It 'Groups by ISO week' {
        $r = Get-LedgerTimeReport -JournalPath $J -GroupBy Week
        $r.Week | Should -Be @('2024-W10', '2024-W11', '2024-W14')
        ($r | Where-Object Week -eq '2024-W11').NonBillableHours | Should -Be 1
    }

    It 'Separates invoiced from open time' {
        New-LedgerTimeInvoice -JournalPath $J -CustomerNumber 10 -Date 2024-04-01
        $volvo = Get-LedgerTimeReport -JournalPath $J -CustomerNumber 10 -GroupBy Customer
        $volvo.InvoicedHours | Should -Be 5
        $volvo.OpenHours | Should -Be 0
    }
}

Describe 'Import-LedgerTimeEntry' {
    BeforeEach {
        $script:J = New-TimeTestJournal -Root $TestDrive
        $script:Csv = Join-Path $TestDrive 'tid.csv'
    }

    It 'Imports a Swedish export and matches project and resource by name' {
        @(
            'Datum;Projekt;Person;Timmar;Beskrivning;Debiterbar'
            '2024-03-07;Webbshop;Konsult Kalle;4;Kodning;ja'
            '2024-03-08;P1;;1:15;Möte;nej'
            '2024-03-08;;;2;Support;'
        ) | Set-Content $Csv -Encoding utf8
        $result = Import-LedgerTimeEntry -JournalPath $J -Path $Csv -ProjectNumber INT
        $result.Imported | Should -Be 3
        $result.Hours | Should -Be 7.25
        $e = Get-LedgerTimeEntry -JournalPath $J
        $e[0].ResourceId | Should -Be 'KON'
        $e[0].ProjectNumber | Should -Be 'P1'
        $e[0].Text | Should -Be 'Kodning'
        $e[1].ResourceId | Should -Be 'HEG'
        $e[1].Billable | Should -BeFalse
        $e[2].ProjectNumber | Should -Be 'INT'
    }

    It 'Imports an English comma-separated export with a customer column' {
        @(
            'Client,Date,Duration,Description'
            'Scania AB,2024-03-07,01:30:00,"Review, part 1"'
        ) | Set-Content $Csv -Encoding utf8
        Import-LedgerTimeEntry -JournalPath $J -Path $Csv | Out-Null
        $e = Get-LedgerTimeEntry -JournalPath $J
        $e.CustomerNumber | Should -Be '20'
        $e.Hours | Should -Be 1.5
        $e.Rate | Should -Be 900
        $e.Text | Should -Be 'Review, part 1'
    }

    It 'Honours explicit column names and date format' {
        @(
            'Dat;Tim;Proj'
            '07/03/2024;3;P1'
        ) | Set-Content $Csv -Encoding utf8
        Import-LedgerTimeEntry -JournalPath $J -Path $Csv -DateColumn Dat -HoursColumn Tim -ProjectColumn Proj -DateFormat 'dd/MM/yyyy' | Out-Null
        (Get-LedgerTimeEntry -JournalPath $J).Date | Should -Be ([datetime]'2024-03-07')
    }

    It 'Imports nothing and reports every bad row' {
        @(
            'Datum;Projekt;Timmar'
            '2024-03-07;P1;2'
            '2024-03-08;Okänt;2'
            'igår;P1;2'
            '2024-03-09;P1;30'
        ) | Set-Content $Csv -Encoding utf8
        $err = { Import-LedgerTimeEntry -JournalPath $J -Path $Csv } | Should -Throw -PassThru
        $err.Exception.Message | Should -BeLike '*Row 3*'
        $err.Exception.Message | Should -BeLike '*Row 4*'
        $err.Exception.Message | Should -BeLike '*Row 5*'
        Get-LedgerTimeEntry -JournalPath $J | Should -BeNullOrEmpty
    }

    It 'Skips rows that are already imported but keeps real duplicates' {
        @(
            'Datum;Projekt;Timmar;Beskrivning'
            '2024-03-07;P1;2;Kodning'
            '2024-03-07;P1;2;Kodning'
        ) | Set-Content $Csv -Encoding utf8
        (Import-LedgerTimeEntry -JournalPath $J -Path $Csv).Imported | Should -Be 2
        Add-Content $Csv '2024-03-08;P1;1;Test'
        $again = Import-LedgerTimeEntry -JournalPath $J -Path $Csv
        $again.Imported | Should -Be 1
        $again.Skipped | Should -Be 2
        @(Get-LedgerTimeEntry -JournalPath $J).Count | Should -Be 3
    }

    It 'Throws when no header row is found' {
        'a;b;c' | Set-Content $Csv -Encoding utf8
        { Import-LedgerTimeEntry -JournalPath $J -Path $Csv } | Should -Throw '*header*'
    }

    It 'Writes nothing with -WhatIf' {
        @('Datum;Projekt;Timmar', '2024-03-07;P1;2') | Set-Content $Csv -Encoding utf8
        Import-LedgerTimeEntry -JournalPath $J -Path $Csv -WhatIf | Out-Null
        Get-LedgerTimeEntry -JournalPath $J | Should -BeNullOrEmpty
    }
}
