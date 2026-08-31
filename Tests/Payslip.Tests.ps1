BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force

    function New-PayslipTestJournal {
        param([string]$Root)
        $path = Join-Path $Root "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $path -Name 'Lön AB' -CompanyType AB | Out-Null
        Import-LedgerChart -JournalPath $path -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $path -StartDate '2024-01-01' -EndDate '2024-12-31'
        Add-LedgerEmployee -JournalPath $path -EmployeeNumber '1' -Name 'Anna Andersson' -SalaryAccount '7210' -TaxRate 0.30
        return $path
    }
}

Describe 'New-LedgerPayslip' {
    BeforeAll {
        $Command = Get-Command -Name 'New-LedgerPayslip'
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }
        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }
        It 'Should have mandatory EmployeeNumber and GrossSalary parameters' {
            foreach ($p in 'EmployeeNumber', 'GrossSalary') {
                $Command.Parameters[$p].Attributes.Mandatory | Should -Contain $true
            }
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-PayslipTestJournal -Root $TestDrive
        }

        It 'Should create pay0001.txt for the first payslip' {
            New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-03-25'
            Test-Path (Join-Path $JournalPath 'payslips\pay0001.txt') | Should -BeTrue
        }

        It 'Should compute net pay and employer contribution from the default rates' {
            $ps = New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-03-25' -PassThru
            $ps.TaxAmount | Should -Be 9000
            $ps.NetPay | Should -Be 21000
            $ps.EmployerContribution | Should -Be 9426
            $ps.TotalEmployerCost | Should -Be 39426
            $ps.Status | Should -Be 'Draft'
        }

        It 'Should use an explicit tax amount' {
            $ps = New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 42000 -TaxAmount 12600 -PassThru
            $ps.TaxAmount | Should -Be 12600
            $ps.NetPay | Should -Be 29400
        }

        It 'Should use an explicit tax rate over the employee default' {
            $ps = New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -TaxRate 0.25 -PassThru
            $ps.TaxAmount | Should -Be 7500
        }

        It 'Should default the salary account to the employee account' {
            $ps = New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -PassThru
            $ps.SalaryAccount | Should -Be '7210'
        }

        It 'Should reject specifying both TaxAmount and TaxRate' {
            { New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -TaxAmount 9000 -TaxRate 0.30 } | Should -Throw '*not both*'
        }

        It 'Should reject an unknown employee' {
            { New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '999' -GrossSalary 30000 } | Should -Throw '*does not exist*'
        }

        It 'Should reject a non-positive gross salary' {
            { New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 0 } | Should -Throw '*greater than zero*'
        }

        It 'Should reject tax exceeding the gross salary' {
            { New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -TaxAmount 30001 } | Should -Throw '*exceed*'
        }

        It 'Should number payslips sequentially' {
            New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 | Out-Null
            $ps2 = New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -PassThru
            $ps2.PayslipNumber | Should -Be 2
        }
    }
}

Describe 'Invoke-LedgerPayrollPosting' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-PayslipTestJournal -Root $TestDrive
            New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-03-25' | Out-Null
        }

        It 'Should post a balanced salary verification' {
            Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber 1
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($b | Where-Object AccountNumber -eq '7210').Balance | Should -Be 30000
            ($b | Where-Object AccountNumber -eq '2710').Balance | Should -Be -9000
            ($b | Where-Object AccountNumber -eq '1930').Balance | Should -Be -21000
            ($b | Where-Object AccountNumber -eq '7510').Balance | Should -Be 9426
            ($b | Where-Object AccountNumber -eq '2730').Balance | Should -Be -9426
        }

        It 'Should mark the payslip Booked and record the verification' {
            $ps = Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber 1 -PassThru
            $ps.Status | Should -Be 'Booked'
            $ps.BookedVerification | Should -Not -BeNullOrEmpty
            $ps.BookedFiscalYear | Should -Be '2024-01_2024-12'
        }

        It 'Should refuse to post twice' {
            Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber 1
            { Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber 1 } | Should -Throw '*already posted*'
        }

        It 'Should throw for an unknown payslip' {
            { Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber 99 } | Should -Throw '*does not exist*'
        }
    }
}

