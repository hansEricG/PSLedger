BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Import-LedgerChart' {
    BeforeAll {
        $CommandName = 'Import-LedgerChart'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a JournalPath parameter of type String' {
            $Param = $Command.Parameters['JournalPath']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have a Template parameter of type String' {
            $Param = $Command.Parameters['Template']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have a Path parameter of type String' {
            $Param = $Command.Parameters['Path']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have a ListAvailable switch parameter' {
            $Param = $Command.Parameters['ListAvailable']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have a Force switch parameter' {
            $Param = $Command.Parameters['Force']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'ListAvailable' {
        It 'Should return available template names' {
            $JournalPath = Join-Path $TestDrive 'listavailable.ledger'
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
            Set-LedgerJournal -Path $JournalPath

            try {
                $Result = Import-LedgerChart -ListAvailable

                $Result | Should -Contain 'BAS-Mini'
                $Result | Should -Contain 'BAS-Smaforetag'
                $Result | Should -Contain 'BAS-Komplett'
            }
            finally {
                Clear-LedgerJournal
            }
        }
    }

    Context 'Import from template' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'
        }

        It 'Should import BAS-Mini template into the journal' {
            Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Mini'

            $Accounts = Get-LedgerAccount -JournalPath $JournalPath
            $Accounts.Count | Should -BeGreaterThan 25
        }

        It 'Should import BAS-Smaforetag template into the journal' {
            Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Smaforetag'

            $Accounts = Get-LedgerAccount -JournalPath $JournalPath
            $Accounts.Count | Should -BeGreaterThan 60
        }

        It 'Should import BAS-Komplett template into the journal' {
            Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Komplett'

            $Accounts = Get-LedgerAccount -JournalPath $JournalPath
            $Accounts.Count | Should -BeGreaterThan 200
        }

        It 'Should throw if template does not exist' {
            { Import-LedgerChart -JournalPath $JournalPath -Template 'NonExistent' } | Should -Throw '*not found*'
        }

        It 'Should throw if journal already has accounts' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa'

            { Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Mini' } | Should -Throw '*already has accounts*'
        }

        It 'Should replace existing accounts when -Force is used' {
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '9999' -AccountName 'Temp'

            Import-LedgerChart -JournalPath $JournalPath -Template 'BAS-Mini' -Force

            $Accounts = Get-LedgerAccount -JournalPath $JournalPath
            $Accounts.Count | Should -BeGreaterThan 25
            $Accounts | Where-Object { $_.AccountNumber -eq '9999' } | Should -BeNullOrEmpty
        }

        It 'Should throw if journal path does not exist' {
            { Import-LedgerChart -JournalPath (Join-Path $TestDrive 'nonexistent.ledger') -Template 'BAS-Mini' } | Should -Throw
        }
    }

    Context 'Import from file' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB'

            $CustomChart = Join-Path $TestDrive 'custom-chart.tsv'
            @(
                "1910`tKassa"
                "2440`tLeverantörsskulder"
                "3010`tFörsäljning"
            ) | Set-Content -Path $CustomChart -Encoding UTF8
        }

        It 'Should import from an external file' {
            Import-LedgerChart -JournalPath $JournalPath -Path (Join-Path $TestDrive 'custom-chart.tsv')

            $Accounts = Get-LedgerAccount -JournalPath $JournalPath
            $Accounts.Count | Should -Be 3
            ($Accounts | Where-Object { $_.AccountNumber -eq '1910' }).AccountName | Should -Be 'Kassa'
        }

        It 'Should throw if file does not exist' {
            { Import-LedgerChart -JournalPath $JournalPath -Path (Join-Path $TestDrive 'missing.tsv') } | Should -Throw '*not found*'
        }
    }
}
