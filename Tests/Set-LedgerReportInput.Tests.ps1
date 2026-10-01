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

        It 'Should have a nullable Int32 AverageEmployees parameter' {
            $Command.Parameters['AverageEmployees'].ParameterType | Should -Be ([Nullable[int]])
        }

        It 'Should have nullable DateTime <_> parameter' -ForEach 'SigningDate', 'AnnualMeetingDate' {
            $Command.Parameters[$_].ParameterType | Should -Be ([Nullable[datetime]])
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $jp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            New-LedgerJournal -Path $jp -Name 'Rapport AB' -OrgNumber '556000-0003' -CompanyType 'AB'
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

        It 'Should persist the fastställelseintyg fields' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -AnnualMeetingDate '2025-10-01' -CertificatePlace 'Gävle' -CertificateSigner 'Anna Andersson'
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.AnnualMeetingDate | Should -Be '2025-10-01'
            $result.CertificatePlace | Should -Be 'Gävle'
            $result.CertificateSigner | Should -Be 'Anna Andersson'
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

        It 'Should store dates as yyyy-MM-dd and numbers as text' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -SigningDate (Get-Date -Year 2025 -Month 10 -Day 1 -Hour 14) -AverageEmployees 3
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.SigningDate | Should -Be '2025-10-01'
            $result.AverageEmployees | Should -Be '3'
        }

        It 'Should remove a date or number field when passed $null' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -AnnualMeetingDate '2025-10-01' -AverageEmployees 2
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -AnnualMeetingDate $null -AverageEmployees $null
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.AnnualMeetingDate | Should -BeNullOrEmpty
            $result.AverageEmployees | Should -BeNullOrEmpty
        }

        It 'Should reject an invalid date' {
            { Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -SigningDate 'inte ett datum' } | Should -Throw '*SigningDate*'
        }

        It 'Should persist the K3 fields' {
            Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -Framework K3 -TransitionNote 'Omklassificering.' `
                -DeferredTaxStatement 'Ingen uppskjuten skatt.' -PledgedAssets 'Inga' -ContingentLiabilities 'Inga' `
                -EventsAfterBalanceDate 'Inga.' -Ownership 'Anna Andersson äger samtliga aktier.'
            $result = Get-LedgerReportInput -JournalPath $jp -FiscalYear $fy
            $result.Framework | Should -Be 'K3'
            $result.TransitionNote | Should -Be 'Omklassificering.'
            $result.DeferredTaxStatement | Should -Be 'Ingen uppskjuten skatt.'
            $result.PledgedAssets | Should -Be 'Inga'
            $result.ContingentLiabilities | Should -Be 'Inga'
            $result.EventsAfterBalanceDate | Should -Be 'Inga.'
            $result.Ownership | Should -Be 'Anna Andersson äger samtliga aktier.'
        }

        It 'Should reject an unknown framework' {
            { Set-LedgerReportInput -JournalPath $jp -FiscalYear $fy -Framework 'K4' } | Should -Throw
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
