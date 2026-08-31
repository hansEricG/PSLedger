BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Set-LedgerReportInput' {
    BeforeAll {
        $CommandName = 'Set-LedgerReportInput'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should support ShouldProcess (-WhatIf / -Confirm)' {
            $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
            $Command.Parameters.ContainsKey('Confirm') | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have a FiscalYear parameter of type String' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have a SignificantEvents parameter' {
            $Command.Parameters.ContainsKey('SignificantEvents') | Should -BeTrue
        }

        It 'Should have a ProposedDividend parameter' {
            $Command.Parameters.ContainsKey('ProposedDividend') | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $jp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            New-LedgerJournal -Path $jp -Name 'Rapport AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-09-01' -EndDate '2025-08-31'
            $fy = '2024-09_2025-08'
        }

        It 'Should create report.txt in the fiscal year directory' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -SigningPlace 'Gävle'
            Test-Path (Join-Path $jp "$fy\report.txt") | Should -BeTrue
        }

        It 'Should persist scalar fields' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -ProposedDividend '0' -SigningPlace 'Gävle' -SigningDate '2025-10-01'
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.ProposedDividend | Should -Be '0'
            $result.SigningPlace | Should -Be 'Gävle'
            $result.SigningDate | Should -Be '2025-10-01'
        }

        It 'Should persist a multi-line SignificantEvents field with Swedish characters' {
            $text = "Under bolagets femtonde räkenskapsår.`nInga väsentliga händelser."
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -SignificantEvents $text
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.SignificantEvents | Should -Be $text
        }

        It 'Should preserve existing fields when updating a different field' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -SigningPlace 'Gävle'
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -ProposedDividend '5000'
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.SigningPlace | Should -Be 'Gävle'
            $result.ProposedDividend | Should -Be '5000'
        }

        It 'Should remove a field when passed an empty string' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -SigningPlace 'Gävle'
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -SigningPlace ''
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.SigningPlace | Should -BeNullOrEmpty
        }

        It 'Should throw when no field is supplied' {
            { Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy } | Should -Throw '*Nothing to update*'
        }

        It 'Should not write when -WhatIf is used' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -SigningPlace 'Gävle' -WhatIf
            Test-Path (Join-Path $jp "$fy\report.txt") | Should -BeFalse
        }
    }
}
