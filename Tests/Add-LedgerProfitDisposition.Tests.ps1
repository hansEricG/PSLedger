BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerProfitDisposition' {
    BeforeAll {
        $Command = Get-Command -Name 'Add-LedgerProfitDisposition'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should support ShouldProcess' {
            Test-TDDSupportsShouldProcess -Command $Command | Should -BeTrue
        }

        It 'Should have a DateTime Date parameter and a Decimal Dividend parameter' {
            $Command.Parameters['Date'].ParameterType.Name | Should -Be 'DateTime'
            $Command.Parameters['Dividend'].ParameterType.Name | Should -Be 'Decimal'
        }

        It 'Should default the retained earnings and dividend accounts to 2091 and 2898' {
            $Command.ScriptBlock.Ast.Body.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'RetainedEarningsAccount' } |
                ForEach-Object { $_.DefaultValue.Value } | Should -Be '2091'
            $Command.ScriptBlock.Ast.Body.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'DividendAccount' } |
                ForEach-Object { $_.DefaultValue.Value } | Should -Be '2898'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $jp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            $fy1 = '2023-01_2023-12'
            $fy2 = '2024-01_2024-12'
            New-LedgerJournal -Path $jp -Name 'Disposition AB' -OrgNumber '556000-0004' -CompanyType 'AB'
            foreach ($a in @(
                    @('1910', 'Kassa'), @('2081', 'Aktiekapital'), @('2091', 'Balanserad vinst eller förlust'),
                    @('2099', 'Årets resultat'), @('2898', 'Outtagen vinstutdelning'),
                    @('3010', 'Försäljning'), @('5010', 'Lokalhyra'), @('8999', 'Årets resultat'))) {
                Add-LedgerAccount -JournalPath $jp -AccountNumber $a[0] -AccountName $a[1]
            }
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2023-01-01' -EndDate '2023-12-31'
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy1 -Date '2023-01-02' -Description 'Aktiekapital' -Rows @(
                @{ Account = '1910'; Amount = 100000 }, @{ Account = '2081'; Amount = -100000 })
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'

            function Complete-Year {
                param ([decimal]$Result, [string]$MeetingDate, [string]$Dividend)
                $rows = if ($Result -ge 0) {
                    @(@{ Account = '1910'; Amount = $Result }, @{ Account = '3010'; Amount = -$Result })
                } else {
                    @(@{ Account = '5010'; Amount = -$Result }, @{ Account = '1910'; Amount = $Result })
                }
                Add-LedgerEntry -JournalPath $jp -FiscalYear $fy1 -Date '2023-06-01' -Description 'Årets affärer' -Rows $rows
                $inputs = @{}
                if ($MeetingDate) { $inputs.AnnualMeetingDate = $MeetingDate }
                if ($Dividend) { $inputs.ProposedDividend = $Dividend }
                if ($inputs.Count) { Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy1 @inputs }
                Close-LedgerFiscalYear -JournalPath $jp -FiscalYear $fy1
                Copy-LedgerOpeningBalance -JournalPath $jp -FromFiscalYear $fy1 -ToFiscalYear $fy2
            }

            function Get-Bal ([string]$Account) {
                $row = Get-LedgerBalance -JournalPath $jp -FiscalYear $fy2 | Where-Object AccountNumber -eq $Account
                if ($row) { [decimal]$row.Balance } else { [decimal]0 }
            }
        }

        It 'Should carry a profit from 2099 to 2091 on the recorded meeting date' {
            Complete-Year -Result 50000 -MeetingDate '2024-05-15'
            $r = Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2

            $r.FromFiscalYear | Should -Be $fy1
            $r.Result | Should -Be 50000
            $r.Dividend | Should -Be 0
            $r.Date | Should -Be ([datetime]'2024-05-15')
            Get-Bal '2099' | Should -Be 0
            Get-Bal '2091' | Should -Be -50000
            $entry = Get-LedgerEntry -JournalPath $jp -FiscalYear $fy2 -VerificationNumber $r.VerificationNumber
            $entry.Description | Should -Be 'Resultatdisposition enligt årsstämma 2024-05-15'
        }

        It 'Should carry a loss from 2099 to 2091' {
            Complete-Year -Result -20000 -MeetingDate '2024-05-15'
            $r = Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2
            $r.Result | Should -Be -20000
            Get-Bal '2099' | Should -Be 0
            Get-Bal '2091' | Should -Be 20000
        }

        It 'Should book the recorded proposed dividend as a liability on 2898' {
            Complete-Year -Result 50000 -MeetingDate '2024-05-15' -Dividend '30000'
            $r = Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2
            $r.Dividend | Should -Be 30000
            $r.CarriedForward | Should -Be 20000
            Get-Bal '2898' | Should -Be -30000
            Get-Bal '2091' | Should -Be -20000
            Get-Bal '2099' | Should -Be 0
        }

        It 'Should let -Date and -Dividend override the recorded report input' {
            Complete-Year -Result 50000 -MeetingDate '2024-05-15' -Dividend '30000'
            $r = Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2 -Date '2024-06-01' -Dividend 0
            $r.Date | Should -Be ([datetime]'2024-06-01')
            $r.Dividend | Should -Be 0
            Get-Bal '2898' | Should -Be 0
        }

        It 'Should throw when no meeting date is recorded or given' {
            Complete-Year -Result 50000
            { Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2 } | Should -Throw '*AnnualMeetingDate*'
        }

        It 'Should throw when the dividend exceeds disposable equity' {
            Complete-Year -Result 50000 -MeetingDate '2024-05-15'
            { Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2 -Dividend 60000 } | Should -Throw '*exceeds*'
        }

        It 'Should throw when the disposition has already been booked' {
            Complete-Year -Result 50000 -MeetingDate '2024-05-15'
            Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2 | Out-Null
            { Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2 } | Should -Throw '*already*'
        }

        It 'Should throw when no fiscal year precedes the booking year' {
            { Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy1 -Date '2023-05-01' } | Should -Throw '*precedes*'
        }

        It 'Should leave retained earnings and the year result in the equity reconciliation unchanged' {
            Complete-Year -Result 50000 -MeetingDate '2024-05-15'
            Add-LedgerEntry -JournalPath $jp -FiscalYear $fy2 -Date '2024-06-01' -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 10000 }, @{ Account = '3010'; Amount = -10000 })
            Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2 | Out-Null

            $eq = Get-LedgerEquityReconciliation -JournalPath $jp -FiscalYear $fy2
            ($eq | Where-Object Component -eq 'RetainedEarnings').OpeningBalance | Should -Be 50000
            ($eq | Where-Object Component -eq 'RetainedEarnings').ClosingBalance | Should -Be 50000
            ($eq | Where-Object Component -eq 'YearResult').ClosingBalance | Should -Be 10000
        }

        It 'Should not book anything with -WhatIf' {
            Complete-Year -Result 50000 -MeetingDate '2024-05-15'
            Add-LedgerProfitDisposition -JournalPath $jp -FiscalYear $fy2 -WhatIf
            Get-Bal '2099' | Should -Be -50000
            @(Get-ChildItem (Join-Path $jp $fy2) -Filter 'ver*.txt').Count | Should -Be 0
        }
    }
}
