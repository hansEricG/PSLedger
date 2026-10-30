# Commands that change a fiscal year's verifications, attachments, documents or
# opening balance must refuse a closed year. Annual report input and new year
# documents (e.g. the signed annual report) are still allowed after closing.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1') -Force
}

Describe 'Closed fiscal year' {
    BeforeEach {
        $J = Join-Path $TestDrive "$([System.IO.Path]::GetRandomFileName()).ledger"
        New-LedgerJournal -Path $J -Name 'Stängda Året AB'
        Add-LedgerAccount -JournalPath $J -AccountNumber '1930' -AccountName 'Företagskonto'
        Add-LedgerAccount -JournalPath $J -AccountNumber '6110' -AccountName 'Kontorsmateriel'
        New-LedgerFiscalYear -JournalPath $J -StartDate '2024-01-01' -EndDate '2024-12-31'
        New-LedgerFiscalYear -JournalPath $J -StartDate '2025-01-01' -EndDate '2025-12-31'
        $Y = '2024-01_2024-12'
        $Next = '2025-01_2025-12'

        $receipt = Join-Path $TestDrive 'kvitto.pdf'
        Set-Content -LiteralPath $receipt -Value 'kvitto'
        $agreement = Join-Path $TestDrive 'avtal.pdf'
        Set-Content -LiteralPath $agreement -Value 'avtal'

        Add-LedgerEntry -JournalPath $J -FiscalYear $Y -Date '2024-03-01' -Description 'Pennor' -Rows @(
            @{ Account = '6110'; Amount = 100 }
            @{ Account = '1930'; Amount = -100 }
        ) -Attachment $receipt
        Add-LedgerDocument -JournalPath $J -FiscalYear $Y -Path $agreement
        Close-LedgerFiscalYear -JournalPath $J -FiscalYear $Y -SkipResultEntry | Out-Null
    }

    It 'Should refuse <Name>' -ForEach @(
        @{ Name = 'Add-LedgerAttachment'; Action = { Add-LedgerAttachment -JournalPath $J -FiscalYear $Y -VerificationNumber 1 -Path $agreement } }
        @{ Name = 'Remove-LedgerAttachment'; Action = { Remove-LedgerAttachment -JournalPath $J -FiscalYear $Y -VerificationNumber 1 -FileName 'kvitto.pdf' -Confirm:$false } }
        @{ Name = 'Remove-LedgerDocument'; Action = { Remove-LedgerDocument -JournalPath $J -FiscalYear $Y -FileName 'avtal.pdf' -Confirm:$false } }
        @{ Name = 'Copy-LedgerOpeningBalance'; Action = { Copy-LedgerOpeningBalance -JournalPath $J -FromFiscalYear $Y -ToFiscalYear $Y } }
        @{ Name = 'Add-LedgerEntry'; Action = {
                Add-LedgerEntry -JournalPath $J -FiscalYear $Y -Date '2024-06-01' -Description 'Sen' -Rows @(
                    @{ Account = '6110'; Amount = 50 }
                    @{ Account = '1930'; Amount = -50 }
                )
            }
        }
    ) {
        $before = Get-ChildItem -LiteralPath (Join-Path $J $Y) -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)" }

        { & $Action } | Should -Throw '*Closed*'

        $after = Get-ChildItem -LiteralPath (Join-Path $J $Y) -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)" }
        $after | Should -Be $before
        (Test-LedgerIntegrity -JournalPath $J -FiscalYear $Y).IsValid | Should -BeTrue
    }

    It 'Should refuse to copy an opening balance into a closed year' {
        Close-LedgerFiscalYear -JournalPath $J -FiscalYear $Next -SkipResultEntry | Out-Null
        { Copy-LedgerOpeningBalance -JournalPath $J -FromFiscalYear $Y -ToFiscalYear $Next } | Should -Throw '*Closed*'
    }

    It 'Should still allow annual report input and new documents after closing' {
        $signed = Join-Path $TestDrive 'arsredovisning-signerad.pdf'
        Set-Content -LiteralPath $signed -Value 'signerad'

        { Set-LedgerReportInput -JournalPath $J -FiscalYear $Y -SigningPlace 'Uppsala' } | Should -Not -Throw
        { Add-LedgerDocument -JournalPath $J -FiscalYear $Y -Path $signed } | Should -Not -Throw
    }
}
