BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'New-LedgerEntryRow' {
    BeforeAll {
        $CommandName = 'New-LedgerEntryRow'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a Debit parameter of type String' {
            $Param = $Command.Parameters['Debit']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have a Credit parameter of type String' {
            $Param = $Command.Parameters['Credit']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have a mandatory Amount parameter of type Decimal' {
            $Param = $Command.Parameters['Amount']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'Decimal'
            $Param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have an optional Objects parameter of type Hashtable' {
            $Param = $Command.Parameters['Objects']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'Hashtable'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }
    }

    Context 'Behavior' {
        It 'Should store a positive amount for a debit row' {
            $row = New-LedgerEntryRow -Debit '1910' 5000
            $row.Account | Should -Be '1910'
            $row.Amount | Should -Be 5000
        }

        It 'Should store a negative amount for a credit row' {
            $row = New-LedgerEntryRow -Credit '3010' 5000
            $row.Account | Should -Be '3010'
            $row.Amount | Should -Be -5000
        }

        It 'Should return a hashtable compatible with Add-LedgerEntry -Rows' {
            $row = New-LedgerEntryRow -Debit '1910' 100
            $row | Should -BeOfType [hashtable]
            $row.ContainsKey('Account') | Should -BeTrue
            $row.ContainsKey('Amount') | Should -BeTrue
        }

        It 'Should include Objects when supplied' {
            $row = New-LedgerEntryRow -Debit '5010' 8000 -Objects @{ 1 = 'sthlm' }
            $row.Objects[1] | Should -Be 'sthlm'
        }

        It 'Should not include an Objects key when not supplied' {
            $row = New-LedgerEntryRow -Debit '5010' 8000
            $row.ContainsKey('Objects') | Should -BeFalse
        }

        It 'Should not include an Objects key for an empty hashtable' {
            $row = New-LedgerEntryRow -Debit '5010' 8000 -Objects @{}
            $row.ContainsKey('Objects') | Should -BeFalse
        }

        It 'Should throw when amount is zero' {
            { New-LedgerEntryRow -Debit '1910' 0 } | Should -Throw '*positive*'
        }

        It 'Should throw when amount is negative' {
            { New-LedgerEntryRow -Debit '1910' -100 } | Should -Throw '*positive*'
        }

        It 'Should not allow Debit and Credit together' {
            { New-LedgerEntryRow -Debit '1910' -Credit '3010' -Amount 100 } | Should -Throw
        }

        It 'Should produce balanced rows that sum to zero' {
            $rows = @(
                New-LedgerEntryRow -Debit '1910' 5000
                New-LedgerEntryRow -Credit '3010' 5000
            )
            ($rows | ForEach-Object { $_.Amount } | Measure-Object -Sum).Sum | Should -Be 0
        }
    }
}
