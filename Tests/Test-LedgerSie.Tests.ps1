BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Test-LedgerSie' {
    BeforeAll {
        $CommandName = 'Test-LedgerSie'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have a mandatory Path parameter of type String' {
            $Param = $Command.Parameters['Path']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $SieFile = Join-Path $TestDrive "in-$([System.IO.Path]::GetRandomFileName()).se"
        }

        It 'Should report a valid file with no errors' {
            $text = @"
#FLAGGA 0
#PROGRAM "PSLedger" "0.2.0"
#FORMAT PC8
#SIETYP 4
#FNAMN "Test AB"
#KONTO 1910 "Kassa"
#KONTO 3010 "Försäljning"
#VER A 1 20240315 "Test"
{
   #TRANS 1910 {} 1000.00
   #TRANS 3010 {} -1000.00
}
"@
            [System.IO.File]::WriteAllText($SieFile, $text, [System.Text.Encoding]::GetEncoding(437))

            $result = Test-LedgerSie -Path $SieFile
            $result.IsValid | Should -BeTrue
            $result.Errors.Count | Should -Be 0
            $result.Accounts | Should -Be 2
            $result.Verifications | Should -Be 1
            $result.Transactions | Should -Be 2
        }

        It 'Should detect unbalanced verification' {
            $text = @"
#SIETYP 4
#KONTO 1910 "Kassa"
#KONTO 3010 "Försäljning"
#VER A 1 20240315 "Bad"
{
   #TRANS 1910 {} 1000.00
   #TRANS 3010 {} -500.00
}
"@
            [System.IO.File]::WriteAllText($SieFile, $text, [System.Text.Encoding]::GetEncoding(437))

            $result = Test-LedgerSie -Path $SieFile
            $result.IsValid | Should -BeFalse
            ($result.Errors -join ' ') | Should -Match 'balance'
        }

        It 'Should detect unknown account in #TRANS' {
            $text = @"
#SIETYP 4
#KONTO 1910 "Kassa"
#VER A 1 20240315 "Bad"
{
   #TRANS 1910 {} 1000.00
   #TRANS 9999 {} -1000.00
}
"@
            [System.IO.File]::WriteAllText($SieFile, $text, [System.Text.Encoding]::GetEncoding(437))

            $result = Test-LedgerSie -Path $SieFile
            $result.IsValid | Should -BeFalse
            ($result.Errors -join ' ') | Should -Match '9999'
        }

        It 'Should detect duplicate verification numbers' {
            $text = @"
#SIETYP 4
#KONTO 1910 "Kassa"
#KONTO 3010 "Försäljning"
#VER A 1 20240315 "First"
{
   #TRANS 1910 {} 100.00
   #TRANS 3010 {} -100.00
}
#VER A 1 20240316 "Dup"
{
   #TRANS 1910 {} 200.00
   #TRANS 3010 {} -200.00
}
"@
            [System.IO.File]::WriteAllText($SieFile, $text, [System.Text.Encoding]::GetEncoding(437))

            $result = Test-LedgerSie -Path $SieFile
            $result.IsValid | Should -BeFalse
            ($result.Errors -join ' ') | Should -Match 'Duplicate'
        }

        It 'Should warn if #SIETYP is missing' {
            $text = @"
#KONTO 1910 "Kassa"
"@
            [System.IO.File]::WriteAllText($SieFile, $text, [System.Text.Encoding]::GetEncoding(437))

            $result = Test-LedgerSie -Path $SieFile
            ($result.Warnings -join ' ') | Should -Match 'SIETYP'
        }

        It 'Should accept comma as decimal separator' {
            $text = @"
#SIETYP 4
#KONTO 1910 "Kassa"
#KONTO 3010 "Försäljning"
#VER A 1 20240315 "Comma decimal"
{
   #TRANS 1910 {} 1000,50
   #TRANS 3010 {} -1000,50
}
"@
            [System.IO.File]::WriteAllText($SieFile, $text, [System.Text.Encoding]::GetEncoding(437))

            $result = Test-LedgerSie -Path $SieFile
            $result.IsValid | Should -BeTrue
        }

        It 'Should throw if file does not exist' {
            { Test-LedgerSie -Path (Join-Path $TestDrive 'missing.se') } | Should -Throw
        }
    }
}
