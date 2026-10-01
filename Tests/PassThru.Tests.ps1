BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')
}

Describe 'CRUD write command PassThru behavior' {
    $CommandNames = @(
            'Add-LedgerAccount', 'Add-LedgerCustomer', 'Set-LedgerCustomer',
            'Add-LedgerSupplier', 'Set-LedgerSupplier',
            'Add-LedgerEmployee', 'Set-LedgerEmployee',
            'Add-LedgerProject', 'Set-LedgerProject',
            'Add-LedgerTimeResource', 'Set-LedgerTimeResource',
            'Add-LedgerDimension', 'Add-LedgerObject', 'Add-LedgerReversal',
            'Add-LedgerDocument', 'Add-LedgerAttachment',
            'New-LedgerJournal', 'New-LedgerFiscalYear', 'Set-LedgerJournal',
            'New-LedgerRecurringEntry', 'Set-LedgerHolding',
            'Set-LedgerReportInput', 'Set-LedgerTimeEntry'
        )

        $Cases = @(
            @{
                Name = 'Add-LedgerAccount'; Key = 'AccountNumber'; Expected = '1999'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive -NoChart
                    Add-LedgerAccount -JournalPath $jp -AccountNumber '1999' -AccountName 'Observationskonto' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerCustomer'; Key = 'CustomerNumber'; Expected = '20'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Add-LedgerCustomer -JournalPath $jp -CustomerNumber '20' -Name 'Volvo AB' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Set-LedgerCustomer'; Key = 'Name'; Expected = 'Volvo Group AB'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive -Customers @(@{ Number = '10'; Name = 'Volvo AB' })
                    Set-LedgerCustomer -JournalPath $jp -CustomerNumber '10' -Name 'Volvo Group AB' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerSupplier'; Key = 'SupplierNumber'; Expected = '200'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Add-LedgerSupplier -JournalPath $jp -SupplierNumber '200' -Name 'Kontorsbolaget AB' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Set-LedgerSupplier'; Key = 'Name'; Expected = 'Kontorsbolaget Sverige AB'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive -Suppliers @(@{ Number = '100'; Name = 'Kontorsbolaget AB' })
                    Set-LedgerSupplier -JournalPath $jp -SupplierNumber '100' -Name 'Kontorsbolaget Sverige AB' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerEmployee'; Key = 'EmployeeNumber'; Expected = '1'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Add-LedgerEmployee -JournalPath $jp -EmployeeNumber '1' -Name 'Anna Andersson' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Set-LedgerEmployee'; Key = 'Name'; Expected = 'Anna Andersson-Ek'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Add-LedgerEmployee -JournalPath $jp -EmployeeNumber '1' -Name 'Anna Andersson'
                    Set-LedgerEmployee -JournalPath $jp -EmployeeNumber '1' -Name 'Anna Andersson-Ek' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerProject'; Key = 'ProjectNumber'; Expected = 'P1'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive -Customers @(@{ Number = '10'; Name = 'Volvo AB' })
                    Add-LedgerProject -JournalPath $jp -ProjectNumber 'P1' -Name 'Kundportal' -CustomerNumber '10' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Set-LedgerProject'; Key = 'Status'; Expected = 'Closed'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive -Customers @(@{ Number = '10'; Name = 'Volvo AB' })
                    Add-LedgerProject -JournalPath $jp -ProjectNumber 'P1' -Name 'Kundportal' -CustomerNumber '10'
                    Set-LedgerProject -JournalPath $jp -ProjectNumber 'P1' -Status Closed -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerTimeResource'; Key = 'ResourceId'; Expected = 'AA'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Add-LedgerTimeResource -JournalPath $jp -ResourceId 'AA' -Name 'Anna Andersson' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Set-LedgerTimeResource'; Key = 'CostRate'; Expected = 750
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Add-LedgerTimeResource -JournalPath $jp -ResourceId 'AA' -Name 'Anna Andersson'
                    Set-LedgerTimeResource -JournalPath $jp -ResourceId 'AA' -CostRate 750 -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerDimension'; Key = 'DimensionNumber'; Expected = 1
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Add-LedgerDimension -JournalPath $jp -DimensionNumber 1 -Name 'Kostnadsställe' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerObject'; Key = 'ObjectNumber'; Expected = 'STHLM'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Add-LedgerDimension -JournalPath $jp -DimensionNumber 1 -Name 'Kostnadsställe'
                    Add-LedgerObject -JournalPath $jp -DimensionNumber 1 -ObjectNumber 'STHLM' -Name 'Stockholm' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerReversal'; Key = 'VerificationNumber'; Expected = 2
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    $rows = @(
                        @{ Account = '1930'; Amount = 1000 }
                        @{ Account = '3010'; Amount = -800 }
                        @{ Account = '2610'; Amount = -200 }
                    )
                    Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-03-15' -Description 'Försäljning' -Rows $rows
                    Add-LedgerReversal -JournalPath $jp -FiscalYear '2024-01_2024-12' -VerificationNumber 1 -Date '2024-03-16' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerDocument'; Key = 'FileName'; Expected = 'kontoutdrag.pdf'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    $file = Join-Path $TestDrive 'kontoutdrag.pdf'
                    Set-Content -Path $file -Value 'pdf' -Encoding UTF8
                    Add-LedgerDocument -JournalPath $jp -FiscalYear '2024-01_2024-12' -Path $file -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Add-LedgerAttachment'; Key = 'FileName'; Expected = 'kvitto.pdf'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    $rows = @(
                        @{ Account = '1930'; Amount = 1000 }
                        @{ Account = '3010'; Amount = -800 }
                        @{ Account = '2610'; Amount = -200 }
                    )
                    Add-LedgerEntry -JournalPath $jp -FiscalYear '2024-01_2024-12' -Date '2024-03-15' -Description 'Försäljning' -Rows $rows
                    $file = Join-Path $TestDrive 'kvitto.pdf'
                    Set-Content -Path $file -Value 'pdf' -Encoding UTF8
                    Add-LedgerAttachment -JournalPath $jp -FiscalYear '2024-01_2024-12' -VerificationNumber 1 -Path $file -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'New-LedgerJournal'; Key = 'Name'; Expected = 'Ny Firma AB'
                Invoke = { param([bool]$WithPassThru)
                    $jp = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).ledger"
                    New-LedgerJournal -Path $jp -Name 'Ny Firma AB' -OrgNumber '556000-0000' -CompanyType AB -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'New-LedgerFiscalYear'; Key = 'Name'; Expected = '2025-01_2025-12'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    New-LedgerFiscalYear -JournalPath $jp -StartDate '2025-01-01' -EndDate '2025-12-31' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Set-LedgerJournal'; Key = 'Name'; Expected = 'Uppdaterad Firma AB'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Set-LedgerJournal -JournalPath $jp -Name 'Uppdaterad Firma AB' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'New-LedgerRecurringEntry'; Key = 'Name'; Expected = 'Hyra'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    $rows = @(
                        @{ Account = '5010'; Amount = 1000 }
                        @{ Account = '2440'; Amount = -1000 }
                    )
                    New-LedgerRecurringEntry -JournalPath $jp -Name 'Hyra' -Description 'Hyra kontor' -Schedule monthly -DayOfMonth 1 -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows $rows -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Set-LedgerHolding'; Key = 'Name'; Expected = 'Investor B'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Add-LedgerAccount -JournalPath $jp -AccountNumber '1350' -AccountName 'Andelar och värdepapper'
                    Set-LedgerHolding -JournalPath $jp -FiscalYear '2024-01_2024-12' -Account 1350 -Name 'Investor B' -Quantity 10 -Price 250 -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Set-LedgerReportInput'; Key = 'SigningPlace'; Expected = 'Gävle'
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive
                    Set-LedgerReportInput -JournalPath $jp -FiscalYear '2024-01_2024-12' -SigningPlace 'Gävle' -PassThru:$WithPassThru
                }
            }
            @{
                Name = 'Set-LedgerTimeEntry'; Key = 'Hours'; Expected = 6
                Invoke = { param([bool]$WithPassThru)
                    $jp = New-TestLedger -Root $TestDrive -Customers @(@{ Number = '10'; Name = 'Volvo AB' })
                    Add-LedgerTimeResource -JournalPath $jp -ResourceId 'AA' -Name 'Anna Andersson'
                    Add-LedgerProject -JournalPath $jp -ProjectNumber 'P1' -Name 'Kundportal' -CustomerNumber '10' -HourlyRate 1000
                    $entry = Add-LedgerTimeEntry -JournalPath $jp -Date '2024-05-01' -ProjectNumber 'P1' -Hours 4 -Text 'Utveckling' -PassThru
                    Set-LedgerTimeEntry -JournalPath $jp -EntryId $entry.EntryId -Hours 6 -PassThru:$WithPassThru
                }
            }
        )

    Context 'Function metadata' {
        It '<_> has a PassThru SwitchParameter' -ForEach $CommandNames {
            $command = Get-Command -Name $_
            $command.Parameters['PassThru'].ParameterType | Should -Be ([switch])
        }
    }

    Context 'Behavior' {
        It '<Name> produces no output by default' -ForEach $Cases {
            $result = @(& $Invoke $false)
            $result | Should -BeNullOrEmpty
        }

        It '<Name> returns the created/updated object with -PassThru' -ForEach $Cases {
            $result = @(& $Invoke $true)
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties[$Key].Value | Should -Be $Expected
        }
    }
}
