BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Remove-LedgerHolding' {
    BeforeAll {
        $Command = Get-Command -Name 'Remove-LedgerHolding'
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

        It 'Should have mandatory String parameters Account and Name that bind from the pipeline' {
            foreach ($p in 'Account', 'Name') {
                $Command.Parameters[$p].ParameterType.Name | Should -Be 'String'
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
                $Command.Parameters[$p].Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $jp = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.ledger')
            $fy = '2024-01_2024-12'
            New-LedgerJournal -Path $jp -Name 'Aktier AB' -OrgNumber '556000-0004' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1350' -AccountName 'Andelar och värdepapper'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1810' -AccountName 'Andelar i börsnoterade företag'
            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -Quantity 500 -Price 265
            Set-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1810 -Name 'Spiltan Räntefond' -Quantity 1000 -Price 11.83
            $file = Join-Path $jp $fy 'holdings.txt'
        }

        It 'Should remove the holding' {
            Remove-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B'
            (Get-LedgerHolding -JournalPath $jp -FiscalYear $fy).Name | Should -Be 'Spiltan Räntefond'
        }

        It 'Should delete holdings.txt when the last holding is removed' {
            Get-LedgerHolding -JournalPath $jp -FiscalYear $fy | Remove-LedgerHolding -JournalPath $jp
            Test-Path $file | Should -BeFalse
        }

        It 'Should throw when the holding does not exist' {
            { Remove-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1810 -Name 'Investor B' } |
                Should -Throw '*not found*'
        }

        It 'Should refuse to change holdings in a closed fiscal year' {
            Close-LedgerFiscalYear -JournalPath $jp -FiscalYear $fy
            { Remove-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' } |
                Should -Throw '*Closed*'
        }

        It 'Should not remove anything with -WhatIf' {
            Remove-LedgerHolding -JournalPath $jp -FiscalYear $fy -Account 1350 -Name 'Investor B' -WhatIf
            @(Get-LedgerHolding -JournalPath $jp -FiscalYear $fy).Count | Should -Be 2
        }
    }
}
