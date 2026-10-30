BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')
}

Describe 'Export-LedgerArchive' {
    BeforeAll {
        $CommandName = 'Export-LedgerArchive'
        $Command = Get-Command -Name $CommandName
        $Fixture = Join-Path $PSScriptRoot 'Fixtures' 'FileFormat' 'Exempel.ledger'
        $OpenYear = '2024-01_2024-12'
        $ClosedYear = '2023-01_2023-12'

        function Copy-TestFixture {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            Copy-Item -Path $Fixture -Destination $dir -Recurse
            Join-Path $dir 'Exempel.ledger'
        }

        function Get-PackageFile {
            param ([string]$Root)
            $rootFull = (Resolve-Path $Root).Path
            @(Get-ChildItem $rootFull -Recurse -File | ForEach-Object { $_.FullName.Substring($rootFull.Length + 1).Replace('\', '/') } | Sort-Object)
        }
    }

    Context 'Function metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should support ShouldProcess' {
            $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }

        It 'Should have an optional FiscalYear parameter that binds from Name' {
            $Param = $Command.Parameters['FiscalYear']
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
            $Param.Aliases | Should -Contain 'Name'
        }

        It 'Should have <Name> as a switch parameter' -ForEach @(
            @{ Name = 'AsDirectory' }
            @{ Name = 'Force' }
        ) {
            $Command.Parameters[$Name].ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have an optional DestinationPath parameter of type String' {
            $Param = $Command.Parameters['DestinationPath']
            $Param.ParameterType.Name | Should -Be 'String'
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }
    }

    Context 'Behavior' {
        BeforeEach {
            $J = Copy-TestFixture
        }

        It 'Writes a zip with one package folder to an archive folder next to the journal' {
            $zip = Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear

            $zip.FullName | Should -Be (Join-Path (Split-Path $J -Parent) 'archive' "Exempel_${ClosedYear}_archive.zip")
            $archive = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
            try {
                $names = @($archive.Entries.FullName)
            }
            finally {
                $archive.Dispose()
            }
            $names | Should -Contain "Exempel_${ClosedYear}_archive/checksums.txt"
            $names | Where-Object { -not $_.StartsWith("Exempel_${ClosedYear}_archive/") } | Should -BeNullOrEmpty
            $names | Where-Object { $_.Contains('\') } | Should -BeNullOrEmpty
            Get-ChildItem (Split-Path $zip.FullName -Parent) -Filter '.tmp_*' -Force | Should -BeNullOrEmpty
        }

        It 'Includes the SIE file, the reports and a journal with only this fiscal year' {
            $dir = Export-LedgerArchive -JournalPath $J -FiscalYear $OpenYear -AsDirectory -Force -WarningAction SilentlyContinue

            $files = Get-PackageFile -Root $dir.FullName
            $expected = @(
                'README.txt', 'checksums.txt', 'manifest.txt'
                "sie/Exempel_$OpenYear.se"
                'journal/journal.txt', 'journal/accounts.txt', 'journal/dimensions.txt', 'journal/objects.txt', 'journal/vat.txt'
                'journal/customers.txt', 'journal/suppliers.txt', 'journal/employees.txt'
                "journal/$OpenYear/year.txt", "journal/$OpenYear/ib.txt", "journal/$OpenYear/holdings.txt"
                "journal/$OpenYear/report.txt", "journal/$OpenYear/integrity.txt"
                "journal/$OpenYear/ver0001/kvitto.pdf", "journal/$OpenYear/documents/avtal.pdf"
                'journal/invoices/inv0001.txt', 'journal/invoices/inv0002.txt'
                'journal/supplierinvoices/sup0001.txt', 'journal/payslips/pay0001.txt', 'journal/bank/stmt0001.txt'
                'reports/arsredovisning.md', 'reports/arsredovisning.docx', 'reports/arsredovisning.pdf'
            )
            $expected += 1..7 | ForEach-Object { "journal/$OpenYear/ver000$_.txt" }
            $expected += foreach ($r in 'grundbok', 'huvudbok', 'saldobalans', 'resultatrakning', 'balansrakning', 'momsrapport') {
                "reports/$r.txt", "reports/$r.pdf"
            }
            $files | Should -Be @($expected | Sort-Object)
        }

        It 'Preserves invoice posting records with the archived invoices' {
            $journal = New-TestLedger -Root $TestDrive -Customers @(@{ Number = '10'; Name = 'Volvo AB' }) `
                -Suppliers @(@{ Number = '100'; Name = 'Kontorsbolaget AB' })
            Set-LedgerJournal -JournalPath $journal -OrgNumber '556677-8899'
            New-LedgerInvoice -JournalPath $journal -CustomerNumber '10' -Date '2024-01-15' -Description 'Konsult' `
                -Rows @(@{ Account = '3010'; Amount = 1000; VatRate = 0.25; VatAccount = '2610' })
            Invoke-LedgerInvoicePosting -JournalPath $journal -InvoiceNumber 1
            $csv = Join-Path $TestDrive 'archive-payment.csv'
            Set-Content -LiteralPath $csv -Value @('Date;Amount;Text', '2024-01-20;1250;Volvo AB', '2024-01-21;-1250;Kontorsbolaget AB')
            Import-LedgerBankStatement -JournalPath $journal -Path $csv -Format Csv `
                -Delimiter ';' -DateColumn Date -AmountColumn Amount -TextColumn Text | Out-Null
            Set-LedgerBankTransaction -JournalPath $journal -TransactionId 1 -InvoiceNumber 1
            $paymentId = (Get-ChildItem -LiteralPath (Join-Path $journal 'invoices' 'payments') -File).BaseName
            New-TestPostedSupplierInvoice -JournalPath $journal -Date '2024-01-15' -Net 1000 | Out-Null
            Set-LedgerBankTransaction -JournalPath $journal -TransactionId 2 -SupplierInvoiceNumber 1
            $supplierId = (Get-ChildItem -LiteralPath (Join-Path $journal 'supplierinvoices' 'payments') -File).BaseName
            Close-LedgerFiscalYear -JournalPath $journal -FiscalYear $OpenYear -SkipResultEntry | Out-Null
            $package = Export-LedgerArchive -JournalPath $journal -FiscalYear $OpenYear -AsDirectory
            $original = Join-Path $journal 'invoices' 'posting' 'inv0001.txt'
            $archived = Join-Path $package.FullName 'journal' 'invoices' 'posting' 'inv0001.txt'
            (Get-FileHash -LiteralPath $archived).Hash | Should -Be (Get-FileHash -LiteralPath $original).Hash
            Get-Content -LiteralPath (Join-Path $package.FullName 'checksums.txt') -Raw |
                Should -BeLike '*journal/invoices/posting/inv0001.txt*'
            $originalPayment = Join-Path $journal 'invoices' 'payments' "$paymentId.txt"
            $archivedPayment = Join-Path $package.FullName 'journal' 'invoices' 'payments' "$paymentId.txt"
            (Get-FileHash -LiteralPath $archivedPayment).Hash | Should -Be (Get-FileHash -LiteralPath $originalPayment).Hash
            Get-Content -LiteralPath (Join-Path $package.FullName 'checksums.txt') -Raw |
                Should -BeLike "*journal/invoices/payments/$paymentId.txt*"
            $archivedTransaction = Get-LedgerBankTransaction -JournalPath (Join-Path $package.FullName 'journal') -TransactionId 1
            $archivedTransaction.MatchType | Should -Be 'CustomerInvoice'
            $archivedTransaction.VerificationNumber | Should -Be 2
            $originalSupplier = Join-Path $journal 'supplierinvoices' 'payments' "$supplierId.txt"
            $archivedSupplier = Join-Path $package.FullName 'journal' 'supplierinvoices' 'payments' "$supplierId.txt"
            (Get-FileHash -LiteralPath $archivedSupplier).Hash | Should -Be (Get-FileHash -LiteralPath $originalSupplier).Hash
            Get-Content -LiteralPath (Join-Path $package.FullName 'checksums.txt') -Raw |
                Should -BeLike "*journal/supplierinvoices/payments/$supplierId.txt*"
            $archivedJournal = Join-Path $package.FullName 'journal'
            $archivedTransaction = Get-LedgerBankTransaction -JournalPath $archivedJournal -TransactionId 2
            $archivedTransaction.MatchType | Should -Be 'SupplierInvoice'
            $archivedTransaction.VerificationNumber | Should -Be 4
            (Add-LedgerSupplierPayment -JournalPath $archivedJournal -InvoiceNumber 1 -PaymentId $supplierId -PassThru).Payments | Should -HaveCount 1
            (Add-LedgerInvoicePayment -JournalPath $archivedJournal -InvoiceNumber 1 -PaymentId $paymentId -PassThru).Payments | Should -HaveCount 1
        }

        It 'Includes an earlier invoice for a pending <Type> payment in the archived year without conflating invoice numbers' -ForEach @(
            @{ Type = 'Customer'; Command = 'Add-LedgerInvoicePayment'; Store = 'invoices'; File = 'inv0001.txt'; Other = 'supplierinvoices' }
            @{ Type = 'Supplier'; Command = 'Add-LedgerSupplierPayment'; Store = 'supplierinvoices'; File = 'sup0001.txt'; Other = 'invoices' }
        ) {
            $journal = New-TestLedger -Root $TestDrive -Customers @(@{ Number = '10'; Name = 'Volvo AB' }) `
                -Suppliers @(@{ Number = '100'; Name = 'Kontorsbolaget AB' })
            Set-LedgerJournal -JournalPath $journal -OrgNumber '556677-8899'
            New-TestPostedInvoice -JournalPath $journal | Out-Null
            New-TestPostedSupplierInvoice -JournalPath $journal | Out-Null
            New-LedgerFiscalYear -JournalPath $journal -StartDate '2025-01-01' -EndDate '2025-12-31'
            Mock Write-LedgerVerification -ModuleName PSLedger { throw 'Injected interruption after plan' }
            $id = New-Guid
            { & $Command -JournalPath $journal -InvoiceNumber 1 -Amount 500 -Date '2025-01-20' -PaymentId $id } | Should -Throw '*retry*'
            $package = Export-LedgerArchive -JournalPath $journal -FiscalYear '2025-01_2025-12' -AsDirectory -Force -WarningAction SilentlyContinue
            $archivedJournal = Join-Path $package.FullName 'journal'
            Test-Path -LiteralPath (Join-Path $archivedJournal $Store $File) | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $archivedJournal $Other) | Should -BeFalse
            $original = Join-Path $journal $Store 'payments' "$id.txt"
            $archived = Join-Path $archivedJournal $Store 'payments' "$id.txt"
            (Get-FileHash -LiteralPath $archived).Hash | Should -Be (Get-FileHash -LiteralPath $original).Hash
        }

        It 'Leaves out invoices, payslips and bank statements of other years' {
            $dir = Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear -AsDirectory

            $files = Get-PackageFile -Root $dir.FullName
            $files | Where-Object { $_ -match '^journal/(invoices|supplierinvoices|payslips|bank)/' } | Should -BeNullOrEmpty
            $files | Where-Object { $_ -match "^journal/$OpenYear/" } | Should -BeNullOrEmpty
        }

        It 'Copies the journal files unchanged so the archived chain still verifies' {
            $dir = Export-LedgerArchive -JournalPath $J -FiscalYear $OpenYear -AsDirectory -Force -WarningAction SilentlyContinue

            $source = Get-FileHash (Join-Path $J $OpenYear 'ver0001' 'kvitto.pdf')
            (Get-FileHash (Join-Path $dir.FullName 'journal' $OpenYear 'ver0001' 'kvitto.pdf')).Hash | Should -Be $source.Hash
            $integrity = Test-LedgerIntegrity -JournalPath (Join-Path $dir.FullName 'journal') -FiscalYear $OpenYear
            $integrity.Status | Should -Be 'Valid'
            $integrity.ChainHash | Should -Be (Test-LedgerIntegrity -JournalPath $J -FiscalYear $OpenYear).ChainHash
        }

        It 'Writes a manifest with the fiscal year, status and chain hash' {
            $dir = Export-LedgerArchive -JournalPath $J -FiscalYear $OpenYear -AsDirectory -Force -WarningAction SilentlyContinue

            $manifest = @{}
            Get-Content (Join-Path $dir.FullName 'manifest.txt') | Where-Object { $_ -notlike ';*' } | ForEach-Object {
                $k, $v = $_ -split "`t", 2
                $manifest[$k] = $v
            }
            $manifest.Journal | Should -Be 'Exempel AB'
            $manifest.OrgNumber | Should -Be '556677-8899'
            $manifest.FiscalYear | Should -Be $OpenYear
            $manifest.StartDate | Should -Be '2024-01-01'
            $manifest.YearStatus | Should -Be 'Open'
            $manifest.Preliminary | Should -Be 'True'
            $manifest.IntegrityStatus | Should -Be 'Valid'
            $manifest.ChainHash | Should -Be '85bf3eb0161b59585358f1586201364c56fdefaf8194fe9aa1663dd8e7bf666e'
            $manifest.Verifications | Should -Be '7'
            $manifest.Attachments | Should -Be '1'
            $manifest.Invoices | Should -Be '2'
            $manifest.Created | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
            $manifest.ContainsKey('Omitted') | Should -BeFalse
        }

        It 'Lists the SHA-256 of every other file in checksums.txt' {
            $dir = Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear -AsDirectory

            $lines = @(Get-Content (Join-Path $dir.FullName 'checksums.txt'))
            $files = Get-PackageFile -Root $dir.FullName | Where-Object { $_ -ne 'checksums.txt' }
            $lines.Count | Should -Be $files.Count
            foreach ($line in $lines) {
                $line | Should -Match '^[0-9a-f]{64}  \S'
                $hash, $rel = $line -split '  ', 2
                (Get-FileHash (Join-Path $dir.FullName $rel)).Hash.ToLowerInvariant() | Should -Be $hash
            }
        }

        It 'Writes readable reports in text and PDF' {
            $dir = Export-LedgerArchive -JournalPath $J -FiscalYear $OpenYear -AsDirectory -Force -WarningAction SilentlyContinue
            $reports = Join-Path $dir.FullName 'reports'

            $journal = Get-Content -Raw (Join-Path $reports 'grundbok.txt')
            $journal | Should -Match 'Grundbok'
            $journal | Should -Match 'PRELIMINÄR'
            $journal | Should -Match 'Kontorsmaterial'
            $journal | Should -Match 'Summa \(7 verifikationer\)'
            $ledger = Get-Content -Raw (Join-Path $reports 'huvudbok.txt')
            $ledger | Should -Match '1930\s+Företagskonto'
            $ledger | Should -Match 'Ingående saldo\s+25 000,00'
            Get-Content -Raw (Join-Path $reports 'balansrakning.txt') | Should -Match 'Summa tillgångar\s+14 955,00'
            foreach ($pdf in Get-ChildItem $reports -Filter '*.pdf') {
                [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($pdf.FullName), 0, 5) | Should -Be '%PDF-'
            }
        }

        It 'Skips the annual report with a warning when it cannot be produced' {
            Mock -ModuleName PSLedger Build-LedgerAnnualReportBlocks { throw 'Company profile missing' }

            $dir = Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear -AsDirectory -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings -join ' ') | Should -Match 'annual report'
            Get-ChildItem (Join-Path $dir.FullName 'reports') -Filter 'arsredovisning.*' | Should -BeNullOrEmpty
            Get-Content (Join-Path $dir.FullName 'manifest.txt') | Should -Contain "Omitted`treports/arsredovisning: Company profile missing"
            Test-Path (Join-Path $dir.FullName 'reports' 'grundbok.pdf') | Should -BeTrue
        }

        It 'Throws for an open fiscal year unless -Force is given' {
            { Export-LedgerArchive -JournalPath $J -FiscalYear $OpenYear } | Should -Throw '*is open*-Force*'
            Test-Path (Join-Path (Split-Path $J -Parent) 'archive' "Exempel_${OpenYear}_archive.zip") | Should -BeFalse
        }

        It 'Throws when the integrity check fails unless -Force is given' {
            Add-Content (Join-Path $J $ClosedYear 'ver0001.txt') 'x'

            { Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear } | Should -Throw '*integrity check*Modified*'

            $zip = Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear -Force -WarningAction SilentlyContinue
            $zip | Should -Not -BeNullOrEmpty
            (Test-LedgerArchive -Path $zip).Issues.Problem | Should -Contain 'Integrity'
        }

        It 'Warns and leaves the chain hash empty for a year without a chain' {
            Remove-Item (Join-Path $J $ClosedYear 'integrity.txt')

            $dir = Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear -AsDirectory -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings -join ' ') | Should -Match 'Protect-LedgerFiscalYear'
            Get-Content (Join-Path $dir.FullName 'manifest.txt') | Should -Contain "IntegrityStatus`tUnsealed"
            (Test-LedgerArchive -Path $dir).Status | Should -Be 'Valid'
        }

        It 'Throws when the archive exists and overwrites it with -Force' {
            $dest = Join-Path $TestDrive 'Arkiv'
            $first = Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear -DestinationPath $dest
            { Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear -DestinationPath $dest } | Should -Throw '*already exists*'

            $second = Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear -DestinationPath $dest -Force
            $second.FullName | Should -Be $first.FullName
            (Test-LedgerArchive -Path $second).IsValid | Should -BeTrue
        }

        It 'Accepts fiscal years from the pipeline' {
            $dest = Join-Path $TestDrive 'Pipeline'
            $results = @(Get-LedgerFiscalYear -JournalPath $J | Where-Object Status -eq 'Closed' |
                    Export-LedgerArchive -JournalPath $J -DestinationPath $dest)
            $results.Name | Should -Be @("Exempel_${ClosedYear}_archive.zip")
        }

        It 'Writes nothing with -WhatIf' {
            Export-LedgerArchive -JournalPath $J -FiscalYear $ClosedYear -WhatIf
            Test-Path (Join-Path (Split-Path $J -Parent) 'archive') | Should -BeFalse
        }

        It 'Does not change the journal' {
            $before = Get-ChildItem $J -Recurse -File | ForEach-Object { "$($_.FullName) $((Get-FileHash $_.FullName).Hash)" }
            Export-LedgerArchive -JournalPath $J -FiscalYear $OpenYear -Force -WarningAction SilentlyContinue | Out-Null
            $after = Get-ChildItem $J -Recurse -File | ForEach-Object { "$($_.FullName) $((Get-FileHash $_.FullName).Hash)" }
            $after | Should -Be $before
        }
    }
}
