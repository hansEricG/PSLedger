BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Add-LedgerCustomer' {
    BeforeAll {
        $CommandName = 'Add-LedgerCustomer'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional JournalPath and mandatory CustomerNumber and Name parameters' {
            $Command.Parameters['JournalPath'].Attributes.Mandatory | Should -Not -Contain $true
            foreach ($p in 'CustomerNumber', 'Name') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Kund AB'
        }

        It 'Should create customers.txt with the entry' {
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
            $file = Join-Path $JournalPath 'customers.txt'
            Test-Path $file | Should -BeTrue
            (Get-Content $file -Raw) | Should -Match "10`tVolvo AB`t`t`t30"
        }

        It 'Should store the supplied optional fields' {
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber 'K012' -Name 'Ericsson AB' `
                -OrgNumber '556016-0680' -Email 'faktura@ericsson.se' -PaymentTermsDays 20
            $c = Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber 'K012'
            $c.OrgNumber | Should -Be '556016-0680'
            $c.Email | Should -Be 'faktura@ericsson.se'
            $c.PaymentTermsDays | Should -Be 20
        }

        It 'Should default PaymentTermsDays to 30' {
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
            (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10').PaymentTermsDays | Should -Be 30
        }

        It 'Should throw if the customer number already exists' {
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
            { Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Dup' } |
                Should -Throw '*already exists*'
        }
    }
}

Describe 'Get-LedgerCustomer' {
    BeforeAll {
        $CommandName = 'Get-LedgerCustomer'
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
            New-LedgerJournal -Path $JournalPath -Name 'Kund AB'
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB'
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '20' -Name 'Saab AB'
        }

        It 'Should return all customers' {
            $result = @(Get-LedgerCustomer -JournalPath $JournalPath)
            $result.Count | Should -Be 2
            $result[0].CustomerNumber | Should -Be '10'
            $result[1].Name | Should -Be 'Saab AB'
        }

        It 'Should filter by CustomerNumber' {
            (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '20').Name | Should -Be 'Saab AB'
        }

        It 'Should return nothing when customers.txt does not exist' {
            $j2 = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $j2 -Name 'Empty'
            Get-LedgerCustomer -JournalPath $j2 | Should -BeNullOrEmpty
        }
    }
}

Describe 'Set-LedgerCustomer' {
    BeforeAll {
        $CommandName = 'Set-LedgerCustomer'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should support ShouldProcess' {
            $Command.Parameters['WhatIf'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Kund AB'
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo AB' -PaymentTermsDays 30
        }

        It 'Should update only the supplied field' {
            Set-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Email 'ny@volvo.se'
            $c = Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10'
            $c.Email | Should -Be 'ny@volvo.se'
            $c.Name | Should -Be 'Volvo AB'
            $c.PaymentTermsDays | Should -Be 30
        }

        It 'Should update name and payment terms together' {
            Set-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo Group AB' -PaymentTermsDays 45
            $c = Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10'
            $c.Name | Should -Be 'Volvo Group AB'
            $c.PaymentTermsDays | Should -Be 45
        }

        It 'Should not change other customers' {
            Add-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '20' -Name 'Saab AB'
            Set-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' -Name 'Volvo Group AB'
            (Get-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '20').Name | Should -Be 'Saab AB'
        }

        It 'Should throw when the customer does not exist' {
            { Set-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '99' -Name 'X' } |
                Should -Throw '*does not exist*'
        }

        It 'Should throw when nothing is supplied to update' {
            { Set-LedgerCustomer -JournalPath $JournalPath -CustomerNumber '10' } |
                Should -Throw '*Nothing to update*'
        }
    }
}
