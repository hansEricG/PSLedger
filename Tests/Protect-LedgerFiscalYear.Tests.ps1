BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')
}

Describe 'Protect-LedgerFiscalYear' {
    BeforeAll {
        $CommandName = 'Protect-LedgerFiscalYear'
        $Command = Get-Command -Name $CommandName
        $FiscalYear = '2024-01_2024-12'

        function Add-TestEntry {
            param ([string]$JournalPath, [string]$Year = $FiscalYear, [string]$Date = '2024-02-01')
            $rows = @(
                New-LedgerEntryRow -Debit 6110 -Amount 100
                New-LedgerEntryRow -Credit 1930 -Amount 100
            )
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $Year -Date $Date -Description 'Kontorsmaterial' -Rows $rows
        }
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should support ShouldProcess' {
            $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }

        It 'Should have an optional FiscalYear parameter that binds from Name' {
            $Param = $Command.Parameters['FiscalYear']
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
            $Param.Aliases | Should -Contain 'Name'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-TestLedger -Root $TestDrive
        }

        It 'Seals a year that has no chain and returns the integrity result' {
            Add-TestEntry -JournalPath $JournalPath
            Add-TestEntry -JournalPath $JournalPath
            Remove-Item (Join-Path $JournalPath $FiscalYear 'integrity.txt')

            $result = Protect-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear
            $result.FiscalYear | Should -Be $FiscalYear
            $result.Status | Should -Be 'Valid'
            $result.Verifications | Should -Be 2
            $result.ChainHash | Should -Match '^[0-9a-f]{64}$'
        }

        It 'Seals only what the chain lacks and keeps reporting changed verifications' {
            Add-TestEntry -JournalPath $JournalPath
            $file = Join-Path $JournalPath $FiscalYear 'ver0001.txt'
            (Get-Content $file) -replace '100', '1000' | Set-Content $file
            Copy-Item $file (Join-Path $JournalPath $FiscalYear 'ver0002.txt')

            $result = Protect-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear
            $result.Verifications | Should -Be 2
            @($result.Issues | ForEach-Object { "$($_.Key) $($_.Problem)" }) | Should -Be @('1 Modified')
        }

        It 'Does nothing when everything is sealed' {
            Add-TestEntry -JournalPath $JournalPath
            $chainFile = Join-Path $JournalPath $FiscalYear 'integrity.txt'
            $before = Get-Content -Raw $chainFile

            Protect-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear | Out-Null
            Get-Content -Raw $chainFile | Should -Be $before
        }

        It 'Seals a closed fiscal year' {
            Add-TestEntry -JournalPath $JournalPath
            Close-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear | Out-Null
            Remove-Item (Join-Path $JournalPath $FiscalYear 'integrity.txt')

            (Protect-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear).Status | Should -Be 'Valid'
        }

        It 'Accepts fiscal years from the pipeline' {
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2025-01-01' -EndDate '2025-12-31'
            Add-TestEntry -JournalPath $JournalPath
            Add-TestEntry -JournalPath $JournalPath -Year '2025-01_2025-12' -Date '2025-02-01'
            Get-ChildItem $JournalPath -Recurse -Filter 'integrity.txt' | Remove-Item

            $results = @(Get-LedgerFiscalYear -JournalPath $JournalPath | Protect-LedgerFiscalYear -JournalPath $JournalPath)
            $results.Status | Should -Be @('Valid', 'Valid')
        }

        It 'Writes nothing with -WhatIf' {
            Add-TestEntry -JournalPath $JournalPath
            Remove-Item (Join-Path $JournalPath $FiscalYear 'integrity.txt')

            Protect-LedgerFiscalYear -JournalPath $JournalPath -FiscalYear $FiscalYear -WhatIf
            Test-Path (Join-Path $JournalPath $FiscalYear 'integrity.txt') | Should -BeFalse
        }
    }
}
