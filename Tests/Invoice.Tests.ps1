BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    function New-InvoiceTestJournal {
        param([string]$Root)
        return New-TestLedger -Root $Root -Customers @(@{ Number = '10'; Name = 'Volvo AB'; PaymentTermsDays = 30 })
    }
}

Describe 'New-LedgerInvoice' {
    BeforeAll {
        $CommandName = 'New-LedgerInvoice'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have mandatory CustomerNumber, Description and Rows parameters' {
            foreach ($p in 'CustomerNumber', 'Description', 'Rows') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-InvoiceTestJournal -Root $TestDrive
            $rows = @(@{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' })
        }

        It 'Should create inv0001.txt for the first invoice' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows
            Test-Path (Join-Path $JournalPath 'invoices\inv0001.txt') | Should -BeTrue
        }

        It 'Should compute Net, Vat and gross totals' {
            $inv = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows -PassThru
            $inv.NetTotal | Should -Be 10000
            $inv.VatTotal | Should -Be 2500
            $inv.Total | Should -Be 12500
            $inv.Status | Should -Be 'Draft'
        }

        It 'Should calculate DueDate from customer payment terms' {
            $inv = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows -PassThru
            $inv.DueDate.ToString('yyyy-MM-dd') | Should -Be '2024-04-14'
        }

        It 'Should honour an explicit DueDate' {
            $inv = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -DueDate '2024-05-01' -Description 'Konsult' -Rows $rows -PassThru
            $inv.DueDate.ToString('yyyy-MM-dd') | Should -Be '2024-05-01'
        }

        It 'Should auto-increment invoice numbers' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'A' -Rows $rows
            $second = New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-16' -Description 'B' -Rows $rows -PassThru
            $second.InvoiceNumber | Should -Be 2
        }

        It 'Should throw when the customer does not exist' {
            { New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '99' -Description 'X' -Rows $rows } |
                Should -Throw '*does not exist*'
        }

        It 'Should throw when a VAT-liable row has no VatAccount' {
            $bad = @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25 })
            { New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Description 'X' -Rows $bad } |
                Should -Throw '*no VatAccount*'
        }

        It 'Should throw when a row amount is not positive' {
            $bad = @(@{ Account = '3010'; Amount = -1000 })
            { New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Description 'X' -Rows $bad } |
                Should -Throw '*greater than zero*'
        }

        It 'Should compute the amount from Quantity and UnitPrice and keep the row text' {
            $timeRows = @(@{ Account = '3010'; Description = 'Systemutveckling mars'; Quantity = 32.5; Unit = 'h'; UnitPrice = 1100; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-31' -Description 'Konsult' -Rows $timeRows
            $inv = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1
            $inv.NetTotal | Should -Be 35750
            $inv.Rows[0].Description | Should -Be 'Systemutveckling mars'
            $inv.Rows[0].Quantity | Should -Be 32.5
            $inv.Rows[0].Unit | Should -Be 'h'
            $inv.Rows[0].UnitPrice | Should -Be 1100
        }

        It 'Should keep the four-column row layout for rows without text' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows
            $line = Get-Content (Join-Path $JournalPath 'invoices\inv0001.txt') | Where-Object { $_ -like '3010*' }
            ($line -split "`t").Count | Should -Be 4
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).Rows[0].Quantity | Should -BeNullOrEmpty
        }

        It 'Should keep tabs and line breaks in the row text from breaking the file' {
            $odd = @(@{ Account = '3010'; Amount = 100; Description = "Rad ett`tmed tab`r`noch radbrytning" })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $odd
            $inv = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1
            $inv.Rows[0].Description | Should -Be 'Rad ett med tab och radbrytning'
            $inv.NetTotal | Should -Be 100
        }

        It 'Should throw when Amount disagrees with Quantity x UnitPrice' {
            $bad = @(@{ Account = '3010'; Amount = 1000; Quantity = 2; UnitPrice = 400 })
            { New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Description 'X' -Rows $bad } |
                Should -Throw '*does not equal*'
        }

        It 'Should throw when a row has neither Amount nor Quantity and UnitPrice' {
            $bad = @(@{ Account = '3010'; Quantity = 2 })
            { New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Description 'X' -Rows $bad } |
                Should -Throw '*must have an Amount*'
        }
    }
}

