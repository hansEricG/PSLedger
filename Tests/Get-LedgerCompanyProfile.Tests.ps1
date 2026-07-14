BeforeAll {
    Import-Module "$PSScriptRoot/../PSLedger/PSLedger.psd1" -Force
    Import-Module TDDUtils -Force
    Import-Module TDDSeams -Force
}

Describe 'Get-LedgerCompanyProfile' {
    Context 'Function metadata' {
        BeforeAll {
            $Command = Get-Command Get-LedgerCompanyProfile
        }

        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a JournalPath parameter' {
            $Command.Parameters.Keys | Should -Contain 'JournalPath'
        }
    }

    Context 'Behavior' {
        BeforeAll {
            $jp = Join-Path $TestDrive 'profile.ledger'
            New-LedgerJournal -Path $jp -Name 'Profil AB' -OrgNumber '556000-1111' -CompanyType 'AB'
            Set-LedgerJournal -JournalPath $jp -Metadata @{
                RegisteredOffice = 'Stockholm'
                BusinessObject   = 'Handel med varor.'
                NumberOfShares   = '500'
                ShareCapital     = '50000'
                BoardMembers     = 'Anna Andersson; Bertil Bengtsson ;Cecilia Carlsson'
            }
        }

        It 'Should return the company name and organisation number' {
            $profile = Get-LedgerCompanyProfile -JournalPath $jp
            $profile.Name | Should -Be 'Profil AB'
            $profile.OrgNumber | Should -Be '556000-1111'
            $profile.CompanyType | Should -Be 'AB'
        }

        It 'Should read the registered office and business object from metadata' {
            $profile = Get-LedgerCompanyProfile -JournalPath $jp
            $profile.RegisteredOffice | Should -Be 'Stockholm'
            $profile.BusinessObject | Should -Be 'Handel med varor.'
        }

        It 'Should parse numeric fields as numbers' {
            $profile = Get-LedgerCompanyProfile -JournalPath $jp
            $profile.NumberOfShares | Should -Be 500
            $profile.ShareCapital | Should -Be 50000
        }

        It 'Should split board members on semicolons and trim whitespace' {
            $profile = Get-LedgerCompanyProfile -JournalPath $jp
            $profile.BoardMembers.Count | Should -Be 3
            $profile.BoardMembers[0] | Should -Be 'Anna Andersson'
            $profile.BoardMembers[1] | Should -Be 'Bertil Bengtsson'
            $profile.BoardMembers[2] | Should -Be 'Cecilia Carlsson'
        }

        It 'Should return empty board members and null fields when metadata is absent' {
            $bare = Join-Path $TestDrive 'bare.ledger'
            New-LedgerJournal -Path $bare -Name 'Bar AB' -OrgNumber '556222-3333' -CompanyType 'AB'
            $profile = Get-LedgerCompanyProfile -JournalPath $bare
            $profile.BoardMembers.Count | Should -Be 0
            $profile.RegisteredOffice | Should -BeNullOrEmpty
            $profile.NumberOfShares | Should -BeNullOrEmpty
        }
    }
}
