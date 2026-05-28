BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerObject' {
    BeforeAll {
        $CommandName = 'Add-LedgerObject'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter and mandatory DimensionNumber, ObjectNumber and Name' {
            $Command.Parameters['JournalPath'].Attributes.Mandatory | Should -Not -Contain $true
            foreach ($p in 'DimensionNumber', 'ObjectNumber', 'Name') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Obj AB'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Kostnadsställe'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 2 -Name 'Projekt'
        }

        It 'Should create objects.txt with the entry' {
            Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber 'sthlm' -Name 'Stockholm'
            $file = Join-Path $JournalPath 'objects.txt'
            Test-Path $file | Should -BeTrue
            $content = Get-Content $file -Raw
            $content | Should -Match "1`tsthlm`tStockholm"
        }

        It 'Should throw if dimension does not exist' {
            { Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 99 -ObjectNumber 'x' -Name 'X' } |
                Should -Throw '*does not exist*'
        }

        It 'Should throw if object already exists in the dimension' {
            Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber 'sthlm' -Name 'Stockholm'
            { Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber 'sthlm' -Name 'Dup' } |
                Should -Throw '*already exists*'
        }

        It 'Should allow same object number in different dimensions' {
            Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber 'alpha' -Name 'Alpha KS'
            { Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 2 -ObjectNumber 'alpha' -Name 'Alpha Proj' } |
                Should -Not -Throw
        }
    }
}

Describe 'Get-LedgerObject' {
    BeforeAll {
        $CommandName = 'Get-LedgerObject'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Obj AB'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Kostnadsställe'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 2 -Name 'Projekt'
            Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber 'sthlm' -Name 'Stockholm'
            Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber 'gbg' -Name 'Göteborg'
            Add-LedgerObject -JournalPath $JournalPath -DimensionNumber 2 -ObjectNumber 'proj-a' -Name 'Projekt Alpha'
        }

        It 'Should return all objects when no filter' {
            $result = @(Get-LedgerObject -JournalPath $JournalPath)
            $result.Count | Should -Be 3
        }

        It 'Should filter by DimensionNumber' {
            $result = @(Get-LedgerObject -JournalPath $JournalPath -DimensionNumber 1)
            $result.Count | Should -Be 2
            $result.ObjectNumber | Should -Contain 'sthlm'
        }

        It 'Should filter by ObjectNumber within a dimension' {
            $result = Get-LedgerObject -JournalPath $JournalPath -DimensionNumber 1 -ObjectNumber 'gbg'
            $result.Name | Should -Be 'Göteborg'
        }
    }
}
