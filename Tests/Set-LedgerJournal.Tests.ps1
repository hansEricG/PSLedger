BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    Import-Module TDDSeams -Force
}

Describe 'Set-LedgerJournal' {
    BeforeAll {
        $CommandName = 'Set-LedgerJournal'
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

        It 'Should have an optional Name parameter of type String' {
            $Param = $Command.Parameters['Name']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have an optional OrgNumber parameter of type String' {
            $Param = $Command.Parameters['OrgNumber']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB' -OrgNumber '556677-8899'
            $JournalFile = Join-Path $JournalPath 'journal.txt'
        }

        It 'Should update the company name' {
            Set-LedgerJournal -JournalPath $JournalPath -Name 'Nya Namnet AB'

            (Get-LedgerJournal -Path $JournalPath).Name | Should -Be 'Nya Namnet AB'
        }

        It 'Should update the organisation number' {
            Set-LedgerJournal -JournalPath $JournalPath -OrgNumber '999888-7777'

            (Get-LedgerJournal -Path $JournalPath).OrgNumber | Should -Be '999888-7777'
        }

        It 'Should update both name and org number in one call' {
            Set-LedgerJournal -JournalPath $JournalPath -Name 'Konsult AB' -OrgNumber '111222-3333'

            $Journal = Get-LedgerJournal -Path $JournalPath
            $Journal.Name | Should -Be 'Konsult AB'
            $Journal.OrgNumber | Should -Be '111222-3333'
        }

        It 'Should leave the org number unchanged when only the name is updated' {
            Set-LedgerJournal -JournalPath $JournalPath -Name 'Bara Namn AB'

            (Get-LedgerJournal -Path $JournalPath).OrgNumber | Should -Be '556677-8899'
        }

        It 'Should add an org number to a journal that has none' {
            $NoOrgPath = Join-Path $TestDrive 'NoOrg.ledger'
            New-LedgerJournal -Path $NoOrgPath -Name 'Utan Orgnr AB'

            Set-LedgerJournal -JournalPath $NoOrgPath -OrgNumber '556677-8899'

            (Get-LedgerJournal -Path $NoOrgPath).OrgNumber | Should -Be '556677-8899'
        }

        It 'Should remove the org number when passed an empty string' {
            Set-LedgerJournal -JournalPath $JournalPath -OrgNumber ''

            (Get-LedgerJournal -Path $JournalPath).OrgNumber | Should -BeNullOrEmpty
        }

        It 'Should preserve the SchemaVersion field' {
            $Before = (Get-LedgerJournal -Path $JournalPath).SchemaVersion

            Set-LedgerJournal -JournalPath $JournalPath -Name 'Behåller Schema AB'

            (Get-LedgerJournal -Path $JournalPath).SchemaVersion | Should -Be $Before
        }

        It 'Should preserve comment lines in journal.txt' {
            Set-LedgerJournal -JournalPath $JournalPath -Name 'Kommentarer AB'

            (Get-Content $JournalFile -Raw) | Should -Match '; PSLedger Journal'
        }

        It 'Should store custom metadata fields via -Metadata' {
            Set-LedgerJournal -JournalPath $JournalPath -Metadata @{ VatNumber = 'SE556677889901' }

            (Get-LedgerJournal -Path $JournalPath).Metadata.VatNumber | Should -Be 'SE556677889901'
        }

        It 'Should store multiple metadata fields in one call' {
            Set-LedgerJournal -JournalPath $JournalPath -Metadata @{ VatNumber = 'SE556677889901'; Email = 'info@firma.se' }

            $Meta = (Get-LedgerJournal -Path $JournalPath).Metadata
            $Meta.VatNumber | Should -Be 'SE556677889901'
            $Meta.Email | Should -Be 'info@firma.se'
        }

        It 'Should update an existing metadata field in place' {
            Set-LedgerJournal -JournalPath $JournalPath -Metadata @{ VatNumber = 'SE111111111101' }
            Set-LedgerJournal -JournalPath $JournalPath -Metadata @{ VatNumber = 'SE999999999901' }

            (Get-LedgerJournal -Path $JournalPath).Metadata.VatNumber | Should -Be 'SE999999999901'
        }

        It 'Should remove a metadata field when its value is empty' {
            Set-LedgerJournal -JournalPath $JournalPath -Metadata @{ VatNumber = 'SE556677889901' }
            Set-LedgerJournal -JournalPath $JournalPath -Metadata @{ VatNumber = '' }

            (Get-LedgerJournal -Path $JournalPath).Metadata.Contains('VatNumber') | Should -BeFalse
        }

        It 'Should update Name, OrgNumber and metadata together' {
            Set-LedgerJournal -JournalPath $JournalPath -Name 'Allt AB' -OrgNumber '111222-3333' -Metadata @{ VatNumber = 'SE111222333301' }

            $Journal = Get-LedgerJournal -Path $JournalPath
            $Journal.Name | Should -Be 'Allt AB'
            $Journal.OrgNumber | Should -Be '111222-3333'
            $Journal.Metadata.VatNumber | Should -Be 'SE111222333301'
        }

        It 'Should throw when a metadata key is a reserved field' {
            { Set-LedgerJournal -JournalPath $JournalPath -Metadata @{ Name = 'X' } } | Should -Throw
        }

        It 'Should throw when a metadata key is not a valid identifier' {
            { Set-LedgerJournal -JournalPath $JournalPath -Metadata @{ 'Bad Key' = 'X' } } | Should -Throw
        }

        It 'Should throw when neither Name nor OrgNumber is supplied' {
            { Set-LedgerJournal -JournalPath $JournalPath } | Should -Throw
        }

        It 'Should throw when the journal does not exist' {
            $Missing = Join-Path $TestDrive 'DoesNotExist.ledger'
            { Set-LedgerJournal -JournalPath $Missing -Name 'X' } | Should -Throw
        }

        It 'Should not modify the journal when -WhatIf is used' {
            Set-LedgerJournal -JournalPath $JournalPath -Name 'Skall Inte Sparas AB' -WhatIf

            (Get-LedgerJournal -Path $JournalPath).Name | Should -Be 'Testföretaget AB'
        }
    }
}
