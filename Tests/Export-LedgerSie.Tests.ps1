BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'Export-LedgerSie' {
    BeforeAll {
        $CommandName = 'Export-LedgerSie'
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

        It 'Should have an optional FiscalYear parameter of type String that binds from Name' {
            $Param = $Command.Parameters['FiscalYear']
            $Param | Should -Not -BeNullOrEmpty
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
            $Param.Attributes.ValueFromPipelineByPropertyName | Should -Contain $true
            $Param.Aliases | Should -Contain 'Name'
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
            $JournalName = [System.IO.Path]::GetRandomFileName()
            $JournalPath = Join-Path $TestDrive "$JournalName.ledger"
            New-LedgerJournal -Path $JournalPath -Name 'Testföretaget AB' -OrgNumber '556677-8899'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1910' -AccountName 'Kassa och bank'
            Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '3010' -AccountName 'Försäljning'
            New-LedgerFiscalYear -JournalPath $JournalPath -StartDate '2024-01-01' -EndDate '2024-12-31'
            $FiscalYear = '2024-01_2024-12'
            Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date '2024-03-15' -Description 'Försäljning kontant' -Rows @(
                @{ Account = '1910'; Amount = 1000.50 }
                @{ Account = '3010'; Amount = -1000.50 }
            )
            $SieFile = Join-Path $TestDrive "export-$JournalName.se"
        }

        It 'Should create the SIE file at the destination path' {
            Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile
            Test-Path $SieFile | Should -BeTrue
        }

        It 'Should write CP437-encoded text with Swedish characters intact' {
            Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile
            $text = [System.IO.File]::ReadAllText($SieFile, [System.Text.Encoding]::GetEncoding(437))
            $text | Should -Match 'Testföretaget AB'
            $text | Should -Match 'Försäljning kontant'
        }

        It 'Should write SIE 4 header records' {
            Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile
            $text = [System.IO.File]::ReadAllText($SieFile, [System.Text.Encoding]::GetEncoding(437))
            $text | Should -Match '#FLAGGA 0'
            $text | Should -Match '#PROGRAM PSLedger'
            $text | Should -Match '#FORMAT PC8'
            $text | Should -Match '#SIETYP 4'
            $text | Should -Match '#ORGNR 556677-8899'
            $text | Should -Match '#RAR 0 20240101 20241231'
        }

        It 'Should write all #KONTO records' {
            Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile
            $text = [System.IO.File]::ReadAllText($SieFile, [System.Text.Encoding]::GetEncoding(437))
            $text | Should -Match '#KONTO 1910 "Kassa och bank"'
            $text | Should -Match '#KONTO 3010'
        }

        It 'Should write #VER and #TRANS records with invariant decimal formatting' {
            Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile
            $text = [System.IO.File]::ReadAllText($SieFile, [System.Text.Encoding]::GetEncoding(437))
            $text | Should -Match '#VER A 1 20240315'
            $text | Should -Match '#TRANS 1910 \{\} 1000\.50'
            $text | Should -Match '#TRANS 3010 \{\} -1000\.50'
        }

        It 'Should produce a file that validates as a valid SIE' {
            Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile
            $result = Test-LedgerSie -Path $SieFile
            $result.IsValid | Should -BeTrue
        }

        It 'Should throw if the destination file exists and -Force is not used' {
            Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile
            { Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile } |
                Should -Throw '*already exists*'
        }

        It 'Should overwrite the destination file when -Force is used' {
            Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile
            { Export-LedgerSie -JournalPath $JournalPath -FiscalYear $FiscalYear -Path $SieFile -Force } |
                Should -Not -Throw
        }

        It 'Should throw if the fiscal year does not exist' {
            { Export-LedgerSie -JournalPath $JournalPath -FiscalYear '2099-01_2099-12' -Path $SieFile } |
                Should -Throw '*Fiscal year not found*'
        }

        It 'Should omit #ORGNR when the journal has no organisation number' {
            $J2 = Join-Path $TestDrive 'noorg.ledger'
            New-LedgerJournal -Path $J2 -Name 'Enskild Firma'
            New-LedgerFiscalYear -JournalPath $J2 -StartDate '2024-01-01' -EndDate '2024-12-31'
            $Out = Join-Path $TestDrive 'noorg.se'

            Export-LedgerSie -JournalPath $J2 -FiscalYear $FiscalYear -Path $Out
            $text = [System.IO.File]::ReadAllText($Out, [System.Text.Encoding]::GetEncoding(437))
            $text | Should -Not -Match '#ORGNR'
        }
    }
}