Describe 'Get-LedgerInvoice' {
    BeforeAll {
        $CommandName = 'Get-LedgerInvoice'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-InvoiceTestJournal -Root $TestDrive
            $rows = @(@{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Ett' -Rows $rows
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-16' -Description 'Tva' -Rows $rows
        }

        It 'Should return all invoices' {
            @(Get-LedgerInvoice -JournalPath $JournalPath).Count | Should -Be 2
        }

        It 'Should resolve the customer name' {
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).CustomerName | Should -Be 'Volvo AB'
        }

        It 'Should filter by status' {
            @(Get-LedgerInvoice -JournalPath $JournalPath -Status Draft).Count | Should -Be 2
            @(Get-LedgerInvoice -JournalPath $JournalPath -Status Paid).Count | Should -Be 0
        }

        It 'Should exclude drafts from the Unpaid filter' {
            @(Get-LedgerInvoice -JournalPath $JournalPath -Unpaid).Count | Should -Be 0
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            @(Get-LedgerInvoice -JournalPath $JournalPath -Unpaid).Count | Should -Be 1
        }

        It 'Should return nothing when no invoices directory exists' {
            $j2 = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $j2 -Name 'Empty'
            Get-LedgerInvoice -JournalPath $j2 | Should -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-LedgerInvoicePosting' {
    BeforeAll {
        $CommandName = 'Invoke-LedgerInvoicePosting'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory InvoiceNumber parameter' {
            $Command.Parameters['InvoiceNumber'].Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-InvoiceTestJournal -Root $TestDrive
            $rows = @(@{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows
        }

        It 'Should mark the invoice Booked and record the verification' {
            $posted = Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 -PassThru
            $posted.Status | Should -Be 'Booked'
            $posted.BookedVerification | Should -Be 1
            $posted.BookedFiscalYear | Should -Be '2024-01_2024-12'
        }

        It 'Should create a balanced verification with receivable, revenue and VAT' {
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            $bal = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($bal | Where-Object AccountNumber -eq '1510').Balance | Should -Be 12500
            ($bal | Where-Object AccountNumber -eq '3010').Balance | Should -Be -10000
            ($bal | Where-Object AccountNumber -eq '2610').Balance | Should -Be -2500
        }

        It 'Should resolve the fiscal year from the invoice date' {
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12').Count | Should -Be 1
        }

        It 'Should throw when posting an already-posted invoice' {
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            { Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 } |
                Should -Throw '*already posted*'
        }

        It 'Should throw when the invoice does not exist' {
            { Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 99 } |
                Should -Throw '*does not exist*'
        }

        It 'Should create no posting plan for WhatIf or failed preflight' {
            $invoicePath = Join-Path $JournalPath 'invoices' 'inv0001.txt'
            $before = (Get-FileHash -LiteralPath $invoicePath).Hash
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 -WhatIf
            $accountsPath = Join-Path $JournalPath 'accounts.txt'
            $accounts = @(Get-Content -LiteralPath $accountsPath | Where-Object { $_ -notmatch '^1510\t' })
            Set-Content -LiteralPath $accountsPath -Value $accounts -Encoding utf8
            { Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*1510*does not exist*'
            Test-Path -LiteralPath (Join-Path $JournalPath 'invoices' 'posting') | Should -BeFalse
            (Get-FileHash -LiteralPath $invoicePath).Hash | Should -Be $before
        }

        It 'Should stop recovery without writing when <Change> differs from the plan' -ForEach @(
            @{ Change = 'invoice'; ExpectedError = '*has changed since its posting plan*' }
            @{ Change = 'verification'; ExpectedError = '*differs from the invoice posting plan*' }
            @{ Change = 'chain'; ExpectedError = '*integrity issues*' }
            @{ Change = 'operation'; ExpectedError = '*Invalid invoice posting record*' }
            @{ Change = 'incomplete operation'; ExpectedError = '*Invalid invoice posting record*' }
            @{ Change = 'operation identity'; ExpectedError = '*differs from the invoice posting plan*' }
            @{ Change = 'year'; ExpectedError = '*posting plan for*not*' }
        ) {
            Mock -ModuleName PSLedger Save-LedgerInvoiceFile { throw 'simulated invoice save failure' }
            { Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*recover safely*'
            $year = '2024-01_2024-12'
            switch ($Change) {
                'invoice' { Add-Content -LiteralPath (Join-Path $JournalPath 'invoices' 'inv0001.txt') -Value '; changed' }
                'verification' { Add-Content -LiteralPath (Join-Path $JournalPath $year 'ver0001.txt') -Value '; changed' }
                'chain' { Add-Content -LiteralPath (Join-Path $JournalPath $year 'integrity.txt') -Value 'partial append' }
                'operation' { Set-Content -LiteralPath (Join-Path $JournalPath 'invoices' 'posting' 'inv0001.txt') -Value "FormatVersion:`t999" }
                'incomplete operation' { Set-Content -LiteralPath (Join-Path $JournalPath 'invoices' 'posting' 'inv0001.txt') -Value "FormatVersion:`t1" }
                'operation identity' {
                    $path = Join-Path $JournalPath 'invoices' 'posting' 'inv0001.txt'
                    $changed = (Get-Content -LiteralPath $path -Raw) -replace '(?m)^OperationId:\t[^\r\n]+', "OperationId:`t$([guid]::NewGuid())"
                    Set-Content -LiteralPath $path -Value $changed -NoNewline
                }
            }
            $before = @(Get-ChildItem -LiteralPath $JournalPath -Recurse -File -Force | Sort-Object FullName |
                    ForEach-Object { "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)" })
            $parameters = @{ JournalPath = $JournalPath; InvoiceNumber = 1 }
            if ($Change -eq 'year') { $parameters.FiscalYear = '2025-01_2025-12' }
            { Invoke-LedgerInvoicePosting @parameters } | Should -Throw $ExpectedError
            $after = @(Get-ChildItem -LiteralPath $JournalPath -Recurse -File -Force | Sort-Object FullName |
                    ForEach-Object { "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)" })
            $after | Should -Be $before
        }

        It 'Should resolve each piped invoice year independently' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-01-01' -EndDate '2025-12-31'
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2025-03-15' -Description 'Nytt ar' -Rows $rows
            $posted = @(Get-LedgerInvoice -JournalPath $JournalPath | Invoke-LedgerInvoicePosting -JournalPath $JournalPath -PassThru)
            $posted.BookedFiscalYear | Should -Be @('2024-01_2024-12', '2025-01_2025-12')
        }
    }
}

Describe 'Add-LedgerInvoicePayment' {
    BeforeAll {
        $CommandName = 'Add-LedgerInvoicePayment'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory InvoiceNumber parameter' {
            $Command.Parameters['InvoiceNumber'].Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-InvoiceTestJournal -Root $TestDrive
            $rows = @(@{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' })
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-15' -Description 'Konsult' -Rows $rows
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
        }

        It 'Should mark the invoice Paid on full payment' {
            $paid = Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10' -PassThru
            $paid.Status | Should -Be 'Paid'
            $paid.PaidAmount | Should -Be 12500
            $paid.RemainingAmount | Should -Be 0
        }

        It 'Should replay a completed PaymentId without duplicating payments, even after later payments' {
            $id = New-Guid
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $id -Amount 5000 -Date '2024-04-10'
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10'
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-20'
            $paid = Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $id -PassThru
            $paid.Status | Should -Be 'Paid'
            $paid.Payments | Should -HaveCount 3
            $paid.PaidAmount | Should -Be 12500
            @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12') | Should -HaveCount 4
        }

        It 'Should reject reuse of a PaymentId with changed <Field>' -ForEach @(
            @{ Field = 'Amount'; Value = 4999 }
            @{ Field = 'Date'; Value = '2024-04-11' }
            @{ Field = 'Account'; Value = '1910' }
            @{ Field = 'FiscalYear'; Value = '2025-01_2025-12' }
            @{ Field = 'InvoiceNumber'; Value = 2 }
        ) {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-20' -Description 'Annan faktura' -Rows $rows
            $id = New-Guid
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $id -Amount 5000 -Date '2024-04-10'
            $retry = @{ JournalPath = $JournalPath; InvoiceNumber = 1; PaymentId = $id }
            $retry[$Field] = $Value
            { Add-LedgerInvoicePayment @retry } | Should -Throw '*different payment inputs*'
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).Payments | Should -HaveCount 1
        }

        It 'Should block conflicting work until an unkeyed interrupted payment is resumed' {
            $script:RealInvoiceSave = & (Get-Module PSLedger) { (Get-Command Save-LedgerInvoiceFile).ScriptBlock }
            Mock Save-LedgerInvoiceFile -ModuleName PSLedger { throw 'Injected payment save failure' }
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' } |
                Should -Throw '*PaymentId*'
            $plan = Get-ChildItem -LiteralPath (Join-Path $JournalPath 'invoices' 'payments') -File
            $id = [guid]$plan.BaseName
            $before = @(Get-ChildItem -LiteralPath $JournalPath -File -Recurse | Get-FileHash).Hash

            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' } | Should -Throw '*unfinished payment*'
            { Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*unfinished payment*'
            { Add-LedgerInvoiceFee -JournalPath $JournalPath -InvoiceNumber 1 -Amount 60 } | Should -Throw '*unfinished payment*'
            { Add-LedgerInvoiceInterest -JournalPath $JournalPath -InvoiceNumber 1 -Amount 60 } | Should -Throw '*unfinished payment*'
            { Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 } | Should -Throw '*unfinished payment*'
            { Invoke-LedgerBankMatching -JournalPath $JournalPath } | Should -Throw '*unfinished payment*'
            { Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 1 -InvoiceNumber 1 } | Should -Throw '*unfinished payment*'
            @(Get-ChildItem -LiteralPath $JournalPath -File -Recurse | Get-FileHash).Hash | Should -Be $before

            Mock Save-LedgerInvoiceFile -ModuleName PSLedger { & $script:RealInvoiceSave -Invoice $Invoice }
            $partial = Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $id -PassThru
            $partial.RemainingAmount | Should -Be 7500
            $partial.Payments | Should -HaveCount 1
        }

        It 'Should leave no payment plan on WhatIf or failed amount preflight' {
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10' -WhatIf
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 1.001 -Date '2024-04-10' } | Should -Throw '*more than two decimals*'
            Test-Path -LiteralPath (Join-Path $JournalPath 'invoices' 'payments') | Should -BeFalse
            @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12') | Should -HaveCount 1
        }

        It 'Should reject recovery after changing <Change> without further writes' -ForEach @(
            @{ Change = 'invoice'; Expected = '*has changed since payment*' }
            @{ Change = 'verification'; Expected = '*differs from the invoice posting plan*' }
            @{ Change = 'integrity'; Expected = '*integrity issues*' }
            @{ Change = 'plan amount'; Expected = '*inputs do not match*' }
            @{ Change = 'malformed plan'; Expected = '*Invalid invoice posting record*' }
        ) {
            $id = New-Guid
            Mock Save-LedgerInvoiceFile -ModuleName PSLedger { throw 'Injected payment save failure' }
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $id -Amount 5000 -Date '2024-04-10' } | Should -Throw '*PaymentId*'
            $plan = Join-Path $JournalPath 'invoices' 'payments' "$id.txt"
            switch ($Change) {
                'invoice' { Add-Content -LiteralPath (Join-Path $JournalPath 'invoices' 'inv0001.txt') -Value '; changed' }
                'verification' { Add-Content -LiteralPath (Join-Path $JournalPath '2024-01_2024-12' 'ver0002.txt') -Value '; changed' }
                'integrity' { Add-Content -LiteralPath (Join-Path $JournalPath '2024-01_2024-12' 'integrity.txt') -Value 'partial append' }
                'plan amount' {
                    $text = (Get-Content -LiteralPath $plan -Raw) -replace "PaymentAmount:`t5000", "PaymentAmount:`t4999"
                    Set-Content -LiteralPath $plan -Value $text -NoNewline
                }
                'malformed plan' { Set-Content -LiteralPath $plan -Value "FormatVersion:`t1" }
            }
            $before = @(Get-ChildItem -LiteralPath $JournalPath -Recurse -File | Get-FileHash).Hash
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $id } | Should -Throw $Expected
            @(Get-ChildItem -LiteralPath $JournalPath -Recurse -File | Get-FileHash).Hash | Should -Be $before
        }

        It 'Should allocate distinct default payment identities for piped invoices' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-01-01' -EndDate '2025-12-31'
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2025-03-15' -Description 'Nytt uppdrag' `
                -Rows @(@{ Account = '3010'; Amount = 2000 })
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 2
            @(
                [pscustomobject]@{ InvoiceNumber = 1 }
                [pscustomobject]@{ InvoiceNumber = 2 }
            ) | Add-LedgerInvoicePayment -JournalPath $JournalPath -Date '2025-04-10'
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).PaidAmount | Should -Be 12500
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 2).PaidAmount | Should -Be 2000
            @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear '2025-01_2025-12') | Should -HaveCount 3
        }

        It 'Should default the payment amount to the remaining amount' {
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10'
            (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).Status | Should -Be 'Paid'
        }

        It 'Should clear the receivable and debit the bank account' {
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10'
            $bal = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($bal | Where-Object AccountNumber -eq '1510').Balance | Should -Be 0
            ($bal | Where-Object AccountNumber -eq '1930').Balance | Should -Be 12500
        }

        It 'Should support partial payments' {
            $partial = Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 5000 -Date '2024-04-10' -PassThru
            $partial.Status | Should -Be 'Partial'
            $partial.RemainingAmount | Should -Be 7500
            $full = Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-20' -PassThru
            $full.Status | Should -Be 'Paid'
            @($full.Payments).Count | Should -Be 2
        }

        It 'Should throw when the payment exceeds the remaining amount' {
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 99999 -Date '2024-04-10' } |
                Should -Throw '*exceeds the remaining*'
        }

        It 'Should throw when paying a draft (unposted) invoice' {
            New-LedgerInvoice -JournalPath $JournalPath -CustomerNumber '10' -Date '2024-03-20' -Description 'Draft' -Rows $rows
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 2 -Date '2024-04-10' } |
                Should -Throw '*has not been posted*'
        }

        It 'Should throw when paying an already fully paid invoice' {
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-04-10'
            { Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -Amount 100 -Date '2024-04-11' } |
                Should -Throw '*already fully paid*'
        }
    }
}
