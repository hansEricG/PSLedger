BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerReportInput' {
    BeforeAll {
        $CommandName = 'Get-LedgerReportInput'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
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
    }

    Context 'Behavior' {
        BeforeEach {
            $jp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            New-LedgerJournal -Path $jp -Name 'Rapport AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-09-01' -EndDate '2025-08-31'
            $fy = '2024-09_2025-08'
        }

        It 'Should return null fields when nothing has been set' {
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.SignificantEvents | Should -BeNullOrEmpty
            $result.ProposedDividend | Should -BeNullOrEmpty
            $result.SigningPlace | Should -BeNullOrEmpty
        }

        It 'Should expose the journal path and fiscal year' {
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.FiscalYear | Should -Be $fy
            $result.JournalPath | Should -Be $jp
        }

        It 'Should round-trip values written by Set-LedgerReportInput' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy `
                -SignificantEvents 'Inga väsentliga händelser.' -ProposedDividend '0' `
                -AverageEmployees '0' -SecuritiesMarketValue '277579' `
                -SigningPlace 'Gävle' -SigningDate '2025-10-01'
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.SignificantEvents | Should -Be 'Inga väsentliga händelser.'
            $result.ProposedDividend | Should -Be '0'
            $result.AverageEmployees | Should -Be '0'
            $result.SecuritiesMarketValue | Should -Be '277579'
            $result.SigningPlace | Should -Be 'Gävle'
            $result.SigningDate | Should -Be '2025-10-01'
        }
    }
}
