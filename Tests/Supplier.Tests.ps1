BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force

    function New-SupplierTestJournal {
        param([string]$Root)
        $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $path -Name 'Faktura AB' -CompanyType AB | Out-Null
        Import-LedgerChart -JournalPath $path -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $path -StartDate '2024-01-01' -EndDate '2024-12-31'
        return $path
    }
}

Describe 'Add-LedgerSupplier' {
    BeforeAll {
        $Command = Get-Command -Name 'Add-LedgerSupplier'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }
        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
        It 'Should have mandatory SupplierNumber and Name parameters' {
            foreach ($p in 'SupplierNumber', 'Name') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-SupplierTestJournal -Root $TestDrive
        }

        It 'Should add a supplier with default payment terms' {
            Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100' -Name 'Kontorsbolaget AB'
            $s = Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100'
            $s.Name | Should -Be 'Kontorsbolaget AB'
            $s.PaymentTermsDays | Should -Be 30
        }

        It 'Should store all optional fields' {
            Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber 'L012' -Name 'Fortum AB' -OrgNumber '556006-8420' -Email 'faktura@fortum.se' -PaymentTermsDays 20
            $s = Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber 'L012'
            $s.OrgNumber | Should -Be '556006-8420'
            $s.Email | Should -Be 'faktura@fortum.se'
            $s.PaymentTermsDays | Should -Be 20
        }

        It 'Should reject a duplicate supplier number' {
            Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100' -Name 'A'
            { Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100' -Name 'B' } | Should -Throw '*already exists*'
        }
    }
}

Describe 'Get-LedgerSupplier' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-SupplierTestJournal -Root $TestDrive
            Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100' -Name 'Alpha AB'
            Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '200' -Name 'Beta AB'
        }

        It 'Should list all suppliers' {
            @(Get-LedgerSupplier -JournalPath $JournalPath).Count | Should -Be 2
        }

        It 'Should filter by supplier number' {
            (Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '200').Name | Should -Be 'Beta AB'
        }

        It 'Should return nothing for an empty register' {
            $empty = New-SupplierTestJournal -Root $TestDrive
            @(Get-LedgerSupplier -JournalPath $empty).Count | Should -Be 0
        }
    }
}

Describe 'Set-LedgerSupplier' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-SupplierTestJournal -Root $TestDrive
            Add-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100' -Name 'Alpha AB' -Email 'old@alpha.se' -PaymentTermsDays 30
        }

        It 'Should update only the specified field' {
            Set-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100' -Email 'new@alpha.se'
            $s = Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100'
            $s.Email | Should -Be 'new@alpha.se'
            $s.Name | Should -Be 'Alpha AB'
            $s.PaymentTermsDays | Should -Be 30
        }

        It 'Should update multiple fields' {
            Set-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100' -Name 'Alpha Group AB' -PaymentTermsDays 45
            $s = Get-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100'
            $s.Name | Should -Be 'Alpha Group AB'
            $s.PaymentTermsDays | Should -Be 45
        }

        It 'Should throw for an unknown supplier' {
            { Set-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '999' -Name 'X' } | Should -Throw '*does not exist*'
        }

        It 'Should throw when nothing is specified to update' {
            { Set-LedgerSupplier -JournalPath $JournalPath -SupplierNumber '100' } | Should -Throw '*Nothing to update*'
        }
    }
}
