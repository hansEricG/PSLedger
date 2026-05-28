BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerDimension' {
    BeforeAll {
        $CommandName = 'Add-LedgerDimension'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional JournalPath parameter and mandatory DimensionNumber and Name parameters' {
            $Command.Parameters['JournalPath'].Attributes.Mandatory | Should -Not -Contain $true
            foreach ($p in 'DimensionNumber', 'Name') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Dim AB'
        }

        It 'Should create dimensions.txt with the entry' {
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Kostnadsställe'
            $file = Join-Path $JournalPath 'dimensions.txt'
            Test-Path $file | Should -BeTrue
            $content = Get-Content $file -Raw
            $content | Should -Match "1`tKostnadsställe"
        }

        It 'Should append multiple dimensions' {
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Kostnadsställe'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 2 -Name 'Projekt'
            $dims = @(Get-LedgerDimension -JournalPath $JournalPath)
            $dims.Count | Should -Be 2
        }

        It 'Should throw if dimension number already exists' {
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Kostnadsställe'
            { Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Dup' } |
                Should -Throw '*already exists*'
        }
    }
}

Describe 'Get-LedgerDimension' {
    BeforeAll {
        $CommandName = 'Get-LedgerDimension'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Dim AB'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 1 -Name 'Kostnadsställe'
            Add-LedgerDimension -JournalPath $JournalPath -DimensionNumber 2 -Name 'Projekt'
        }

        It 'Should return all dimensions' {
            $result = @(Get-LedgerDimension -JournalPath $JournalPath)
            $result.Count | Should -Be 2
            $result[0].DimensionNumber | Should -Be 1
            $result[1].Name | Should -Be 'Projekt'
        }

        It 'Should filter by DimensionNumber' {
            $result = Get-LedgerDimension -JournalPath $JournalPath -DimensionNumber 2
            $result.Name | Should -Be 'Projekt'
        }

        It 'Should return nothing if dimensions.txt does not exist' {
            $j2 = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $j2 -Name 'Empty'
            Get-LedgerDimension -JournalPath $j2 | Should -BeNullOrEmpty
        }
    }
}
