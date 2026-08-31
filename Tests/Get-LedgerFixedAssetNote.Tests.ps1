BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Get-LedgerFixedAssetNote' {
    BeforeAll {
        $CommandName = 'Get-LedgerFixedAssetNote'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory FromAccount parameter of type Int32' {
            $Param = $Command.Parameters['FromAccount']
            $Param.ParameterType.Name | Should -Be 'Int32'
            $Param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Contain $true
        }

        It 'Should have a mandatory ToAccount parameter of type Int32' {
            $Param = $Command.Parameters['ToAccount']
            $Param.ParameterType.Name | Should -Be 'Int32'
            $Param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'assets.ledger'
            New-LedgerJournal -Path $jp -Name 'Anläggning AB' -OrgNumber '556726-5342' -CompanyType 'AB'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1210' -AccountName 'Inventarier'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1219' -AccountName 'Ack avskrivningar inventarier'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '1930' -AccountName 'Företagskonto'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '7832' -AccountName 'Avskrivningar inventarier'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '2099' -AccountName 'Årets resultat (eget kapital)'
            Add-LedgerAccount -JournalPath $jp -AccountNumber '8999' -AccountName 'Årets resultat'

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2023-01-01' -EndDate '2023-12-31'
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-02-01' -Description 'Köp inventarier' -Rows @(
                @{ Account = '1210'; Amount = 100000 }, @{ Account = '1930'; Amount = -100000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2023-01_2023-12' -Date '2023-12-31' -Description 'Avskrivning' -Rows @(
                @{ Account = '7832'; Amount = 20000 }, @{ Account = '1219'; Amount = -20000 })
            Close-LedgerFiscalYear -JournalPath $jp -FiscalYear '2023-01_2023-12'

            New-LedgerFiscalYear -JournalPath $jp -StartDate '2024-01-01' -EndDate '2024-12-31'
            Copy-LedgerOpeningBalance -JournalPath $jp -FromFiscalYear '2023-01_2023-12' -ToFiscalYear '2024-01_2024-12'
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-02-01' -Description 'Köp inventarier' -Rows @(
                @{ Account = '1210'; Amount = 50000 }, @{ Account = '1930'; Amount = -50000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-06-01' -Description 'Sålt inventarie' -Rows @(
                @{ Account = '1930'; Amount = 30000 }, @{ Account = '1210'; Amount = -30000 })
            Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-12-31' -Description 'Avskrivning' -Rows @(
                @{ Account = '7832'; Amount = 25000 }, @{ Account = '1219'; Amount = -25000 })
        }

        It 'Should roll forward the acquisition value' {
            $note = Get-LedgerFixedAssetNote -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -FromAccount 1210 -ToAccount 1210 -DepreciationFromAccount 1219 -DepreciationToAccount 1219 -Label 'Inventarier'
            $note.OpeningAcquisition | Should -Be 100000
            $note.Purchases | Should -Be 50000
            $note.Disposals | Should -Be -30000
            $note.ClosingAcquisition | Should -Be 120000
        }

        It 'Should roll forward accumulated depreciation' {
            $note = Get-LedgerFixedAssetNote -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -FromAccount 1210 -ToAccount 1210 -DepreciationFromAccount 1219 -DepreciationToAccount 1219
            $note.OpeningDepreciation | Should -Be -20000
            $note.YearDepreciation | Should -Be -25000
            $note.ClosingDepreciation | Should -Be -45000
        }

        It 'Should compute the carrying amount' {
            $note = Get-LedgerFixedAssetNote -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -FromAccount 1210 -ToAccount 1210 -DepreciationFromAccount 1219 -DepreciationToAccount 1219
            $note.BookValue | Should -Be 75000
        }

        It 'Should work without a depreciation range' {
            $note = Get-LedgerFixedAssetNote -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -FromAccount 1210 -ToAccount 1210
            $note.HasDepreciation | Should -BeFalse
            $note.BookValue | Should -Be 120000
        }

        It 'Should return nothing when the range has no accounts' {
            $note = Get-LedgerFixedAssetNote -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -FromAccount 1400 -ToAccount 1499
            $note | Should -BeNullOrEmpty
        }

        It 'Should use the supplied label' {
            $note = Get-LedgerFixedAssetNote -JournalPath $jp -FiscalYear '2024-01_2024-12' `
                -FromAccount 1210 -ToAccount 1210 -Label 'Inventarier'
            $note.Label | Should -Be 'Inventarier'
        }
    }
}
