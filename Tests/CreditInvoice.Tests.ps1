BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    function New-CreditTestJournal {
        param([string]$Root)
        return New-TestLedger -Root $Root -Customers @(@{ Number = '10'; Name = 'Volvo AB'; PaymentTermsDays = 30 })
    }

    function New-BookedInvoice {
        param([string]$JournalPath)
        return New-TestPostedInvoice -JournalPath $JournalPath
    }
}

Describe 'Add-LedgerCreditInvoice' {
    BeforeAll {
        $CommandName = 'Add-LedgerCreditInvoice'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory InvoiceNumber parameter typed as int' {
            $Command.Parameters['InvoiceNumber'].Attributes.Mandatory | Should -Contain $true
            $Command.Parameters['InvoiceNumber'].ParameterType | Should -Be ([int])
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-CreditTestJournal -Root $TestDrive
        }

        It 'Should create a credit note with a new number and negated total' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            $credit = Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30' -PassThru
            $credit.InvoiceNumber | Should -Be 2
            $credit.Total | Should -Be (-12500)
            $credit.Status | Should -Be 'Credited'
        }

        It 'Should mark both the original and the credit note as Credited' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30'
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).Status | Should -Be 'Credited'
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 2).Status | Should -Be 'Credited'
        }

        It 'Should copy row text and negate the quantity on the credit note' {
            $rows = @(@{ Account = '3010'; Description = 'Systemutveckling mars'; Quantity = 10; Unit = 'h'; UnitPrice = 1000; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-31' -Description 'Konsult' -Rows $rows | Out-Null
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            $credit = Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30' -PassThru
            $credit.Rows[0].Description | Should -Be 'Systemutveckling mars'
            $credit.Rows[0].Quantity | Should -Be (-10)
            $credit.Rows[0].UnitPrice | Should -Be 1000
            $credit.Rows[0].Amount | Should -Be (-10000)
        }

        It 'Should post a balanced reversing verification' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30'
            $balances = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            foreach ($acct in '1510', '3010', '2610') {
                ($balances | Where-Object AccountNumber -eq $acct).Balance | Should -Be 0
            }
        }

        It 'Should remove the invoice from accounts receivable' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30'
            $ar = @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-05-01')
            $ar.Count | Should -Be 0
        }

        It 'Should throw when the invoice does not exist' {
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 99 } | Should -Throw '*does not exist*'
        }

        It 'Should throw for a Draft invoice (not posted)' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Draft' -Rows @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25; VatAccount = '2610' }) | Out-Null
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*not posted*'
        }

        It 'Should throw for an invoice with payments' {
            $n = New-BookedInvoice -JournalPath $JournalPath
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber $n -Amount 5000 -Date '2024-04-10'
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber $n } | Should -Throw '*payments*'
        }

        It 'Should treat a repeated credit of the same invoice as completed and throw for an already credited note' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30'
            $again = Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -PassThru
            $again.InvoiceNumber | Should -Be 2
            @(Get-LedgerInvoice -JournalPath $JournalPath).Count | Should -Be 2
            @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12').Count | Should -Be 2
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-05-01' } | Should -Throw '*saved credit plan*'
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 2 } | Should -Throw '*already been credited*'
        }

        It 'Should reverse booked fees and interest together with the invoice' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber 1 -Amount 60 -Date '2024-05-01'
            Add-LedgerInvoiceInterest -JournalPath $JournalPath -InvoiceNumber 1 -Amount 25.50 -Date '2024-05-02'
            $credit = Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-05-10' -PassThru
            $credit.Total | Should -Be (-12585.50)
            $credit.Charges | Should -HaveCount 2
            $credit.Charges[0].Amount | Should -Be (-60)
            $credit.Charges[0].VerificationNumber | Should -Be 4
            $balances = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            foreach ($acct in '1510', '3010', '2610', '3590', '8310') {
                ($balances | Where-Object AccountNumber -eq $acct).Balance | Should -Be 0 -Because $acct
            }
            @(Get-LedgerAccountsReceivable -JournalPath $JournalPath -AsOf '2024-05-11').Count | Should -Be 0
            (Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -PassThru).InvoiceNumber | Should -Be 2
        }

        It 'Should write nothing with -WhatIf' {
            New-BookedInvoice -JournalPath $JournalPath | Out-Null
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30' -WhatIf
            Test-Path (Join-Path $JournalPath 'invoices' 'credits') | Should -BeFalse
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).Status | Should -Be 'Booked'
            @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12').Count | Should -Be 1
        }

        Context 'Recovery' {
            BeforeEach {
                New-BookedInvoice -JournalPath $JournalPath | Out-Null
                $script:failCredit = $true
                $script:realWrite = & (Get-Module PSLedger) { (Get-Command Write-LedgerVerification).ScriptBlock }
                Mock -ModuleName PSLedger Write-LedgerVerification { & $script:realWrite -JournalPath $JournalPath -FiscalYear $FiscalYear -Date $Date -Description $Description -Rows $Rows -Attachment $Attachment -PassThru:$PassThru -LegacyReversal:$LegacyReversal -OperationId $(if ($OperationId) { $OperationId } else { [guid]::Empty }) -ReservedNumber ([int]$ReservedNumber) -Confirm:$false }
                Mock -ModuleName PSLedger Write-LedgerVerification { throw 'simulated interruption' } -ParameterFilter { $script:failCredit }
                { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-30' } | Should -Throw '*rerun Add-LedgerCreditInvoice*'
                $script:failCredit = $false
                $planPath = Join-Path $JournalPath 'invoices' 'credits' 'inv0001.txt'
            }

            It 'Should reserve the credit note and verification numbers in an immutable plan' {
                $plan = Get-Content -LiteralPath $planPath
                $plan | Should -Contain "CreditInvoiceNumber:`t2"
                $plan | Should -Contain "VerificationNumber:`t2"
                $plan | Should -Contain "CreditDate:`t2024-04-30"
                Test-Path (Join-Path $JournalPath 'invoices' 'inv0002.txt') | Should -BeFalse

                New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-05-01' -Description 'Ny' -Rows @(@{ Account = '3010'; Amount = 100 }) -PassThru |
                    Select-Object -ExpandProperty InvoiceNumber | Should -Be 3
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -Date '2024-05-01' -Description 'Annat' -Rows @(
                    @{ Account = '1510'; Amount = 1 }, @{ Account = '3010'; Amount = -1 }) -PassThru |
                    Select-Object -ExpandProperty VerificationNumber | Should -Be 3
            }

            It 'Should complete the saved credit and keep the planned date' {
                $credit = Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -PassThru
                $credit.InvoiceNumber | Should -Be 2
                $credit.InvoiceDate | Should -Be ([datetime]'2024-04-30')
                $credit.BookedVerification | Should -Be 2
                (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).Status | Should -Be 'Credited'
                (Test-LedgerIntegrity -JournalPath $JournalPath -FiscalYear '2024-01_2024-12').Status | Should -Be 'Valid'
            }

            It 'Should stop when the original invoice changed after planning' {
                $file = Join-Path $JournalPath 'invoices' 'inv0001.txt'
                (Get-Content -LiteralPath $file -Raw) -replace 'DueDate:\t\S+', "DueDate:`t2024-12-31" | Set-Content -LiteralPath $file -NoNewline
                { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*changed since its credit was planned*'
                Test-Path (Join-Path $JournalPath '2024-01_2024-12' 'ver0002.txt') | Should -BeFalse
            }

            It 'Should block other invoice changes until the credit is resumed' {
                { Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber 1 -Amount 60 -Date '2024-05-01' } |
                    Should -Throw '*unfinished credit*'
            }
        }
    }
}