Describe 'Get-LedgerPayslip' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-PayslipTestJournal -Root $TestDrive
            New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-03-25' | Out-Null
            New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 25000 -PayDate '2024-03-25' | Out-Null
            Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber 1
        }

        It 'Should list all payslips with the employee name' {
            $all = @(Get-LedgerPayslip -JournalPath $JournalPath)
            $all.Count | Should -Be 2
            $all[0].EmployeeName | Should -Be 'Anna Andersson'
        }

        It 'Should filter by status' {
            @(Get-LedgerPayslip -JournalPath $JournalPath -Status Draft).Count | Should -Be 1
            @(Get-LedgerPayslip -JournalPath $JournalPath -Status Booked).Count | Should -Be 1
        }

        It 'Should return a single payslip by number' {
            (Get-LedgerPayslip -JournalPath $JournalPath -PayslipNumber 2).GrossSalary | Should -Be 25000
        }
    }
}

Describe 'Add-LedgerPayrollTaxPayment' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-PayslipTestJournal -Root $TestDrive
            New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-03-25' | Out-Null
            Invoke-LedgerPayrollPosting -JournalPath $JournalPath -PayslipNumber 1
        }

        It 'Should settle the tax and contribution liabilities to zero' {
            $pay = Add-LedgerPayrollTaxPayment -JournalPath $JournalPath -Date '2024-04-12'
            $pay.TaxAmount | Should -Be 9000
            $pay.EmployerContributionAmount | Should -Be 9426
            $pay.Total | Should -Be 18426
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($b | Where-Object AccountNumber -eq '2710').Balance | Should -Be 0
            ($b | Where-Object AccountNumber -eq '2730').Balance | Should -Be 0
        }

        It 'Should credit the payment account with the total' {
            Add-LedgerPayrollTaxPayment -JournalPath $JournalPath -Date '2024-04-12' | Out-Null
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            # 21000 net pay + 18426 taxes = 39426 out of the bank
            ($b | Where-Object AccountNumber -eq '1930').Balance | Should -Be -39426
        }

        It 'Should pay explicit amounts when given' {
            $pay = Add-LedgerPayrollTaxPayment -JournalPath $JournalPath -Date '2024-04-12' -TaxAmount 5000 -EmployerContributionAmount 0
            $pay.Total | Should -Be 5000
            $b = Get-LedgerBalance -JournalPath $JournalPath -FiscalYear '2024-01_2024-12'
            ($b | Where-Object AccountNumber -eq '2710').Balance | Should -Be -4000
        }

        It 'Should throw when there is nothing to pay' {
            Add-LedgerPayrollTaxPayment -JournalPath $JournalPath -Date '2024-04-12' | Out-Null
            { Add-LedgerPayrollTaxPayment -JournalPath $JournalPath -Date '2024-05-12' } | Should -Throw '*Nothing to pay*'
        }
    }
}

Describe 'Export-LedgerPayslip' {
    Context 'Behavior' {
        BeforeEach {
            $JournalPath = New-PayslipTestJournal -Root $TestDrive
            New-LedgerPayslip -JournalPath $JournalPath -EmployeeNumber '1' -GrossSalary 30000 -PayDate '2024-03-25' | Out-Null
        }

        It 'Should write a PDF payslip' {
            $out = Join-Path $TestDrive 'lb1.pdf'
            Export-LedgerPayslip -JournalPath $JournalPath -PayslipNumber 1 -Path $out
            Test-Path $out | Should -BeTrue
            (Get-Item $out).Length | Should -BeGreaterThan 0
        }

        It 'Should write a text payslip containing the amounts' {
            $out = Join-Path $TestDrive 'lb1.txt'
            Export-LedgerPayslip -JournalPath $JournalPath -PayslipNumber 1 -Path $out -Format Text
            $content = Get-Content $out -Raw
            $content | Should -Match 'Anna Andersson'
            $content | Should -Match 'Nettolön'
        }

        It 'Should refuse to overwrite without -Force' {
            $out = Join-Path $TestDrive 'lb1.md'
            Export-LedgerPayslip -JournalPath $JournalPath -PayslipNumber 1 -Path $out -Format Markdown
            { Export-LedgerPayslip -JournalPath $JournalPath -PayslipNumber 1 -Path $out -Format Markdown } | Should -Throw '*already exists*'
        }

        It 'Should throw for an unknown payslip' {
            { Export-LedgerPayslip -JournalPath $JournalPath -PayslipNumber 99 -Path (Join-Path $TestDrive 'x.txt') -Format Text } | Should -Throw '*does not exist*'
        }
    }
}
