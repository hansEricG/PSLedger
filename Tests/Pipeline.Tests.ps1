BeforeAll {
    Import-Module "$PSScriptRoot\..\PSLedger\PSLedger.psd1" -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')
}

Describe 'Pipeline input' {
    Context 'Function metadata' {
        It '<Command> accepts -<Parameter> by property name' -ForEach @(
            @{ Command = 'Export-LedgerInvoice'; Parameter = 'InvoiceNumber' }
            @{ Command = 'Invoke-LedgerInvoicePosting'; Parameter = 'InvoiceNumber' }
            @{ Command = 'Add-LedgerInvoicePayment'; Parameter = 'InvoiceNumber' }
            @{ Command = 'Add-LedgerInvoiceFee'; Parameter = 'InvoiceNumber' }
            @{ Command = 'Add-LedgerInvoiceInterest'; Parameter = 'InvoiceNumber' }
            @{ Command = 'Add-LedgerInvoiceReminder'; Parameter = 'InvoiceNumber' }
            @{ Command = 'Add-LedgerCreditInvoice'; Parameter = 'InvoiceNumber' }
            @{ Command = 'Invoke-LedgerSupplierInvoicePosting'; Parameter = 'InvoiceNumber' }
            @{ Command = 'Add-LedgerSupplierPayment'; Parameter = 'InvoiceNumber' }
            @{ Command = 'Export-LedgerPayslip'; Parameter = 'PayslipNumber' }
            @{ Command = 'Invoke-LedgerPayrollPosting'; Parameter = 'PayslipNumber' }
            @{ Command = 'Set-LedgerCustomer'; Parameter = 'CustomerNumber' }
            @{ Command = 'Set-LedgerSupplier'; Parameter = 'SupplierNumber' }
            @{ Command = 'Set-LedgerEmployee'; Parameter = 'EmployeeNumber' }
        ) {
            $param = (Get-Command $Command).Parameters[$Parameter]
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).ValueFromPipelineByPropertyName |
                Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-TestLedger -Root $TestDrive -Customers @(
                @{ Number = '10'; Name = 'Volvo AB' }
                @{ Number = '20'; Name = 'Scania AB' }
            ) -Suppliers @(
                @{ Number = '100'; Name = 'Telia AB' }
            )
        }

        It 'Should post all draft invoices piped from Get-LedgerInvoice' {
            New-TestPostedInvoice -JournalPath $JournalPath -CustomerNumber '10' -NoPost | Out-Null
            New-TestPostedInvoice -JournalPath $JournalPath -CustomerNumber '20' -NoPost | Out-Null

            Get-LedgerInvoice -JournalPath $JournalPath -Status Draft |
                Invoke-LedgerInvoicePosting -JournalPath $JournalPath

            @(Get-LedgerInvoice -JournalPath $JournalPath -Status Draft).Count | Should -Be 0
            @(Get-LedgerInvoice -JournalPath $JournalPath).Count | Should -Be 2
        }

        It 'Should post all draft supplier invoices piped from Get-LedgerSupplierInvoice' {
            New-TestPostedSupplierInvoice -JournalPath $JournalPath -NoPost | Out-Null
            New-TestPostedSupplierInvoice -JournalPath $JournalPath -NoPost | Out-Null

            Get-LedgerSupplierInvoice -JournalPath $JournalPath -Status Draft |
                Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath

            @(Get-LedgerSupplierInvoice -JournalPath $JournalPath -Status Draft).Count | Should -Be 0
        }

        It 'Should update every customer piped from Get-LedgerCustomer' {
            Get-LedgerCustomer -JournalPath $JournalPath |
                Set-LedgerCustomer -JournalPath $JournalPath -PaymentTermsDays 20

            Get-LedgerCustomer -JournalPath $JournalPath | ForEach-Object {
                $_.PaymentTermsDays | Should -Be 20
            }
        }

        It 'Should update every supplier piped from Get-LedgerSupplier' {
            Get-LedgerSupplier -JournalPath $JournalPath |
                Set-LedgerSupplier -JournalPath $JournalPath -PaymentTermsDays 15

            (Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100').PaymentTermsDays | Should -Be 15
        }
    }
}
