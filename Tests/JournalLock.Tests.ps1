BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $modulePath -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    $workerPath = Join-Path $TestDrive 'lock-worker.ps1'
    Set-Content -LiteralPath $workerPath -Encoding utf8 -Value {
        param ($ModulePath, $JournalPath, $Mode, $Ready, $Gate)
        $ErrorActionPreference = 'Stop'
        $env:PSLEDGER_EXTENSIONS = ''
        $env:PSLEDGER_USER_EXTENSIONS = Join-Path (Split-Path $Ready -Parent) 'extensions'
        Import-Module $ModulePath -Force
        $paymentId = '11111111-1111-1111-1111-111111111111'
        $chargeId = '22222222-2222-2222-2222-222222222222'
        if ($Mode -match '^(Invoice|Payment|Bank|SupplierInvoice|SupplierPayment|SupplierBank|Account|Charge|Credit|Payroll)After') {
            & (Get-Module PSLedger) {
                param ($Ready, $Mode)
                $script:PostingReady = $Ready
                $script:PostingPause = {
                    Set-Content -LiteralPath $script:PostingReady -Value 'checkpoint'
                    Start-Sleep -Seconds 60
                    throw 'The invoice posting test did not terminate its worker.'
                }
                switch -Regex ($Mode) {
                    'AfterPlan$' {
                        function script:Write-LedgerVerification { & $script:PostingPause }
                    }
                    'AfterSave$' {
                        function script:Register-LedgerIntegrityItem { & $script:PostingPause }
                    }
                    'AfterSeal$' {
                        if ($Mode -like 'Account*') {
                            function script:Set-LedgerBankTransactionState { & $script:PostingPause }
                        }
                        elseif ($Mode -like 'Supplier*') {
                            function script:Save-LedgerSupplierInvoiceFile { & $script:PostingPause }
                        }
                        elseif ($Mode -like 'Payroll*') {
                            function script:Save-LedgerPayslipFile { & $script:PostingPause }
                        }
                        else { function script:Save-LedgerInvoiceFile { & $script:PostingPause } }
                    }
                    'AfterStatus$' {
                        if ($Mode -like 'Payroll*') {
                            $script:OriginalPayslipSave = (Get-Command Save-LedgerPayslipFile).ScriptBlock
                            function script:Save-LedgerPayslipFile {
                                param ($Payslip)
                                & $script:OriginalPayslipSave -Payslip $Payslip
                                & $script:PostingPause
                            }
                        }
                        elseif ($Mode -like 'Supplier*') {
                            $script:OriginalInvoiceSave = (Get-Command Save-LedgerSupplierInvoiceFile).ScriptBlock
                            function script:Save-LedgerSupplierInvoiceFile {
                                param ($Invoice)
                                & $script:OriginalInvoiceSave -Invoice $Invoice
                                & $script:PostingPause
                            }
                        }
                        else {
                            $script:OriginalInvoiceSave = (Get-Command Save-LedgerInvoiceFile).ScriptBlock
                            function script:Save-LedgerInvoiceFile {
                                param ($Invoice)
                                & $script:OriginalInvoiceSave -Invoice $Invoice
                                & $script:PostingPause
                            }
                        }
                    }
                    'AfterLink$' {
                        $script:OriginalBankSave = (Get-Command Save-LedgerBankStatementFile).ScriptBlock
                        function script:Save-LedgerBankStatementFile {
                            param ($Statement)
                            & $script:OriginalBankSave -Statement $Statement
                            & $script:PostingPause
                        }
                    }
                    'AfterCounterpart$' {
                        $script:OriginalBankSave = (Get-Command Save-LedgerBankStatementFile).ScriptBlock
                        function script:Save-LedgerBankStatementFile {
                            param ($Statement)
                            & $script:OriginalBankSave -Statement $Statement
                            if ($Statement.BankAccount -eq '1940') { & $script:PostingPause }
                        }
                    }
                }
            } $Ready $Mode
            if ($Mode -like 'Account*') {
                Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 1 -Account '1940'
            }
            elseif ($Mode -like 'SupplierInvoice*') {
                Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
            }
            elseif ($Mode -like 'SupplierBank*') {
                Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 1 -SupplierInvoiceNumber 1
            }
            elseif ($Mode -like 'SupplierPayment*') {
                Add-LedgerSupplierPayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $paymentId -Amount 500.000 -Date '2024-01-20'
            }
            elseif ($Mode -like 'Bank*') {
                Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 1 -InvoiceNumber 1
            }
            elseif ($Mode -like 'Payment*') {
                Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $paymentId -Amount 500.000 -Date '2024-01-20'
            }
            elseif ($Mode -like 'Charge*') {
                Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Fee 60 -BookFee -ChargeId $chargeId -Date '2024-01-20'
            }
            elseif ($Mode -like 'Credit*') {
                Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-01-20'
            }
            elseif ($Mode -like 'Payroll*') {
                Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber 1
            }
            else { Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1 }
            exit 0
        }
        if ($Mode -eq 'TryLock') {
            & (Get-Module PSLedger) {
                param ($JournalPath)
                $lock = $null
                try { $lock = Enter-LedgerJournalLock -JournalPath $JournalPath -TimeoutSeconds 1 }
                finally { Exit-LedgerJournalLock -Lock $lock }
            } $JournalPath
            exit 0
        }
        if ($Mode -eq 'PauseAfterSave') {
            & (Get-Module PSLedger) {
                param ($Ready)
                $script:LockTestReady = $Ready
                function script:Register-LedgerIntegrityItem {
                    Set-Content -LiteralPath $script:LockTestReady -Value 'saved'
                    Start-Sleep -Seconds 60
                    throw 'The test did not terminate the paused writer.'
                }
            } $Ready
        }
        else {
            Set-Content -LiteralPath $Ready -Value 'ready'
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while (-not (Test-Path -LiteralPath $Gate)) {
                if ($timer.Elapsed.TotalSeconds -gt 30) { throw 'Worker start gate timed out.' }
                Start-Sleep -Milliseconds 20
            }
        }
        if ($Mode -eq 'Invoice') {
            Invoke-LedgerInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
        }
        elseif ($Mode -eq 'SupplierInvoice') {
            Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
        }
        elseif ($Mode -eq 'BankImport') {
            Import-LedgerBankStatement -JournalPath $JournalPath -Path (Join-Path (Split-Path $JournalPath -Parent) 'bank.csv') `
                -Format Csv -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text -ReferenceColumn Reference | Out-Null
        }
        elseif ($Mode -eq 'BankManual') {
            Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 1 -InvoiceNumber 1
        }
        elseif ($Mode -eq 'Account') {
            Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 1 -Account '1940'
        }
        elseif ($Mode -eq 'SupplierBankManual') {
            Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 1 -SupplierInvoiceNumber 1
        }
        elseif ($Mode -eq 'Bank') {
            Invoke-LedgerBankMatching -JournalPath $JournalPath | Out-Null
        }
        elseif ($Mode -like 'Payment*' -or $Mode -like 'SupplierPayment*') {
            if ($Mode -match '(New|Large)$') { $paymentId = [guid]::NewGuid() }
            $amount = if ($Mode -like '*Large') { 900 } else { 500.000 }
            $command = if ($Mode -like 'Supplier*') { 'Add-LedgerSupplierPayment' } else { 'Add-LedgerInvoicePayment' }
            & $command -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $paymentId -Amount $amount -Date '2024-01-20'
        }
        elseif ($Mode -eq 'Charge') {
            Add-LedgerInvoiceReminder -JournalPath $JournalPath -InvoiceNumber 1 -Fee 60 -BookFee -ChargeId $chargeId -Date '2024-01-20'
        }
        elseif ($Mode -eq 'Credit') {
            Add-LedgerCreditInvoice -JournalPath $JournalPath -InvoiceNumber 1 -Date '2024-01-20'
        }
        elseif ($Mode -eq 'Payroll') {
            Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber 1
        }
        elseif ($Mode -eq 'Seal') {
            Protect-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' | Out-Null
        }
        else {
            $count = if ($Mode -eq 'Post') { 10 } else { 1 }
            for ($i = 0; $i -lt $count; $i++) {
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear '2024-01_2024-12' -Date '2024-01-15' `
                    -Description "$PID-$i" -Rows @(
                        @{ Account = '1930'; Amount = 100 }
                        @{ Account = '3010'; Amount = -100 }
                    )
            }
        }
    }

    function Start-LockTestWorker {
        param ([string]$Mode)
        $ready = Join-Path $TestDrive "$([guid]::NewGuid()).ready"
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $info.UseShellExecute = $false
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        foreach ($arg in @('-NoProfile', '-NonInteractive', '-File', $workerPath,
                $modulePath, $journal, $Mode, $ready, $gate)) {
            $info.ArgumentList.Add($arg)
        }
        $process = [Diagnostics.Process]::Start($info)
        $worker = [pscustomobject]@{
            Process = $process
            Output = $process.StandardOutput.ReadToEndAsync()
            Error = $process.StandardError.ReadToEndAsync()
            Ready = $ready
        }
        $workers.Add($worker)
        $worker
    }

    function Wait-LockTestReady {
        param ($Worker)
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $Worker.Ready)) {
            if ($Worker.Process.HasExited) { throw "Worker exited: $($Worker.Error.Result)" }
            if ($timer.Elapsed.TotalSeconds -gt 30) { throw 'Worker readiness timed out.' }
            Start-Sleep -Milliseconds 20
        }
    }

    function Complete-LockTestWorker {
        param ($Worker)
        $Worker.Process.WaitForExit(60000) | Should -BeTrue
        $Worker.Process.ExitCode | Should -Be 0 -Because $Worker.Error.Result
    }

    function New-LockTestInvoice {
        foreach ($number in '1510', '2610') {
            Add-LedgerAccount -JournalPath $journal -AccountNumber $number -AccountName "Konto $number"
        }
        Add-LedgerCustomer -JournalPath $journal -CustomerNumber '10' -Name 'Volvo AB'
        New-LedgerInvoice -JournalPath $journal -CustomerNumber '10' -Date '2024-01-15' -Description 'Konsultuppdrag' `
            -Rows @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25; VatAccount = '2610' })
    }

    function New-LockTestSupplierInvoice {
        param ([switch]$Draft)
        foreach ($number in '2440', '5010', '2640') {
            Add-LedgerAccount -JournalPath $journal -AccountNumber $number -AccountName "Konto $number"
        }

        Add-LedgerSupplier -JournalPath $journal -SupplierNumber '100' -Name 'Kontorsbolaget AB'
        New-LedgerSupplierInvoice -JournalPath $journal -SupplierNumber '100' -Date '2024-01-15' -Description 'Hyra' `
            -Reference 'SUP-1' -Rows @(@{ Account = '5010'; Amount = 1000; VatRate = 0.25; VatAccount = '2640' })
        if (-not $Draft) { Invoke-LedgerSupplierInvoicePosting -JournalPath $journal -InvoiceNumber 1 }
    }

    function New-LockTestPayslip {
        foreach ($number in '7210', '2710', '7510', '2730') {
            Add-LedgerAccount -JournalPath $journal -AccountNumber $number -AccountName "Konto $number"
        }
        Add-LedgerEmployee -JournalPath $journal -EmployeeNumber '1' -Name 'Anna Andersson' -SalaryAccount '7210' -TaxRate 0.30
        New-LedgerPayslip -JournalPath $journal -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-01-25' | Out-Null
    }

    function New-LockTestTransfer {
        Add-LedgerAccount -JournalPath $journal -AccountNumber '1940' -AccountName 'Sparkonto'
        Import-LedgerBankStatement -JournalPath $journal -Path (New-LockTestBankSource -Supplier) -Format Csv `
            -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text -ReferenceColumn Reference | Out-Null
        $source = Join-Path (Split-Path $journal -Parent) 'counterpart.csv'
        Set-Content -LiteralPath $source -Value @('Date;Amount;Text', '2024-01-21;500;Transfer')
        Import-LedgerBankStatement -JournalPath $journal -Path $source -Account '1940' -Format Csv `
            -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text | Out-Null
    }

    function New-LockTestBankSource {
        param ([switch]$Supplier)
        $source = Join-Path (Split-Path $journal -Parent) 'bank.csv'
        $row = if ($Supplier) { '2024-01-20;-500;Kontorsbolaget AB;SUP-1' } else { '2024-01-20;500;Volvo AB;133' }
        Set-Content -LiteralPath $source -Value @('Date;Amount;Text;Reference', $row)
        $source
    }
}

