BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force

    function New-DeclarationTestJournal {
        param([string]$Root)
        $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $path -Name 'Lön AB' -CompanyType AB | Out-Null
        Set-LedgerJournal -JournalPath $path -OrgNumber '556677-8899' -Metadata @{
            ContactName  = 'Anna Andersson'
            ContactPhone = '08-123456'
            ContactEmail = 'anna@lon.se'
        } | Out-Null
        Import-LedgerChart -JournalPath $path -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $path -StartDate '2024-01-01' -EndDate '2024-12-31'
        Add-LedgerEmployee -JournalPath $path -EmployeeNumber '1' -Name 'Anna Andersson' -PersonalNumber '19850101-1234' -SalaryAccount '7210' -TaxRate 0.30
        Add-LedgerEmployee -JournalPath $path -EmployeeNumber '2' -Name 'Bengt Bengtsson' -PersonalNumber '19700202-5678' -SalaryAccount '7210' -TaxRate 0.30
        return $path
    }

    function Add-BookedPayslip {
        param($JournalPath, $EmployeeNumber, $GrossSalary, $PayDate)
        $ps = New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber $EmployeeNumber -GrossSalary $GrossSalary -PayDate $PayDate -PassThru
        Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber $ps.PayslipNumber -FiscalYear '2024-01_2024-12' | Out-Null
    }
}

Describe 'Export-LedgerEmployerDeclaration' {
    BeforeAll {
        $Command = Get-Command -Name 'Export-LedgerEmployerDeclaration'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }
        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
        It 'Should have mandatory Period and Path parameters' {
            foreach ($p in 'Period', 'Path') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-DeclarationTestJournal -Root $TestDrive
            Add-BookedPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-03-25'
            Add-BookedPayslip -JournalPath $JournalPath -EmployeeNumber '2' -GrossSalary 40000 -PayDate '2024-03-25'
            $OutPath = Join-Path $TestDrive "agi-$([System.IO.Path]::GetRandomFileName()).xml"
        }

        It 'Should write an XML file' {
            Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath | Out-Null
            Test-Path $OutPath | Should -BeTrue
        }

        It 'Should return a summary with the period totals' {
            $result = Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath
            $result.Period | Should -Be '202403'
            $result.EmployeeCount | Should -Be 2
            $result.TotalGrossSalary | Should -Be 70000
            $result.TotalTaxWithheld | Should -Be 21000
            $result.TotalEmployerContribution | Should -Be 21994
        }

        It 'Should produce well-formed XML with the Skatteverket root' {
            Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath | Out-Null
            [xml]$doc = Get-Content $OutPath -Raw
            $doc.Skatteverket.omrade | Should -Be 'Arbetsgivardeklaration'
        }

        It 'Should prefix the org number to the 12-digit IDENTITET form' {
            $result = Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath
            $result.OrgNumber | Should -Be '165566778899'
        }

        It 'Should include the HU field codes for the totals' {
            Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath | Out-Null
            $xml = Get-Content $OutPath -Raw
            $xml | Should -Match 'faltkod="497">21000<'
            $xml | Should -Match 'faltkod="487">21994<'
        }

        It 'Should emit one IU per employee with the payee id and amounts' {
            Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath | Out-Null
            [xml]$doc = Get-Content $OutPath -Raw
            $ius = @($doc.Skatteverket.Blankett | Where-Object { $_.Blankettinnehall.IU })
            $ius.Count | Should -Be 2
            $xml = Get-Content $OutPath -Raw
            $xml | Should -Match 'faltkod="215">198501011234<'
            $xml | Should -Match 'faltkod="215">197002025678<'
            $xml | Should -Match 'faltkod="011">30000<'
            $xml | Should -Match 'faltkod="001">9000<'
        }

        It 'Should aggregate multiple payslips for the same employee' {
            Add-BookedPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 5000 -PayDate '2024-03-28'
            $result = Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath
            $result.EmployeeCount | Should -Be 2
            $result.TotalGrossSalary | Should -Be 75000
        }

        It 'Should only include payslips whose pay date is in the period' {
            Add-BookedPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 33000 -PayDate '2024-04-25'
            $result = Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202404' -Path $OutPath
            $result.EmployeeCount | Should -Be 1
            $result.TotalGrossSalary | Should -Be 33000
        }

        It 'Should ignore draft (unposted) payslips' {
            New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '2' -GrossSalary 99000 -PayDate '2024-03-26' | Out-Null
            $result = Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath
            $result.TotalGrossSalary | Should -Be 70000
        }

        It 'Should throw when there are no booked payslips in the period' {
            { Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202401' -Path $OutPath } |
                Should -Throw '*No booked payslips*'
        }

        It 'Should throw when an employee has no personal number' {
            Add-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber '3' -Name 'Cecilia Carlsson' -SalaryAccount '7210' -TaxRate 0.30
            Add-BookedPayslip -JournalPath $JournalPath -EmployeeNumber '3' -GrossSalary 20000 -PayDate '2024-03-25'
            { Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath } |
                Should -Throw '*no personal number*'
        }

        It 'Should throw when the journal has no OrgNumber' {
            $bare = Join-Path $TestDrive 'bare.ledger'
            New-LedgerJournal -Path $bare -Name 'Bare AB' -CompanyType AB | Out-Null
            Import-LedgerChart -JournalPath $bare -Template 'BAS-Smaforetag'
            New-LedgerFiscalYear -JournalPath $bare -StartDate '2024-01-01' -EndDate '2024-12-31'
            Add-LedgerEmployee -JournalPath $bare -EmployeeNumber '1' -Name 'X' -PersonalNumber '19850101-1234'
            $ps = New-LedgerPayslip -JournalPath $bare -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-03-25' -PassThru
            Invoke-LedgerPayrollPosting -JournalPath $bare -PayslipNumber $ps.PayslipNumber -FiscalYear '2024-01_2024-12' | Out-Null
            { Export-LedgerEmployerDeclaration -JournalPath $bare -Period '202403' -Path $OutPath } |
                Should -Throw '*no OrgNumber*'
        }

        It 'Should refuse to overwrite an existing file without -Force' {
            Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath | Out-Null
            { Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath } |
                Should -Throw '*already exists*'
        }

        It 'Should overwrite an existing file with -Force' {
            Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath | Out-Null
            { Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath -Force } |
                Should -Not -Throw
        }

        It 'Should override contact details from parameters' {
            Export-LedgerEmployerDeclaration -JournalPath $JournalPath -Period '202403' -Path $OutPath -ContactName 'Erik Ek' -ContactPhone '070-000' -ContactEmail 'erik@lon.se' | Out-Null
            $xml = Get-Content $OutPath -Raw
            $xml | Should -Match '<gem:Namn>Erik Ek</gem:Namn>'
        }
    }
}
