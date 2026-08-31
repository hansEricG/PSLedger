BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    function New-ApTestJournal {
        param([string]$Root)
        return New-TestLedger -Root $Root -Suppliers @(
            @{ Number = '100'; Name = 'Alpha AB'; PaymentTermsDays = 30 }
            @{ Number = '200'; Name = 'Beta AB'; PaymentTermsDays = 30 }
        )
    }

    function New-PostedSupplierInvoice {
        param([string]$JournalPath, [string]$Supplier, [string]$Date, [decimal]$Net = 8000)
        return New-TestPostedSupplierInvoice -JournalPath $JournalPath -SupplierNumber $Supplier -Date $Date -Net $Net
    }
}

Describe 'Get-LedgerAccountsPayable' {
    BeforeAll {
        $Command = Get-Command -Name 'Get-LedgerAccountsPayable'
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
            $JournalPath = New-ApTestJournal -Root $TestDrive
        }

        It 'Should return only posted, unpaid supplier invoices' {
            New-PostedSupplierInvoice -JournalPath $JournalPath -Supplier '100' -Date '2024-03-10' | Out-Null
            New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '200' -Date '2024-03-10' -Description 'Draft' -Rows @(@{ Account = '5010'; Amount = 500; VatRate = 0.25; VatAccount = '2640' }) | Out-Null
            $ap = @(Get-LedgerAccountsPayable -JournalPath $JournalPath -AsOf '2024-05-01')
            $ap.Count | Should -Be 1
            $ap[0].InvoiceNumber | Should -Be 1
        }

        It 'Should compute DaysOverdue and the aging bucket' {
            New-PostedSupplierInvoice -JournalPath $JournalPath -Supplier '100' -Date '2024-03-10' | Out-Null
            # DueDate = 2024-04-09; AsOf 2024-05-01 => 22 days overdue.
            $ap = @(Get-LedgerAccountsPayable -JournalPath $JournalPath -AsOf '2024-05-01')
            $ap[0].DaysOverdue | Should -Be 22
            $ap[0].AgingBucket | Should -Be '1-30'
        }

        It 'Should report Current before the due date' {
            New-PostedSupplierInvoice -JournalPath $JournalPath -Supplier '100' -Date '2024-03-10' | Out-Null
            $ap = @(Get-LedgerAccountsPayable -JournalPath $JournalPath -AsOf '2024-04-01')
            $ap[0].AgingBucket | Should -Be 'Current'
        }

        It 'Should place a heavily overdue invoice in the 90+ bucket' {
            New-PostedSupplierInvoice -JournalPath $JournalPath -Supplier '100' -Date '2024-01-01' | Out-Null
            $ap = @(Get-LedgerAccountsPayable -JournalPath $JournalPath -AsOf '2024-06-01')
            $ap[0].AgingBucket | Should -Be '90+'
        }

        It 'Should reflect the remaining amount after a partial payment' {
            $n = New-PostedSupplierInvoice -JournalPath $JournalPath -Supplier '100' -Date '2024-03-10'
            Add-LedgerSupplierPayment -JournalPath $JournalPath -InvoiceNumber $n -Amount 4000 -Date '2024-04-05'
            $ap = @(Get-LedgerAccountsPayable -JournalPath $JournalPath -AsOf '2024-05-01')
            $ap[0].RemainingAmount | Should -Be 6000
            $ap[0].Status | Should -Be 'Partial'
        }

        It 'Should filter by SupplierNumber' {
            New-PostedSupplierInvoice -JournalPath $JournalPath -Supplier '100' -Date '2024-03-10' | Out-Null
            New-PostedSupplierInvoice -JournalPath $JournalPath -Supplier '200' -Date '2024-03-10' | Out-Null
            $ap = @(Get-LedgerAccountsPayable -JournalPath $JournalPath -AsOf '2024-05-01' -SupplierNumber '200')
            $ap.Count | Should -Be 1
            $ap[0].SupplierNumber | Should -Be '200'
        }

        It 'Should aggregate per bucket with -Summary' {
            New-PostedSupplierInvoice -JournalPath $JournalPath -Supplier '100' -Date '2024-03-10' | Out-Null
            New-PostedSupplierInvoice -JournalPath $JournalPath -Supplier '200' -Date '2024-03-11' | Out-Null
            $summary = @(Get-LedgerAccountsPayable -JournalPath $JournalPath -AsOf '2024-05-01' -Summary)
            $summary.Count | Should -Be 5
            $bucket = $summary | Where-Object AgingBucket -eq '1-30'
            $bucket.Count | Should -Be 2
            $bucket.Total | Should -Be 20000
        }

        It 'Should return nothing when there are no open payables' {
            @(Get-LedgerAccountsPayable -JournalPath $JournalPath -AsOf '2024-05-01').Count | Should -Be 0
        }
    }
}
