BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    Import-Module TDDSeams -Force
}

Describe 'Get-LedgerAccountingPrinciples' {
    Context 'Function metadata' {
        BeforeAll {
            $Command = Get-Command Get-LedgerAccountingPrinciples
        }

        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an AsLines switch parameter' {
            $Command.Parameters['AsLines'].ParameterType | Should -Be ([switch])
        }
    }

    Context 'Behavior' {
        It 'Should return the K2 principles as a single string by default' {
            $result = Get-LedgerAccountingPrinciples
            $result | Should -BeOfType [string]
            $result | Should -Match 'K2'
            $result | Should -Match 'BFNAR 2016:10'
            $result | Should -Match 'årsredovisningslagen'
        }

        It 'Should contain a newline between paragraphs in the single-string form' {
            $result = Get-LedgerAccountingPrinciples
            $result | Should -Match "`n"
        }

        It 'Should return an array of paragraphs with -AsLines' {
            $result = @(Get-LedgerAccountingPrinciples -AsLines)
            $result.Count | Should -BeGreaterThan 1
            $result[0] | Should -Match 'årsredovisningslagen'
        }

        It 'Should not contain empty paragraphs with -AsLines' {
            $result = @(Get-LedgerAccountingPrinciples -AsLines)
            ($result | Where-Object { $_.Trim() -eq '' }).Count | Should -Be 0
        }

        It 'Should preserve Swedish characters (UTF-8)' {
            $result = Get-LedgerAccountingPrinciples
            $result | Should -Match 'Fordringar'
            $result | Should -Match 'å|ä|ö'
        }
    }
}
