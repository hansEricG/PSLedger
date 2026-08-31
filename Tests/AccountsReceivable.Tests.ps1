BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force

    function New-ArTestJournal {
        param([string]$Root)
        $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $path -Name 'Faktura AB' -CompanyType AB | Out-Null
        Import-LedgerChart -JournalPath $path -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $path -StartDate '2024-01-01' -EndDate '2024-12-31'
        Add-LedgerCustomer -JournalPath $path -CustomerNumber '10' -Name 'Volvo AB' -PaymentTermsDays 30
        Add-LedgerCustomer -JournalPath $path -CustomerNumber '20' -Name 'Saab AB' -PaymentTermsDays 30
        return $path
    }

    function New-PostedInvoice {
        param([string]$JournalPath, [string]$Customer, [string]$Date, [decimal]$Net = 10000)
        $rows = @(@{ Account = '3010'; Amount = $Net; VatRate = 0.25; VatAccount = '2610' })
        $inv = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber $Customer -Date $Date -Description 'Tjänst' -Rows $rows -PassThru
        Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber $inv.InvoiceNumber
        return $inv.InvoiceNumber
    }
}

Describe 'Get-LedgerAccountsReceivable' {
    BeforeAll {
        $CommandName = 'Get-LedgerAccountsReceivable'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should type AsOf as datetime' {
            $Command.Parameters['AsOf'].ParameterType | Should -Be ([datetime])
        }

        It 'Should have a Summary switch' {
            $Command.Parameters['Summary'].ParameterType | Should -Be ([switch])
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-ArTestJournal -Root $TestDrive
        }

        It 'Should return only posted, unpaid invoices' {
            New-PostedInvoice -JournalPath $JournalPath -Customer '10' -Date '2024-03-15' | Out-Null
            # A draft invoice should be excluded.
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '20' -Date '2024-03-15' -Description 'Draft' -Rows @(@{ Account = '3010'; Amount = 5000; VatRate = 0.25; VatAccount = '2610' }) | Out-Null
            $ar = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-05-01')
            $ar.Count | Should -Be 1
            $ar[0].InvoiceNumber | Should -Be 1
        }

        It 'Should compute DaysOverdue relative to AsOf' {
            New-PostedInvoice -JournalPath $JournalPath -Customer '10' -Date '2024-03-15' | Out-Null
            # DueDate = 2024-04-14; AsOf 2024-05-01 => 17 days overdue.
            $ar = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-05-01')
            $ar[0].DaysOverdue | Should -Be 17
            $ar[0].AgingBucket | Should -Be '1-30'
        }

        It 'Should report 0 days overdue and Current bucket before the due date' {
            New-PostedInvoice -JournalPath $JournalPath -Customer '10' -Date '2024-03-15' | Out-Null
            $ar = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-04-01')
            $ar[0].DaysOverdue | Should -Be 0
            $ar[0].AgingBucket | Should -Be 'Current'
        }

        It 'Should place a heavily overdue invoice in the 90+ bucket' {
            New-PostedInvoice -JournalPath $JournalPath -Customer '10' -Date '2024-01-01' | Out-Null
            # DueDate 2024-01-31; AsOf 2024-06-01 => 122 days.
            $ar = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-06-01')
            $ar[0].AgingBucket | Should -Be '90+'
        }

        It 'Should reflect the remaining amount after a partial payment' {
            $n = New-PostedInvoice -JournalPath $JournalPath -Customer '10' -Date '2024-03-15'
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber $n -Amount 5000 -Date '2024-04-10'
            $ar = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-05-01')
            $ar[0].RemainingAmount | Should -Be 7500
            $ar[0].Status | Should -Be 'Partial'
        }

        It 'Should filter by CustomerNumber' {
            New-PostedInvoice -JournalPath $JournalPath -Customer '10' -Date '2024-03-15' | Out-Null
            New-PostedInvoice -JournalPath $JournalPath -Customer '20' -Date '2024-03-15' | Out-Null
            $ar = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-05-01' -CustomerNumber '20')
            $ar.Count | Should -Be 1
            $ar[0].CustomerNumber | Should -Be '20'
        }

        It 'Should aggregate per bucket with -Summary' {
            New-PostedInvoice -JournalPath $JournalPath -Customer '10' -Date '2024-03-15' | Out-Null
            New-PostedInvoice -JournalPath $JournalPath -Customer '20' -Date '2024-03-16' | Out-Null
            $summary = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-05-01' -Summary)
            $summary.Count | Should -Be 5
            $bucket = $summary | Where-Object AgingBucket -eq '1-30'
            $bucket.Count | Should -Be 2
            $bucket.Total | Should -Be 25000
        }

        It 'Should return nothing when there are no open invoices' {
            $ar = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-05-01')
            $ar.Count | Should -Be 0
        }
    }
}
