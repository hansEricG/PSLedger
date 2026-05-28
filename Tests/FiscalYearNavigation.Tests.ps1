BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Fiscal Year Navigation' {
    BeforeAll {
        # Set up a journal with 3 fiscal years
        $journalDir = Join-Path $TestDrive 'NavTest.ledger'
        New-LedgerJournal -Path $journalDir -Name 'NavTest AB' -OrgNumber '556000-0001'
        New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2022-01-01' -EndDate '2022-12-31'
        New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2023-01-01' -EndDate '2023-12-31'
        New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2024-01-01' -EndDate '2024-12-31'
        Close-LedgerFiscalYear -JournalPath $journalDir -FiscalYear '2022-01_2022-12'
        Close-LedgerFiscalYear -JournalPath $journalDir -FiscalYear '2023-01_2023-12'
        Set-LedgerJournal -Path $journalDir
    }

    AfterAll {
        Clear-LedgerJournal
    }

    Context 'Get-LedgerFirstFiscalYear' {
        BeforeAll {
            $Command = Get-Command -Name 'Get-LedgerFirstFiscalYear'
        }

        It 'Should exist as a command' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should return the oldest fiscal year' {
            $result = Get-LedgerFirstFiscalYear
            $result.Name | Should -Be '2022-01_2022-12'
        }

        It 'Should return object with Name, StartDate, EndDate, Status' {
            $result = Get-LedgerFirstFiscalYear
            $result.Name | Should -Not -BeNullOrEmpty
            $result.StartDate | Should -Not -BeNullOrEmpty
            $result.EndDate | Should -Not -BeNullOrEmpty
            $result.Status | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-LedgerLatestFiscalYear' {
        BeforeAll {
            $Command = Get-Command -Name 'Get-LedgerLatestFiscalYear'
        }

        It 'Should exist as a command' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should return the most recent fiscal year regardless of status' {
            $result = Get-LedgerLatestFiscalYear
            $result.Name | Should -Be '2024-01_2024-12'
            $result.Status | Should -Be 'Open'
        }
    }

    Context 'Get-LedgerLatestOpenFiscalYear' {
        BeforeAll {
            $Command = Get-Command -Name 'Get-LedgerLatestOpenFiscalYear'
        }

        It 'Should exist as a command' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should return the most recent open fiscal year' {
            $result = Get-LedgerLatestOpenFiscalYear
            $result.Name | Should -Be '2024-01_2024-12'
            $result.Status | Should -Be 'Open'
        }

        It 'Should skip closed years' {
            $result = Get-LedgerLatestOpenFiscalYear
            $result.Name | Should -Not -Be '2023-01_2023-12'
        }
    }

    Context 'Get-LedgerNextFiscalYear' {
        BeforeAll {
            $Command = Get-Command -Name 'Get-LedgerNextFiscalYear'
        }

        It 'Should exist as a command' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory Name parameter' {
            $Param = $Command.Parameters['Name']
            $Param | Should -Not -BeNullOrEmpty
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should accept pipeline input via Name property' {
            $result = Get-LedgerFirstFiscalYear | Get-LedgerNextFiscalYear
            $result.Name | Should -Be '2023-01_2023-12'
        }

        It 'Should return the next fiscal year by name' {
            $result = Get-LedgerNextFiscalYear -Name '2022-01_2022-12'
            $result.Name | Should -Be '2023-01_2023-12'
        }

        It 'Should return nothing for the last fiscal year' {
            $result = Get-LedgerNextFiscalYear -Name '2024-01_2024-12'
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'Fiscal Year Auto-Resolution' {
    BeforeAll {
        $journalDir = Join-Path $TestDrive 'AutoFY.ledger'
        New-LedgerJournal -Path $journalDir -Name 'AutoFY AB' -OrgNumber '556000-0002'
        New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2023-01-01' -EndDate '2023-12-31'
        New-LedgerFiscalYear -JournalPath $journalDir -StartDate '2024-01-01' -EndDate '2024-12-31'

        # Add an entry to 2024
        $rows = @(
            @{ Account = '1910'; Amount = 1000 }
            @{ Account = '3010'; Amount = -1000 }
        )
        Import-LedgerChart -JournalPath $journalDir -Template 'BAS-Mini'
        Add-LedgerEntry -JournalPath $journalDir -FiscalYear '2024-01_2024-12' `
            -Date '2024-06-15' -Description 'Test' -Rows $rows

        Set-LedgerJournal -Path $journalDir
    }

    AfterAll {
        Clear-LedgerJournal
    }

    It 'Get-LedgerEntry defaults to latest fiscal year when omitted' {
        $entries = Get-LedgerEntry
        $entries | Should -Not -BeNullOrEmpty
        $entries[0].Description | Should -Be 'Test'
    }

    It 'Get-LedgerBalance defaults to latest fiscal year when omitted' {
        $balance = Get-LedgerBalance
        $balance | Should -Not -BeNullOrEmpty
    }

    It 'Pipeline: fiscal year object piped to Get-LedgerEntry' {
        $entries = Get-LedgerLatestFiscalYear | Get-LedgerEntry
        $entries | Should -Not -BeNullOrEmpty
    }

    It 'Pipeline: fiscal year object piped to Get-LedgerBalance' {
        $balance = Get-LedgerLatestFiscalYear | Get-LedgerBalance
        $balance | Should -Not -BeNullOrEmpty
    }

    It 'Pipeline: chained navigation' {
        $second = Get-LedgerFirstFiscalYear | Get-LedgerNextFiscalYear
        $second.Name | Should -Be '2024-01_2024-12'
    }
}
