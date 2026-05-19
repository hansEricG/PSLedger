BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    Import-Module TDDSeams -Force
}

Describe 'New-LedgerJournal' {
    BeforeAll {
        $CommandName = 'New-LedgerJournal'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory Path parameter of type String' {
            $Param = $Command.Parameters['Path']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $TestFile = [System.IO.Path]::GetRandomFileName() + '.ledger'
            $TestPath = Join-Path $TestDrive $TestFile
        }

        It 'Should create a new ledger file at the specified path' {
            New-LedgerJournal -Path $TestPath

            Test-Path $TestPath | Should -BeTrue
        }

        It 'Should write a valid header to the file' {
            New-LedgerJournal -Path $TestPath

            $Content = Get-Content $TestPath -Raw
            $Content | Should -Match '^; PSLedger Journal'
        }

        It 'Should throw if the file already exists' {
            New-LedgerJournal -Path $TestPath

            { New-LedgerJournal -Path $TestPath } | Should -Throw
        }
    }
}
