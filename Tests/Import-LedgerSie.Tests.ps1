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

        Context 'Opening balances (#IB)' {
            BeforeEach {
                $IbName = [System.IO.Path]::GetRandomFileName()
                $IbSieFile = Join-Path $TestDrive "ib-$IbName.se"
                [System.IO.File]::WriteAllText($IbSieFile, @"
#SIETYP 4
#KONTO 1910 "Kassa"
#KONTO 2010 "Eget kapital"
#KONTO 3010 "Försäljning"
#RAR 0 20240101 20241231
#RAR -1 20230101 20231231
#IB 0 1910 1000.00
#IB 0 2010 -1000.00
#IB -1 1910 9999.00
#VER A 1 20240315 "Försäljning"
{
   #TRANS 1910 {} 500.00
   #TRANS 3010 {} -500.00
}
"@, [System.Text.Encoding]::GetEncoding(437))

                $IbJournal = Join-Path $TestDrive "ibdst-$IbName.ledger"
                New-LedgerJournal -Path $IbJournal -Name 'IB Mottagare AB'
                New-LedgerFiscalYear -JournalPath $IbJournal -StartDate '2024-01-01' -EndDate '2024-12-31'
            }

            It 'Should create an opening balance verification dated on the year start' {
                Import-LedgerSie -JournalPath $IbJournal -FiscalYear $FiscalYear -Path $IbSieFile -CreateMissingAccounts

                $entries = @(Get-LedgerEntry -JournalPath $IbJournal -FiscalYear $FiscalYear | Sort-Object VerificationNumber)
                $entries[0].Description | Should -Be 'Ingående balans'
                $entries[0].Date | Should -Be '2024-01-01'
            }

            It 'Should carry the opening balance into Get-LedgerBalance' {
                Import-LedgerSie -JournalPath $IbJournal -FiscalYear $FiscalYear -Path $IbSieFile -CreateMissingAccounts

                $balance = Get-LedgerBalance -JournalPath $IbJournal -FiscalYear $FiscalYear
                # 1910: 1000 opening + 500 from the verification = 1500
                ($balance | Where-Object AccountNumber -eq '1910').Balance | Should -Be 1500
                ($balance | Where-Object AccountNumber -eq '2010').Balance | Should -Be -1000
            }

            It 'Should report ImportedOpeningBalance as true' {
                $result = Import-LedgerSie -JournalPath $IbJournal -FiscalYear $FiscalYear -Path $IbSieFile -CreateMissingAccounts
                $result.ImportedOpeningBalance | Should -BeTrue
                $result.ImportedEntries | Should -Be 1
            }

            It 'Should ignore #IB records for other years (year index != 0)' {
                Import-LedgerSie -JournalPath $IbJournal -FiscalYear $FiscalYear -Path $IbSieFile -CreateMissingAccounts

                $opening = @(Get-LedgerEntry -JournalPath $IbJournal -FiscalYear $FiscalYear | Where-Object Description -eq 'Ingående balans')
                $opening.Rows.Account | Should -Not -Contain '9999'
                # Only the two year-0 IB rows should be present
                @($opening.Rows).Count | Should -Be 2
            }

            It 'Should report ImportedOpeningBalance as false when the SIE file has no #IB' {
                $result = Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile
                $result.ImportedOpeningBalance | Should -BeFalse
            }
        }

        Context 'Duplicate import protection' {
            It 'Should throw when importing into a fiscal year that already has verifications' {
                Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile

                { Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile } |
                    Should -Throw '*already contains verifications*'
            }

            It 'Should not add any entries when a duplicate import is rejected' {
                Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile
                try { Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile } catch { }

                $entries = @(Get-LedgerEntry -JournalPath $TargetJournal -FiscalYear $FiscalYear)
                $entries.Count | Should -Be 2
            }

            It 'Should allow re-import into a non-empty fiscal year when -Force is set' {
                Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile
                Import-LedgerSie -JournalPath $TargetJournal -FiscalYear $FiscalYear -Path $SieFile -Force

                $entries = @(Get-LedgerEntry -JournalPath $TargetJournal -FiscalYear $FiscalYear)
                $entries.Count | Should -Be 4
            }

            It 'Should have a Force switch parameter' {
                $Command.Parameters['Force'].ParameterType.Name | Should -Be 'SwitchParameter'
            }
        }

        Context 'Fiscal year gap protection' {
            BeforeEach {
                $GapName = [System.IO.Path]::GetRandomFileName()
                $GapJournal = Join-Path $TestDrive "gap-$GapName.ledger"
                New-LedgerJournal -Path $GapJournal -Name 'Gap AB'
                Add-LedgerAccount -JournalPath $GapJournal -AccountNumber '1910' -AccountName 'Kassa'
                Add-LedgerAccount -JournalPath $GapJournal -AccountNumber '3010' -AccountName 'Försäljning'
                # Existing fiscal year 2022 (leaves 2023 as a potential gap before 2024)
                New-LedgerFiscalYear -JournalPath $GapJournal -StartDate '2022-01-01' -EndDate '2022-12-31'

                $Sie2024 = Join-Path $TestDrive "gap2024-$GapName.se"
                [System.IO.File]::WriteAllText($Sie2024, @"
#SIETYP 4
#KONTO 1910 "Kassa"
#KONTO 3010 "Försäljning"
#RAR 0 20240101 20241231
#VER A 1 20240315 "Test"
{
   #TRANS 1910 {} 500.00
   #TRANS 3010 {} -500.00
}
"@, [System.Text.Encoding]::GetEncoding(437))

                $Sie2023 = Join-Path $TestDrive "gap2023-$GapName.se"
                [System.IO.File]::WriteAllText($Sie2023, @"
#SIETYP 4
#KONTO 1910 "Kassa"
#KONTO 3010 "Försäljning"
#RAR 0 20230101 20231231
#VER A 1 20230315 "Test"
{
   #TRANS 1910 {} 500.00
   #TRANS 3010 {} -500.00
}
"@, [System.Text.Encoding]::GetEncoding(437))
            }

            It 'Should throw when auto-creating a non-contiguous fiscal year (gap)' {
                { Import-LedgerSie -JournalPath $GapJournal -Path $Sie2024 } | Should -Throw '*gap*'
            }

            It 'Should not create the fiscal year when a gap would be created' {
                try { Import-LedgerSie -JournalPath $GapJournal -Path $Sie2024 } catch { }
                $years = @(Get-LedgerFiscalYear -JournalPath $GapJournal)
                $years.Name | Should -Not -Contain '2024-01_2024-12'
            }

            It 'Should allow a contiguous fiscal year import' {
                Import-LedgerSie -JournalPath $GapJournal -Path $Sie2023
                $years = @(Get-LedgerFiscalYear -JournalPath $GapJournal)
                $years.Name | Should -Contain '2023-01_2023-12'
            }

            It 'Should allow a gap-creating import when -Force is set' {
                Import-LedgerSie -JournalPath $GapJournal -Path $Sie2024 -Force
                $years = @(Get-LedgerFiscalYear -JournalPath $GapJournal)
                $years.Name | Should -Contain '2024-01_2024-12'
            }

            It 'Should allow filling an existing gap between two fiscal years' {
                # Force-create 2024 (gap), then import 2023 to fill the gap exactly
                Import-LedgerSie -JournalPath $GapJournal -Path $Sie2024 -Force
                Import-LedgerSie -JournalPath $GapJournal -Path $Sie2023
                $years = @(Get-LedgerFiscalYear -JournalPath $GapJournal)
                $years.Name | Should -Contain '2023-01_2023-12'
            }
        }

        Context 'Opening balance rounding' {
            BeforeEach {
                $RoundName = [System.IO.Path]::GetRandomFileName()
                $RoundJournal = Join-Path $TestDrive "round-$RoundName.ledger"
                New-LedgerJournal -Path $RoundJournal -Name 'Round AB'
                Add-LedgerAccount -JournalPath $RoundJournal -AccountNumber '1910' -AccountName 'Kassa'
                Add-LedgerAccount -JournalPath $RoundJournal -AccountNumber '2010' -AccountName 'Eget kapital'
                Add-LedgerAccount -JournalPath $RoundJournal -AccountNumber '3010' -AccountName 'Försäljning'
                New-LedgerFiscalYear -JournalPath $RoundJournal -StartDate '2024-01-01' -EndDate '2024-12-31'

                # #IB sums to 0.14 (öresdifferens)
                $RoundSie = Join-Path $TestDrive "round-$RoundName.se"
                [System.IO.File]::WriteAllText($RoundSie, @"
#SIETYP 4
#KONTO 1910 "Kassa"
#KONTO 2010 "Eget kapital"
#KONTO 3010 "Försäljning"
#RAR 0 20240101 20241231
#IB 0 1910 1000.14
#IB 0 2010 -1000.00
#VER A 1 20240315 "Försäljning"
{
   #TRANS 1910 {} 500.00
   #TRANS 3010 {} -500.00
}
"@, [System.Text.Encoding]::GetEncoding(437))
            }

            It 'Should post a small öresdifferens to the rounding account' {
                Import-LedgerSie -JournalPath $RoundJournal -FiscalYear $FiscalYear -Path $RoundSie -CreateMissingAccounts

                $opening = Get-LedgerEntry -JournalPath $RoundJournal -FiscalYear $FiscalYear | Where-Object Description -eq 'Ingående balans'
                ($opening.Rows | Where-Object Account -eq '3740').Amount | Should -Be -0.14
            }

            It 'Should report the rounding adjustment in the result' {
                $result = Import-LedgerSie -JournalPath $RoundJournal -FiscalYear $FiscalYear -Path $RoundSie -CreateMissingAccounts
                $result.OpeningBalanceRounding | Should -Be -0.14
            }

            It 'Should produce a balanced opening balance entry' {
                Import-LedgerSie -JournalPath $RoundJournal -FiscalYear $FiscalYear -Path $RoundSie -CreateMissingAccounts
                $opening = Get-LedgerEntry -JournalPath $RoundJournal -FiscalYear $FiscalYear | Where-Object Description -eq 'Ingående balans'
                $sum = [decimal]0
                $opening.Rows | ForEach-Object { $sum += [decimal]$_.Amount }
                $sum | Should -Be 0
            }

            It 'Should create the rounding account with the BAS name when -CreateMissingAccounts is set' {
                Import-LedgerSie -JournalPath $RoundJournal -FiscalYear $FiscalYear -Path $RoundSie -CreateMissingAccounts
                $accounts = @(Get-LedgerAccount -JournalPath $RoundJournal)
                ($accounts | Where-Object AccountNumber -eq '3740').AccountName | Should -Be 'Öres- och kronutjämning'
            }

            It 'Should throw when the rounding account is missing and -CreateMissingAccounts is not set' {
                { Import-LedgerSie -JournalPath $RoundJournal -FiscalYear $FiscalYear -Path $RoundSie } |
                    Should -Throw '*rounding account*'
            }

            It 'Should use a custom -RoundingAccount' {
                Add-LedgerAccount -JournalPath $RoundJournal -AccountNumber '3741' -AccountName 'Avrundning'
                Import-LedgerSie -JournalPath $RoundJournal -FiscalYear $FiscalYear -Path $RoundSie -RoundingAccount '3741'

                $opening = Get-LedgerEntry -JournalPath $RoundJournal -FiscalYear $FiscalYear | Where-Object Description -eq 'Ingående balans'
                ($opening.Rows | Where-Object Account -eq '3741').Amount | Should -Be -0.14
            }

            It 'Should abort when the difference exceeds -RoundingTolerance' {
                { Import-LedgerSie -JournalPath $RoundJournal -FiscalYear $FiscalYear -Path $RoundSie -CreateMissingAccounts -RoundingTolerance 0.05 } |
                    Should -Throw '*do not balance*'
            }
        }
    }
}