Describe 'Journal write locking' {
    BeforeEach {
        $journal = New-TestLedger -Root $TestDrive -NoChart
        foreach ($number in '1930', '3010') {
            Add-LedgerAccount -JournalPath $journal -AccountNumber $number -AccountName "Konto $number"
        }
        $year = '2024-01_2024-12'
        $gate = Join-Path $TestDrive "$([guid]::NewGuid()).gate"
        $workers = [Collections.Generic.List[object]]::new()
        $entry = @{
            JournalPath = $journal; FiscalYear = $year; Date = '2024-01-15'; Description = 'Test'
            Rows = @(@{ Account = '1930'; Amount = 100 }; @{ Account = '3010'; Amount = -100 })
        }
    }

    AfterEach {
        foreach ($worker in $workers) {
            if (-not $worker.Process.HasExited) {
                $worker.Process.Kill($true)
                $worker.Process.WaitForExit()
            }
            $worker.Process.Dispose()
        }
    }

    It 'Serializes separate posting and sealing processes without lost entries or chain records' {
        $first = Start-LockTestWorker Post
        $second = Start-LockTestWorker Post
        $sealer = Start-LockTestWorker Seal
        foreach ($worker in @($first, $second, $sealer)) { Wait-LockTestReady $worker }
        Set-Content -LiteralPath $gate -Value 'go'
        foreach ($worker in @($first, $second, $sealer)) { Complete-LockTestWorker $worker }

        $entries = @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year)
        $entries.VerificationNumber | Should -Be @(1..20)
        @($entries.Description | Sort-Object -Unique) | Should -HaveCount 20
        $integrity = Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year
        $integrity.IsValid | Should -BeTrue
        $integrity.Verifications | Should -Be 20
    }

    It 'Keeps the outer lock through nested posting, attachments and closing, and reports contention' {
        $attachment = Join-Path $TestDrive 'kvitto.txt'
        Set-Content -LiteralPath $attachment -Value 'Kvitto'
        $lock = & (Get-Module PSLedger) { param ($Path) Enter-LedgerJournalLock -JournalPath $Path } $journal
        try {
            Add-LedgerEntry @entry -Attachment $attachment
            Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
            $blocked = Start-LockTestWorker TryLock
            $blocked.Process.WaitForExit(30000) | Should -BeTrue
            $blocked.Process.ExitCode | Should -Not -Be 0
            $blocked.Error.Result | Should -BeLike '*is busy*within 1 seconds*'
        }
        finally {
            & (Get-Module PSLedger) { param ($Lock) Exit-LedgerJournalLock -Lock $Lock } $lock
        }
        $unblocked = Start-LockTestWorker TryLock
        Complete-LockTestWorker $unblocked
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
    }

    It 'Checks the closed-year guard after a waiting writer acquires the lock' {
        $lock = & (Get-Module PSLedger) { param ($Path) Enter-LedgerJournalLock -JournalPath $Path } $journal
        try {
            $waiting = Start-LockTestWorker PostOne
            Wait-LockTestReady $waiting
            Set-Content -LiteralPath $gate -Value 'go'
            Start-Sleep -Milliseconds 500
            $waiting.Process.HasExited | Should -BeFalse
            Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
        }
        finally {
            & (Get-Module PSLedger) { param ($Lock) Exit-LedgerJournalLock -Lock $Lock } $lock
        }
        $waiting.Process.WaitForExit(30000) | Should -BeTrue
        $waiting.Process.ExitCode | Should -Not -Be 0
        $waiting.Error.Result | Should -BeLike '*closed*'
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 0
    }

    It 'Releases a killed writer lock without reusing its saved number or hiding the unsealed entry' {
        Add-LedgerEntry @entry
        $paused = Start-LockTestWorker PauseAfterSave
        Wait-LockTestReady $paused
        $waiting = Start-LockTestWorker PostOne
        Wait-LockTestReady $waiting
        Set-Content -LiteralPath $gate -Value 'go'
        Start-Sleep -Milliseconds 500
        $waiting.Process.HasExited | Should -BeFalse
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 2

        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        Complete-LockTestWorker $waiting
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year).VerificationNumber | Should -Be @(1, 2, 3)
        $integrity = Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year
        $integrity.IsValid | Should -BeFalse
        @($integrity.Issues | ForEach-Object { "$($_.Kind) $($_.Key) $($_.Problem)" }) |
            Should -Be @('Verification 2 Unsealed')
        Test-Path -LiteralPath (Join-Path $journal '.write.lock') | Should -BeTrue
    }

    It 'Preserves an existing verification if allocation encounters a conflicting filename' {
        Add-LedgerEntry @entry
        $path = Join-Path $journal $year 'ver0001.txt'
        $before = (Get-FileHash -LiteralPath $path).Hash
        Mock -ModuleName PSLedger Get-ChildItem { @() } -ParameterFilter { $Filter -eq 'ver*.txt' }
        { Add-LedgerEntry @entry } | Should -Throw
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
        @(Get-ChildItem -LiteralPath (Join-Path $journal $year) -Force -Filter '.tmp_*') | Should -HaveCount 0
    }

    It 'Reports a saved but unsealed verification explicitly and releases the lock on error' {
        Mock -ModuleName PSLedger Register-LedgerIntegrityItem { throw 'simulated sealing failure' }
        { Add-LedgerEntry @entry } | Should -Throw '*was saved*Do not post it again*simulated sealing failure*'
        Test-Path -LiteralPath (Join-Path $journal $year 'ver0001.txt') | Should -BeTrue
        $worker = Start-LockTestWorker TryLock
        Complete-LockTestWorker $worker
    }

    It 'Does not create a coordination file or verification for WhatIf' {
        Add-LedgerEntry @entry -WhatIf
        Test-Path -LiteralPath (Join-Path $journal '.write.lock') | Should -BeFalse
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 0
    }

    It 'Recovers invoice posting after process termination at <Checkpoint>' -ForEach @(
        @{ Checkpoint = 'InvoiceAfterPlan' }
        @{ Checkpoint = 'InvoiceAfterSave' }
        @{ Checkpoint = 'InvoiceAfterSeal' }
        @{ Checkpoint = 'InvoiceAfterStatus' }
    ) {
        New-LockTestInvoice
        Add-LedgerEntry @entry
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        $operationPath = Join-Path $journal 'invoices' 'posting' 'inv0001.txt'
        $planHash = (Get-FileHash -LiteralPath $operationPath).Hash
        $savedPath = Join-Path $journal $year 'ver0002.txt'
        $savedHash = if (Test-Path -LiteralPath $savedPath) { (Get-FileHash -LiteralPath $savedPath).Hash }

        # Another posting must not consume a reservation even when no verification was saved yet.
        (Add-LedgerEntry @entry -PassThru).VerificationNumber | Should -Be 3
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Invoice
        if ($Checkpoint -eq 'InvoiceAfterStatus') {
            $retry.Process.WaitForExit(30000) | Should -BeTrue
            $retry.Process.ExitCode | Should -Not -Be 0
            $retry.Error.Result | Should -BeLike '*already posted*'
        }
        else { Complete-LockTestWorker $retry }

        $invoice = Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1
        $invoice.Status | Should -Be 'Booked'
        $invoice.BookedVerification | Should -Be 2
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year).VerificationNumber | Should -Be @(1, 2, 3)
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
        (Get-FileHash -LiteralPath $operationPath).Hash | Should -Be $planHash
        if ($savedHash) { (Get-FileHash -LiteralPath $savedPath).Hash | Should -Be $savedHash }
    }

    It 'Recovers supplier invoice posting after process termination at <Checkpoint>' -ForEach @(
        @{ Checkpoint = 'SupplierInvoiceAfterPlan' }
        @{ Checkpoint = 'SupplierInvoiceAfterSave' }
        @{ Checkpoint = 'SupplierInvoiceAfterSeal' }
        @{ Checkpoint = 'SupplierInvoiceAfterStatus' }
    ) {
        New-LockTestSupplierInvoice -Draft
        Add-LedgerEntry @entry
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        $operationPath = Join-Path $journal 'supplierinvoices' 'posting' 'sup0001.txt'
        $planHash = (Get-FileHash -LiteralPath $operationPath).Hash

        (Add-LedgerEntry @entry -PassThru).VerificationNumber | Should -Be 3
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker SupplierInvoice
        if ($Checkpoint -eq 'SupplierInvoiceAfterStatus') {
            $retry.Process.WaitForExit(30000) | Should -BeTrue
            $retry.Process.ExitCode | Should -Not -Be 0
            $retry.Error.Result | Should -BeLike '*already posted*'
        }
        else { Complete-LockTestWorker $retry }

        $invoice = Get-LedgerSupplierInvoice -JournalPath $journal -InvoiceNumber 1
        $invoice.Status | Should -Be 'Booked'
        $invoice.BookedVerification | Should -Be 2
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year).VerificationNumber | Should -Be @(1, 2, 3)
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
        (Get-FileHash -LiteralPath $operationPath).Hash | Should -Be $planHash
    }

    It 'Handles supplier invoice recovery in a closed year with saved verification=<Saved>' -ForEach @(
        @{ Saved = $true; Checkpoint = 'SupplierInvoiceAfterSave' }
        @{ Saved = $false; Checkpoint = 'SupplierInvoiceAfterPlan' }
    ) {
        New-LockTestSupplierInvoice -Draft
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker SupplierInvoice
        if ($Saved) {
            Complete-LockTestWorker $retry
            (Get-LedgerSupplierInvoice -JournalPath $journal -InvoiceNumber 1).Status | Should -Be 'Booked'
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 1
        }
        else {
            $retry.Process.WaitForExit(30000) | Should -BeTrue
            $retry.Process.ExitCode | Should -Not -Be 0
            $retry.Error.Result | Should -BeLike '*closed*'
            (Get-LedgerSupplierInvoice -JournalPath $journal -InvoiceNumber 1).Status | Should -Be 'Draft'
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 0
        }
    }

    It 'Handles recovery in a closed year with saved verification=<Saved>' -ForEach @(
        @{ Saved = $true; Checkpoint = 'InvoiceAfterSave' }
        @{ Saved = $false; Checkpoint = 'InvoiceAfterPlan' }
    ) {
        New-LockTestInvoice
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
        $yearHash = (Get-FileHash -LiteralPath (Join-Path $journal $year 'year.txt')).Hash
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Invoice
        if ($Saved) {
            Complete-LockTestWorker $retry
            (Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1).Status | Should -Be 'Booked'
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 1
        }
        else {
            $retry.Process.WaitForExit(30000) | Should -BeTrue
            $retry.Process.ExitCode | Should -Not -Be 0
            $retry.Error.Result | Should -BeLike '*closed*'
            (Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1).Status | Should -Be 'Draft'
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 0
        }
        (Get-FileHash -LiteralPath (Join-Path $journal $year 'year.txt')).Hash | Should -Be $yearHash
    }

    It 'Posts the same invoice only once when two processes race' {
        New-LockTestInvoice
        $first = Start-LockTestWorker Invoice
        $second = Start-LockTestWorker Invoice
        Wait-LockTestReady $first
        Wait-LockTestReady $second
        Set-Content -LiteralPath $gate -Value 'go'
        foreach ($worker in @($first, $second)) { $worker.Process.WaitForExit(30000) | Should -BeTrue }
        @($first.Process.ExitCode, $second.Process.ExitCode | Sort-Object) | Should -Be @(0, 1)
        ($first.Error.Result + $second.Error.Result) | Should -BeLike '*already posted*'
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 1
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
    }

    It 'Recovers a payment after process termination at <Checkpoint>' -ForEach @(
        @{ Checkpoint = 'PaymentAfterPlan' }
        @{ Checkpoint = 'PaymentAfterSave' }
        @{ Checkpoint = 'PaymentAfterSeal' }
        @{ Checkpoint = 'PaymentAfterStatus' }
    ) {
        New-LockTestInvoice
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        $operationPath = Join-Path $journal 'invoices' 'payments' '11111111-1111-1111-1111-111111111111.txt'
        $hash = (Get-FileHash -LiteralPath $operationPath).Hash
        $savedPath = Join-Path $journal $year 'ver0002.txt'
        $savedHash = if (Test-Path -LiteralPath $savedPath) { (Get-FileHash -LiteralPath $savedPath).Hash }
        (Add-LedgerEntry @entry -PassThru).VerificationNumber | Should -Be 3
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Payment
        Complete-LockTestWorker $retry

        $invoice = Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1
        $invoice.Payments | Should -HaveCount 1
        $invoice.Payments[0].VerificationNumber | Should -Be 2
        $invoice.RemainingAmount | Should -Be 750
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
        (Get-FileHash -LiteralPath $operationPath).Hash | Should -Be $hash
        if ($savedHash) { (Get-FileHash -LiteralPath $savedPath).Hash | Should -Be $savedHash }
    }

    It 'Recovers a reminder fee after process termination at <Checkpoint>' -ForEach @(
        @{ Checkpoint = 'ChargeAfterPlan' }
        @{ Checkpoint = 'ChargeAfterSave' }
        @{ Checkpoint = 'ChargeAfterSeal' }
        @{ Checkpoint = 'ChargeAfterStatus' }
    ) {
        New-LockTestInvoice
        Add-LedgerAccount -JournalPath $journal -AccountNumber '3590' -AccountName 'Övriga sidointäkter'
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        $operationPath = Join-Path $journal 'invoices' 'charges' '22222222-2222-2222-2222-222222222222.txt'
        $hash = (Get-FileHash -LiteralPath $operationPath).Hash
        $savedPath = Join-Path $journal $year 'ver0002.txt'
        $savedHash = if (Test-Path -LiteralPath $savedPath) { (Get-FileHash -LiteralPath $savedPath).Hash }
        if ($Checkpoint -ne 'ChargeAfterStatus') {
            { Add-LedgerInvoicePayment -JournalPath $journal -InvoiceNumber 1 -Amount 100 -Date '2024-01-21' } |
                Should -Throw '*unfinished charge*Add-LedgerInvoiceReminder*-ChargeId*'
        }
        (Add-LedgerEntry @entry -PassThru).VerificationNumber | Should -Be 3
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Charge
        Complete-LockTestWorker $retry

        $invoice = Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1
        $invoice.Charges | Should -HaveCount 1
        $invoice.Charges[0].VerificationNumber | Should -Be 2
        $invoice.ReminderCount | Should -Be 1
        $invoice.RemainingAmount | Should -Be 1310
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
        (Get-FileHash -LiteralPath $operationPath).Hash | Should -Be $hash
        if ($savedHash) { (Get-FileHash -LiteralPath $savedPath).Hash | Should -Be $savedHash }
    }

    It 'Recovers a credit after process termination at <Checkpoint>' -ForEach @(
        @{ Checkpoint = 'CreditAfterPlan' }
        @{ Checkpoint = 'CreditAfterSave' }
        @{ Checkpoint = 'CreditAfterSeal' }
        @{ Checkpoint = 'CreditAfterStatus' }
    ) {
        New-LockTestInvoice
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        $operationPath = Join-Path $journal 'invoices' 'credits' 'inv0001.txt'
        $hash = (Get-FileHash -LiteralPath $operationPath).Hash
        $savedPath = Join-Path $journal $year 'ver0002.txt'
        $savedHash = if (Test-Path -LiteralPath $savedPath) { (Get-FileHash -LiteralPath $savedPath).Hash }
        (Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1).Status | Should -Be 'Booked'
        (Add-LedgerEntry @entry -PassThru).VerificationNumber | Should -Be 3
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Credit
        Complete-LockTestWorker $retry

        (Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1).Status | Should -Be 'Credited'
        $credit = Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 2
        $credit.Status | Should -Be 'Credited'
        $credit.BookedVerification | Should -Be 2
        $credit.Total | Should -Be (-1250)
        @(Get-LedgerInvoice -JournalPath $journal) | Should -HaveCount 2
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 3
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
        (Get-FileHash -LiteralPath $operationPath).Hash | Should -Be $hash
        if ($savedHash) { (Get-FileHash -LiteralPath $savedPath).Hash | Should -Be $savedHash }
    }

    It 'Handles <Kind> recovery in a closed year with saved verification=<Saved>' -ForEach @(
        @{ Kind = 'Charge'; Saved = $true }
        @{ Kind = 'Charge'; Saved = $false }
        @{ Kind = 'Credit'; Saved = $true }
        @{ Kind = 'Credit'; Saved = $false }
    ) {
        New-LockTestInvoice
        Add-LedgerAccount -JournalPath $journal -AccountNumber '3590' -AccountName 'Övriga sidointäkter'
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        $paused = Start-LockTestWorker "$Kind$(if ($Saved) { 'AfterSave' } else { 'AfterPlan' })"
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker $Kind
        $invoice = $null
        if ($Saved) {
            Complete-LockTestWorker $retry
            $invoice = Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1
            if ($Kind -eq 'Charge') { $invoice.Charges | Should -HaveCount 1 } else { $invoice.Status | Should -Be 'Credited' }
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 2
        }
        else {
            $retry.Process.WaitForExit(30000) | Should -BeTrue
            $retry.Process.ExitCode | Should -Not -Be 0
            $retry.Error.Result | Should -BeLike '*closed*'
            $invoice = Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1
            $invoice.Charges | Should -HaveCount 0
            $invoice.Status | Should -Be 'Booked'
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 1
        }
    }

    It 'Recovers payroll posting after process termination at <Checkpoint>' -ForEach @(
        @{ Checkpoint = 'PayrollAfterPlan' }
        @{ Checkpoint = 'PayrollAfterSave' }
        @{ Checkpoint = 'PayrollAfterSeal' }
        @{ Checkpoint = 'PayrollAfterStatus' }
    ) {
        New-LockTestPayslip
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        $operationPath = Join-Path $journal 'payslips' 'posting' 'pay0001.txt'
        $hash = (Get-FileHash -LiteralPath $operationPath).Hash
        $savedPath = Join-Path $journal $year 'ver0001.txt'
        $savedHash = if (Test-Path -LiteralPath $savedPath) { (Get-FileHash -LiteralPath $savedPath).Hash }
        (Add-LedgerEntry @entry -PassThru).VerificationNumber | Should -Be 2
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Payroll
        if ($Checkpoint -eq 'PayrollAfterStatus') {
            $retry.Process.WaitForExit(60000) | Should -BeTrue
            $retry.Error.Result | Should -BeLike '*already posted*'
        }
        else { Complete-LockTestWorker $retry }

        $payslip = Get-LedgerPayslip -JournalPath $journal -PayslipNumber 1
        $payslip.Status | Should -Be 'Booked'
        $payslip.BookedVerification | Should -Be 1
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 2
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
        (Get-FileHash -LiteralPath $operationPath).Hash | Should -Be $hash
        if ($savedHash) { (Get-FileHash -LiteralPath $savedPath).Hash | Should -Be $savedHash }
    }

    It 'Handles payroll recovery in a closed year with saved verification=<Saved>' -ForEach @(
        @{ Saved = $true; Checkpoint = 'PayrollAfterSave' }
        @{ Saved = $false; Checkpoint = 'PayrollAfterPlan' }
    ) {
        New-LockTestPayslip
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Payroll
        if ($Saved) {
            Complete-LockTestWorker $retry
            (Get-LedgerPayslip -JournalPath $journal -PayslipNumber 1).Status | Should -Be 'Booked'
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 1
        }
        else {
            $retry.Process.WaitForExit(30000) | Should -BeTrue
            $retry.Process.ExitCode | Should -Not -Be 0
            $retry.Error.Result | Should -BeLike '*closed*'
            (Get-LedgerPayslip -JournalPath $journal -PayslipNumber 1).Status | Should -Be 'Draft'
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 0
        }
    }

    It 'Handles payment recovery in a closed year with saved verification=<Saved>' -ForEach @(
        @{ Saved = $true; Checkpoint = 'PaymentAfterSave' }
        @{ Saved = $false; Checkpoint = 'PaymentAfterPlan' }
    ) {
        New-LockTestInvoice
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Payment
        if ($Saved) {
            Complete-LockTestWorker $retry
            (Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1).Payments | Should -HaveCount 1
        }
        else {
            $retry.Process.WaitForExit(30000) | Should -BeTrue
            $retry.Process.ExitCode | Should -Not -Be 0
            $retry.Error.Result | Should -BeLike '*closed*'
            (Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1).Payments | Should -HaveCount 0
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 1
        }
    }

    It 'Serializes payment processes with second mode <SecondMode>' -ForEach @(
        @{ SecondMode = 'Payment'; ExpectedPayments = 1 }
        @{ SecondMode = 'PaymentNew'; ExpectedPayments = 2 }
    ) {
        New-LockTestInvoice
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        $first = Start-LockTestWorker Payment
        $second = Start-LockTestWorker $SecondMode
        Wait-LockTestReady $first
        Wait-LockTestReady $second
        Set-Content -LiteralPath $gate -Value 'go'
        Complete-LockTestWorker $first
        Complete-LockTestWorker $second
        $invoice = Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1
        $invoice.Payments | Should -HaveCount $ExpectedPayments
        $invoice.PaidAmount | Should -Be (500 * $ExpectedPayments)
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount (1 + $ExpectedPayments)
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
    }

    It 'Rechecks the remaining receivable after acquiring the payment lock' {
        New-LockTestInvoice
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        $first = Start-LockTestWorker PaymentLarge
        $second = Start-LockTestWorker PaymentLarge
        Wait-LockTestReady $first
        Wait-LockTestReady $second
        Set-Content -LiteralPath $gate -Value 'go'
        foreach ($worker in @($first, $second)) { $worker.Process.WaitForExit(30000) | Should -BeTrue }
        @($first.Process.ExitCode, $second.Process.ExitCode | Sort-Object) | Should -Be @(0, 1)
        ($first.Error.Result + $second.Error.Result) | Should -BeLike '*exceeds the remaining amount*'
        $invoice = Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1
        $invoice.Payments | Should -HaveCount 1
        $invoice.RemainingAmount | Should -Be 350
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 2
    }

    It 'Resumes the bank payment and its link after <Checkpoint>' -ForEach @(
        @{ Checkpoint = 'BankAfterPlan' }
        @{ Checkpoint = 'BankAfterSave' }
        @{ Checkpoint = 'BankAfterSeal' }
        @{ Checkpoint = 'BankAfterStatus' }
        @{ Checkpoint = 'BankAfterLink' }
    ) {
        New-LockTestInvoice
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        Import-LedgerBankStatement -JournalPath $journal -Path (New-LockTestBankSource) -Format Csv `
            -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text -ReferenceColumn Reference | Out-Null
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        $plan = Get-ChildItem -LiteralPath (Join-Path $journal 'invoices' 'payments') -File
        $hash = (Get-FileHash -LiteralPath $plan.FullName).Hash
        $extra = $Checkpoint -in 'BankAfterStatus', 'BankAfterLink'
        if ($extra) {
            Add-LedgerInvoicePayment -JournalPath $journal -InvoiceNumber 1 -Amount 250 -Date '2024-01-21'
        }
        (Add-LedgerEntry @entry -PassThru).VerificationNumber | Should -Be $(if ($extra) { 4 } else { 3 })
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Bank
        Complete-LockTestWorker $retry
        $t = Get-LedgerBankTransaction -JournalPath $journal -TransactionId 1
        $t.Status | Should -Be 'Matched'
        $t.MatchType | Should -Be 'CustomerInvoice'
        $t.MatchRef | Should -Be '1'
        $t.VerificationNumber | Should -Be 2
        $invoice = Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1
        $invoice.Payments | Should -HaveCount $(if ($extra) { 2 } else { 1 })
        $invoice.PaidAmount | Should -Be $(if ($extra) { 750 } else { 500 })
        (Get-FileHash -LiteralPath $plan.FullName).Hash | Should -Be $hash
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
    }

    It 'Serializes manual and automatic matching of one customer payment' {
        New-LockTestInvoice
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        Import-LedgerBankStatement -JournalPath $journal -Path (New-LockTestBankSource) -Format Csv `
            -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text -ReferenceColumn Reference | Out-Null
        $first = Start-LockTestWorker Bank
        $second = Start-LockTestWorker BankManual
        Wait-LockTestReady $first
        Wait-LockTestReady $second
        Set-Content -LiteralPath $gate -Value 'go'
        Complete-LockTestWorker $first
        Complete-LockTestWorker $second
        (Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1).Payments | Should -HaveCount 1
        (Get-LedgerBankTransaction -JournalPath $journal -TransactionId 1).VerificationNumber | Should -Be 2
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
    }

    It 'Recovers a bank match in a closed year only if its verification was saved: <Saved>' -ForEach @(
        @{ Saved = $true; Checkpoint = 'BankAfterSave' }
        @{ Saved = $false; Checkpoint = 'BankAfterPlan' }
    ) {
        New-LockTestInvoice
        Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
        Import-LedgerBankStatement -JournalPath $journal -Path (New-LockTestBankSource) -Format Csv `
            -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text -ReferenceColumn Reference | Out-Null
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker Bank
        if ($Saved) {
            Complete-LockTestWorker $retry
            (Get-LedgerBankTransaction -JournalPath $journal -TransactionId 1).Status | Should -Be 'Matched'
            (Get-LedgerInvoice -JournalPath $journal -InvoiceNumber 1).Payments | Should -HaveCount 1
        }
        else {
            $retry.Process.WaitForExit(30000) | Should -BeTrue
            $retry.Process.ExitCode | Should -Not -Be 0
            $retry.Error.Result | Should -BeLike '*closed*'
            (Get-LedgerBankTransaction -JournalPath $journal -TransactionId 1).Status | Should -Be 'Unmatched'
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 1
        }
    }

    It 'Resumes a supplier payment after process termination at <Checkpoint>' -ForEach @(
        foreach ($kind in 'SupplierPayment', 'SupplierBank') {
            foreach ($stage in 'Plan', 'Save', 'Seal', 'Status', 'Link') {
                if ($stage -eq 'Link' -and $kind -eq 'SupplierPayment') { continue }
                @{ Checkpoint = "${kind}After$stage"; Bank = $kind -eq 'SupplierBank' }
            }
        }
    ) {
        New-LockTestSupplierInvoice
        if ($Bank) {
            Import-LedgerBankStatement -JournalPath $journal -Path (New-LockTestBankSource -Supplier) -Format Csv `
                -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text -ReferenceColumn Reference | Out-Null
        }
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        $plan = Get-ChildItem -LiteralPath (Join-Path $journal 'supplierinvoices' 'payments') -File
        $hash = (Get-FileHash -LiteralPath $plan.FullName).Hash
        $savedPath = Join-Path $journal $year 'ver0002.txt'
        $savedHash = if (Test-Path -LiteralPath $savedPath) { (Get-FileHash -LiteralPath $savedPath).Hash }
        (Add-LedgerEntry @entry -PassThru).VerificationNumber | Should -Be 3
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker $(if ($Bank) { 'Bank' } else { 'SupplierPayment' })
        Complete-LockTestWorker $retry

        $invoice = Get-LedgerSupplierInvoice -JournalPath $journal -InvoiceNumber 1
        $invoice.Payments | Should -HaveCount 1
        $invoice.Payments[0].VerificationNumber | Should -Be 2
        $invoice.RemainingAmount | Should -Be 750
        if ($Bank) {
            $t = Get-LedgerBankTransaction -JournalPath $journal -TransactionId 1
            $t.MatchType | Should -Be 'SupplierInvoice'
            $t.MatchRef | Should -Be '1'
            $t.VerificationNumber | Should -Be 2
            $t.Status | Should -Be 'Matched'
        }
        (Get-FileHash -LiteralPath $plan.FullName).Hash | Should -Be $hash
        if ($savedHash) { (Get-FileHash -LiteralPath $savedPath).Hash | Should -Be $savedHash }
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
    }

    It 'Recovers supplier <Kind> in a closed year only if its verification was saved: <Saved>' -ForEach @(
        foreach ($kind in 'Payment', 'Bank') {
            @{ Kind = $kind; Saved = $true; Checkpoint = "Supplier${kind}AfterSave" }
            @{ Kind = $kind; Saved = $false; Checkpoint = "Supplier${kind}AfterPlan" }
        }
    ) {
        New-LockTestSupplierInvoice
        if ($Kind -eq 'Bank') {
            Import-LedgerBankStatement -JournalPath $journal -Path (New-LockTestBankSource -Supplier) -Format Csv `
                -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text -ReferenceColumn Reference | Out-Null
        }
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
        Set-Content -LiteralPath $gate -Value 'go'
        $retry = Start-LockTestWorker $(if ($Kind -eq 'Bank') { 'Bank' } else { 'SupplierPayment' })
        if ($Saved) { Complete-LockTestWorker $retry }
        else {
            $retry.Process.WaitForExit(30000) | Should -BeTrue
            $retry.Process.ExitCode | Should -Not -Be 0
            $retry.Error.Result | Should -BeLike '*closed*'
        }
        $expectedCount = if ($Saved) { 1 } else { 0 }
        (Get-LedgerSupplierInvoice -JournalPath $journal -InvoiceNumber 1).Payments | Should -HaveCount $expectedCount
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount (1 + $expectedCount)
        if ($Kind -eq 'Bank') {
            (Get-LedgerBankTransaction -JournalPath $journal -TransactionId 1).Status |
                Should -Be $(if ($Saved) { 'Matched' } else { 'Unmatched' })
        }
    }

    It 'Serializes supplier payment processes with second mode <SecondMode>' -ForEach @(
        @{ FirstMode = 'SupplierPayment'; SecondMode = 'SupplierPayment'; Count = 1; Amount = 500 }
        @{ FirstMode = 'SupplierPayment'; SecondMode = 'SupplierPaymentNew'; Count = 2; Amount = 1000 }
        @{ FirstMode = 'SupplierPaymentLarge'; SecondMode = 'SupplierPaymentLarge'; Count = 1; Amount = 900 }
        @{ FirstMode = 'Bank'; SecondMode = 'SupplierBankManual'; Count = 1; Amount = 500 }
    ) {
        New-LockTestSupplierInvoice
        if ($FirstMode -eq 'Bank') {
            Import-LedgerBankStatement -JournalPath $journal -Path (New-LockTestBankSource -Supplier) -Format Csv `
                -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text -ReferenceColumn Reference | Out-Null
        }
        $first = Start-LockTestWorker $FirstMode
        $second = Start-LockTestWorker $SecondMode
        Wait-LockTestReady $first
        Wait-LockTestReady $second
        Set-Content -LiteralPath $gate -Value 'go'
        if ($FirstMode -eq 'SupplierPaymentLarge') {
            foreach ($worker in @($first, $second)) { $worker.Process.WaitForExit(30000) | Should -BeTrue }
            @($first.Process.ExitCode, $second.Process.ExitCode | Sort-Object) | Should -Be @(0, 1)
            ($first.Error.Result + $second.Error.Result) | Should -BeLike '*exceeds the remaining amount*'
        }
        else {
            Complete-LockTestWorker $first
            Complete-LockTestWorker $second
        }
        $invoice = Get-LedgerSupplierInvoice -JournalPath $journal -InvoiceNumber 1
        $invoice.Payments | Should -HaveCount $Count
        $invoice.PaidAmount | Should -Be $Amount
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount (1 + $Count)
        if ($FirstMode -eq 'Bank') {
            (Get-LedgerBankTransaction -JournalPath $journal -TransactionId 1).MatchType | Should -Be 'SupplierInvoice'
        }
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
    }

    It 'Resumes a bank account posting and both transfer links after <Checkpoint>' -ForEach @(
        @{ Checkpoint = 'AccountAfterPlan' }
        @{ Checkpoint = 'AccountAfterSave' }
        @{ Checkpoint = 'AccountAfterSeal' }
        @{ Checkpoint = 'AccountAfterLink' }
        @{ Checkpoint = 'AccountAfterCounterpart' }
    ) {
        New-LockTestTransfer
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        $plan = Join-Path $journal 'bank' 'posting' 'txn1.txt'
        $hash = (Get-FileHash -LiteralPath $plan).Hash
        $savedPath = Join-Path $journal $year 'ver0001.txt'
        $savedHash = if (Test-Path -LiteralPath $savedPath) { (Get-FileHash -LiteralPath $savedPath).Hash }
        (Add-LedgerEntry @entry -PassThru).VerificationNumber | Should -Be 2
        Set-Content -LiteralPath $gate -Value 'go'
        Complete-LockTestWorker (Start-LockTestWorker Bank)
        $transactions = @(Get-LedgerBankTransaction -JournalPath $journal)
        $transactions.Status | Should -Be @('Matched', 'Matched')
        $transactions.VerificationNumber | Should -Be @(1, 1)
        (Get-FileHash -LiteralPath $plan).Hash | Should -Be $hash
        if ($savedHash) { (Get-FileHash -LiteralPath $savedPath).Hash | Should -Be $savedHash }
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
    }

    It 'Resumes a bank posting in a closed year only if its verification exists: <Saved>' -ForEach @(
        @{ Saved = $true; Checkpoint = 'AccountAfterSave' }
        @{ Saved = $false; Checkpoint = 'AccountAfterPlan' }
    ) {
        New-LockTestTransfer
        $paused = Start-LockTestWorker $Checkpoint
        Wait-LockTestReady $paused
        $paused.Process.Kill($true)
        $paused.Process.WaitForExit()
        Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $year -SkipResultEntry | Out-Null
        if ($Saved) {
            Invoke-LedgerBankMatching -JournalPath $journal | Out-Null
            @(Get-LedgerBankTransaction -JournalPath $journal).Status | Should -Be @('Matched', 'Matched')
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 1
        }
        else {
            { Invoke-LedgerBankMatching -JournalPath $journal } | Should -Throw '*closed*'
            @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 0
        }
    }

    It 'Serializes competing manual postings of the same bank transfer' {
        New-LockTestTransfer
        $first = Start-LockTestWorker Account
        $second = Start-LockTestWorker Account
        Wait-LockTestReady $first
        Wait-LockTestReady $second
        Set-Content -LiteralPath $gate -Value 'go'
        Complete-LockTestWorker $first
        Complete-LockTestWorker $second
        @(Get-LedgerBankTransaction -JournalPath $journal).VerificationNumber | Should -Be @(1, 1)
        @(Get-LedgerEntry -JournalPath $journal -FiscalYear $year) | Should -HaveCount 1
        (Test-LedgerIntegrity -JournalPath $journal -FiscalYear $year).IsValid | Should -BeTrue
    }

    It 'Serializes concurrent bank imports before allocating identities' {
        $null = New-LockTestBankSource
        $first = Start-LockTestWorker BankImport
        $second = Start-LockTestWorker BankImport
        Wait-LockTestReady $first
        Wait-LockTestReady $second
        Set-Content -LiteralPath $gate -Value 'go'
        Complete-LockTestWorker $first
        Complete-LockTestWorker $second
        @(Get-LedgerBankTransaction -JournalPath $journal) | Should -HaveCount 1
        @(Get-LedgerBankStatement -JournalPath $journal) | Should -HaveCount 1
    }
}
