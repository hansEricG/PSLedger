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
        if ($Mode -eq 'Seal') {
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
}
