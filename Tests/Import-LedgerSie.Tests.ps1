BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Import-LedgerSie' {
    BeforeAll {
        $CommandName = 'Import-LedgerSie'
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
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have an optional FiscalYear parameter of type String' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have a mandatory Path parameter of type String that binds from FullName' {
            $Param = $Command.Parameters['Path']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
            $Param.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $Param.Aliases | Should -Contain 'FullName'
        }

        It 'Should have a CreateMissingAccounts switch parameter' {
            $Param = $Command.Parameters['CreateMissingAccounts']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $SourceName = [System.IO.Path]::GetRandomFileName()
            $SourceJournal = Join-Path $TestDrive "src-$SourceName.ledger"
            New-LedgerJournal -Path $SourceJournal -Name 'Källföretaget AB' -OrgNumber '556677-8899'
            Add-LedgerAccount -JournalPath $SourceJournal -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $SourceJournal -AccountNumber '3010' -AccountName 'Försäljning'
            New-LedgerFiscalYear -JournalPath $SourceJournal -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'
            Add-LedgerEntry -JournalPath $SourceJournal -FiscalYear $FiscalYear -Date '2024-03-15' -Description 'Försäljning' -Rows @(
                @{ Account = '1910'; Amount = 1000 }
                @{ Account = '3010'; Amount = -1000 }
            )
            Add-LedgerEntry -JournalPath $SourceJournal -FiscalYear $FiscalYear -Date '2024-04-01' -Description 'Försäljning 2' -Rows @(
                @{ Account = '1910'; Amount = 500.25 }
                @{ Account = '3010'; Amount = -500.25 }
            )

            $SieFile = Join-Path $TestDrive "transfer-$SourceName.se"
            Export-LedgerSie -JournalPath $SourceJournal -FiscalYear $FiscalYear -Path $SieFile

            $TargetJournal = Join-Path $TestDrive "dst-$SourceName.ledger"
            New-LedgerJournal -Path $TargetJournal -Name 'Mottagaren AB'
            Add-LedgerAccount -JournalPath $TargetJournal -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $TargetJournal -AccountNumber '3010' -AccountName 'Försäljning'
            New-LedgerFiscalYear -JournalPath $TargetJournal -StartDate '2024-01-01' -EndDate '2024-12-31'
        }

        It 'Should import all verifications from the SIE file' {
            Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile

            $entries = @(Get-LedgerEntry -JournalPath $TargetJournal -FiscalYear $FiscalYear)
            $entries.Count | Should -Be 2
        }

        It 'Should preserve description, date and amounts' {
            Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile

            $entries = @(Get-LedgerEntry -JournalPath $TargetJournal -FiscalYear $FiscalYear | Sort-Object VerificationNumber)
            $entries[0].Description | Should -Be 'Försäljning'
            $entries[0].Date | Should -Be '2024-03-15'
            ($entries[1].Rows | Where-Object Account -eq '1910').Amount | Should -Be 500.25
        }

        It 'Should return a summary object with ImportedEntries' {
            $result = Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile
            $result.ImportedEntries | Should -Be 2
        }

        It 'Should throw if SIE file is invalid' {
            $bad = Join-Path $TestDrive 'bad.se'
            [System.IO.File]::WriteAllText($bad, @"
#SIETYP 4
#KONTO 1910 "Kassa"
#VER A 1 20240315 "Bad"
{
   #TRANS 1910 {} 1000.00
   #TRANS 9999 {} -1000.00
}
"@, [System.Text.Encoding]::GetEncoding(437))

            { Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $bad } |
                Should -Throw '*invalid*'
        }

        It 'Should throw if target account is missing and -CreateMissingAccounts is not set' {
            $J3 = Join-Path $TestDrive 'empty.ledger'
            New-LedgerJournal -Path $J3 -Name 'Tom AB'
            New-LedgerFiscalYear -JournalPath $J3 -StartDate '2024-01-01' -EndDate '2024-12-31'

            { Import-LedgerSie -JournalPath $J3 -FiscalYear $FiscalYear -Path $SieFile } |
                Should -Throw '*CreateMissingAccounts*'
        }

        It 'Should create missing accounts when -CreateMissingAccounts is set' {
            $J3 = Join-Path $TestDrive 'empty2.ledger'
            New-LedgerJournal -Path $J3 -Name 'Tom AB'
            New-LedgerFiscalYear -JournalPath $J3 -StartDate '2024-01-01' -EndDate '2024-12-31'

            Import-LedgerSie -JournalPath $J3 -FiscalYear $FiscalYear -Path $SieFile -CreateMissingAccounts

            $accounts = @(Get-LedgerAccount -JournalPath $J3)
            $accounts.AccountNumber | Should -Contain '1910'
            $accounts.AccountNumber | Should -Contain '3010'
        }

        It 'Should throw if the target fiscal year is closed' {
            Close-LedgerFiscalYear -JournalPath $TargetJournal -FiscalYear $FiscalYear

            { Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile } |
                Should -Throw '*Closed*'
        }

        It 'Should throw if the target fiscal year does not exist' {
            { Import-LedgerSie -JournalPath $TargetJournal -FiscalYear '2099-01_2099-12' -Path $SieFile } |
                Should -Throw '*Fiscal year not found*'
        }

        It 'Should auto-detect fiscal year from #RAR 0 when FiscalYear not specified' {
            $J4 = Join-Path $TestDrive 'autofy.ledger'
            New-LedgerJournal -Path $J4 -Name 'AutoFY AB'
            Add-LedgerAccount -JournalPath $J4 -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $J4 -AccountNumber '3010' -AccountName 'Försäljning'
            New-LedgerFiscalYear -JournalPath $J4 -StartDate '2024-01-01' -EndDate '2024-12-31'

            $result = Import-LedgerSie -JournalPath $J4 -Path $SieFile
            $result.ImportedEntries | Should -Be 2
            $entries = @(Get-LedgerEntry -JournalPath $J4 -FiscalYear '2024-01_2024-12')
            $entries.Count | Should -Be 2
        }

        It 'Should create fiscal year automatically from #RAR 0 when it does not exist' {
            $J5 = Join-Path $TestDrive 'createfy.ledger'
            New-LedgerJournal -Path $J5 -Name 'CreateFY AB'
            Add-LedgerAccount -JournalPath $J5 -AccountNumber '1910' -AccountName 'Kassa'
            Add-LedgerAccount -JournalPath $J5 -AccountNumber '3010' -AccountName 'Försäljning'

            # No fiscal year exists — should be created from SIE #RAR 0
            $result = Import-LedgerSie -JournalPath $J5 -Path $SieFile
            $result.ImportedEntries | Should -Be 2

            $allYears = @(Get-LedgerFiscalYear -JournalPath $J5)
            $fy = $allYears | Where-Object Name -eq '2024-01_2024-12'
            $fy | Should -Not -BeNullOrEmpty
            $fy.StartDate | Should -Be '2024-01-01'
            $fy.EndDate | Should -Be '2024-12-31'
        }
    }
}
