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
        if ($Mode -match '^(Invoice|Payment)After') {
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
                        function script:Save-LedgerInvoiceFile { & $script:PostingPause }
                    }
                    'AfterStatus$' {
                        $script:OriginalInvoiceSave = (Get-Command Save-LedgerInvoiceFile).ScriptBlock
                        function script:Save-LedgerInvoiceFile {
                            param ($Invoice)
                            & $script:OriginalInvoiceSave -Invoice $Invoice
                            & $script:PostingPause
                        }
                    }
                }
            } $Ready $Mode
            if ($Mode -like 'Payment*') {
                Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $paymentId -Amount 500.000 -Date '2024-01-20'
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
        elseif ($Mode -like 'Payment*') {
            if ($Mode -in 'PaymentNew', 'PaymentLarge') { $paymentId = [guid]::NewGuid() }
            $amount = if ($Mode -eq 'PaymentLarge') { 900 } else { 500.000 }
            Add-LedgerInvoicePayment -JournalPath $JournalPath -InvoiceNumber 1 -PaymentId $paymentId -Amount $amount -Date '2024-01-20'
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
}
