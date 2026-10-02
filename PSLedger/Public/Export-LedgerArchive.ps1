<#
.SYNOPSIS
Exports a fiscal year as a self-contained archive package for long-term storage.

.DESCRIPTION
Creates a package that keeps the fiscal year's accounting records (räkenskapsinformation)
readable without PSLedger for the seven years the Swedish Bookkeeping Act
(bokföringslagen) requires. By default the package is one zip file,
'<JournalName>_<FiscalYear>_archive.zip', containing a folder with the same name:

  README.txt       what the package contains and how to verify it (in Swedish)
  manifest.txt     company, fiscal year, PSLedger version, integrity status and
                   the year's final chain hash
  checksums.txt    SHA-256 of every other file, in the format of 'sha256sum -c'
  sie/             the year as a SIE 4 file
  reports/         grundbok, huvudbok, saldobalans, resultaträkning, balansräkning
                   and momsrapport as .txt and .pdf, and the annual report as
                   .md, .docx and .pdf
  journal/         a PSLedger journal with only this fiscal year: the registers,
                   the fiscal-year directory (verifications, attachments, documents,
                   integrity.txt), and the customer invoices, supplier invoices,
                   payslips and bank statements that belong to the year

Customer and supplier invoices are included when their invoice date is in the
year, they are booked in the year or a payment is booked in the year. Payslips are
included by pay date or booking, bank statements when their period overlaps the
year. Recurring entries, time reporting and extensions are not included.

Before exporting, the fiscal year must be closed and its integrity chain intact
(see Test-LedgerIntegrity). A year without a chain is exported with a warning.
A report that cannot be produced (for example an annual report without the
required company information) is skipped with a warning and listed in the manifest.

Use Test-LedgerArchive to verify a package later.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year to archive. If omitted, uses the latest fiscal year.
Accepts pipeline input from fiscal year objects.

.PARAMETER DestinationPath
The directory to write the package to. Defaults to an 'archive' folder next to
the journal directory. Created if it does not exist.

.PARAMETER AsDirectory
Write the package as a directory instead of a zip file.

.PARAMETER Force
Export even if the fiscal year is open (the package is marked as preliminary)
or its integrity check fails (the result is recorded in the manifest), and
overwrite an existing package.

.EXAMPLE
Export-LedgerArchive -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

Creates .\archive\MinFirma_2024-01_2024-12_archive.zip next to Min Firma AB's journal.

.EXAMPLE
Get-LedgerFiscalYear -JournalPath .\Konsult.ledger | Where-Object Status -eq 'Closed' |
    Export-LedgerArchive -JournalPath .\Konsult.ledger -DestinationPath E:\Arkiv

Archives every closed fiscal year of Konsult AB to an external disk.
#>
function Export-LedgerArchive {
    [OutputType([System.IO.FileSystemInfo])]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [string]$DestinationPath,

        [switch]$AsDirectory,

        [switch]$Force
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $journalDir = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($JournalPath).TrimEnd('\', '/')
        $yearDir = Join-Path $journalDir $FiscalYear
        if (-not (Test-Path -LiteralPath $yearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }
        $year = Get-LedgerFiscalYear -JournalPath $journalDir | Where-Object { $_.Name -eq $FiscalYear }
        if (-not $year) {
            throw "Fiscal year year.txt missing for $FiscalYear"
        }
        $preliminary = $year.Status -ne 'Closed'
        if ($preliminary -and -not $Force) {
            throw "Fiscal year $FiscalYear is open. Close it with Close-LedgerFiscalYear, or use -Force to export a preliminary archive."
        }

        $integrity = Test-LedgerIntegrity -JournalPath $journalDir -FiscalYear $FiscalYear
        if ($integrity.Status -eq 'Invalid') {
            $summary = @($integrity.Issues | Select-Object -First 5 | ForEach-Object { "$($_.Kind) $($_.Key): $($_.Problem)" }) -join '; '
            if (-not $Force) {
                throw "The integrity check of $FiscalYear failed ($summary). Run Test-LedgerIntegrity for details, or use -Force to archive anyway."
            }
            Write-Warning "The integrity check of $FiscalYear failed ($summary). Archiving anyway because -Force was given."
        }
        elseif ($integrity.Status -eq 'Unsealed') {
            Write-Warning "Fiscal year $FiscalYear has no integrity chain. Seal it with Protect-LedgerFiscalYear before archiving to include one."
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($journalDir)
        $packageName = "${baseName}_${FiscalYear}_archive"
        if (-not $DestinationPath) {
            $DestinationPath = Join-Path (Split-Path $journalDir -Parent) 'archive'
        }
        $destDir = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DestinationPath)
        $target = if ($AsDirectory) { Join-Path $destDir $packageName } else { Join-Path $destDir "$packageName.zip" }

        if ((Test-Path -LiteralPath $target) -and -not $Force) {
            throw "Archive already exists: $target. Use -Force to overwrite."
        }

        if (-not $PSCmdlet.ShouldProcess($target, "Export archive of fiscal year $FiscalYear")) {
            return
        }

        if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        $staging = Join-Path $destDir ".tmp_$([guid]::NewGuid().ToString('N'))"
        try {
            $root = Join-Path $staging $packageName
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            foreach ($dir in 'sie', 'reports', 'journal') {
                New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null
            }

            # --- journal/: a journal holding only this fiscal year ------------
            $archJournal = Join-Path $root 'journal'
            foreach ($file in 'journal.txt', 'accounts.txt', 'dimensions.txt', 'objects.txt', 'customers.txt', 'suppliers.txt', 'employees.txt') {
                $src = Join-Path $journalDir $file
                if (Test-Path -LiteralPath $src -PathType Leaf) {
                    Copy-Item -LiteralPath $src -Destination (Join-Path $archJournal $file)
                }
            }
            Copy-Item -LiteralPath $yearDir -Destination (Join-Path $archJournal $FiscalYear) -Recurse
            Get-ChildItem -LiteralPath (Join-Path $archJournal $FiscalYear) -Recurse -File -Filter '.tmp_*' -Force |
                Remove-Item -Force

            $start = [datetime]$year.StartDate
            $end = [datetime]$year.EndDate
            $inYear = { param($date) $null -ne $date -and ([datetime]$date) -ge $start -and ([datetime]$date) -le $end }
            $copyDocument = {
                param($sourcePath, $subDir)
                $dest = Join-Path $archJournal $subDir
                if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
                Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $dest (Split-Path $sourcePath -Leaf))
            }

            $invoices = 0
            foreach ($inv in @(Get-LedgerInvoice -JournalPath $journalDir)) {
                if ((& $inYear $inv.InvoiceDate) -or $inv.BookedFiscalYear -eq $FiscalYear -or
                    @($inv.Payments | Where-Object { $_.FiscalYear -eq $FiscalYear }).Count -gt 0) {
                    & $copyDocument $inv.FilePath 'invoices'
                    $invoices++
                }
            }
            $supplierInvoices = 0
            foreach ($inv in @(Get-LedgerSupplierInvoice -JournalPath $journalDir)) {
                if ((& $inYear $inv.InvoiceDate) -or $inv.BookedFiscalYear -eq $FiscalYear -or
                    @($inv.Payments | Where-Object { $_.FiscalYear -eq $FiscalYear }).Count -gt 0) {
                    & $copyDocument $inv.FilePath 'supplierinvoices'
                    $supplierInvoices++
                }
            }
            $payslips = 0
            foreach ($slip in @(Get-LedgerPayslip -JournalPath $journalDir)) {
                if ((& $inYear $slip.PayDate) -or $slip.BookedFiscalYear -eq $FiscalYear) {
                    & $copyDocument $slip.FilePath 'payslips'
                    $payslips++
                }
            }
            $statements = 0
            foreach ($stmt in @(Get-LedgerBankStatement -JournalPath $journalDir)) {
                $from = if ($stmt.FromDate) { [datetime]$stmt.FromDate } else { [datetime]$stmt.ImportedDate }
                $to = if ($stmt.ToDate) { [datetime]$stmt.ToDate } else { $from }
                $file = Join-Path $journalDir 'bank' ('stmt{0:D4}.txt' -f [int]$stmt.StatementNumber)
                if ($from -le $end -and $to -ge $start -and (Test-Path -LiteralPath $file -PathType Leaf)) {
                    & $copyDocument $file 'bank'
                    $statements++
                }
            }

            # --- sie/ and reports/ ---------------------------------------------
            Export-LedgerSie -JournalPath $journalDir -FiscalYear $FiscalYear -Path (Join-Path $root 'sie' "${baseName}_${FiscalYear}.se") -Confirm:$false -WhatIf:$false

            $journal = Get-LedgerJournal -Path $journalDir
            $version = [string]$MyInvocation.MyCommand.Module.Version
            $created = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
            $context = [pscustomobject]@{
                CompanyName = $journal.Name; OrgNumber = $journal.OrgNumber
                StartDate = $start.ToString('yyyy-MM-dd'); EndDate = $end.ToString('yyyy-MM-dd')
                Preliminary = $preliminary; Created = $created; Version = $version
            }

            $entries = @(Get-LedgerEntry -JournalPath $journalDir -FiscalYear $FiscalYear)
            $balances = @(Get-LedgerBalance -JournalPath $journalDir -FiscalYear $FiscalYear)
            $accountNames = @{}
            foreach ($a in @(Get-LedgerAccount -JournalPath $journalDir)) { $accountNames[[string]$a.AccountNumber] = $a.AccountName }

            $reportsDir = Join-Path $root 'reports'
            $omitted = [System.Collections.Generic.List[string]]::new()
            $reports = [ordered]@{
                grundbok        = { Build-LedgerArchiveJournalBlocks -Entries $entries -AccountNames $accountNames -Context $context }
                huvudbok        = { Build-LedgerArchiveGeneralLedgerBlocks -Entries $entries -Balances $balances -Context $context }
                saldobalans     = { Build-LedgerArchiveTrialBalanceBlocks -Balances $balances -Context $context }
                resultatrakning = {
                    Build-LedgerArchiveStatementBlocks -Title 'Resultaträkning' -Context $context `
                        -Lines @(Get-LedgerIncomeStatement -JournalPath $journalDir -FiscalYear $FiscalYear) `
                        -SumGroups 'OperatingResult', 'ResultAfterFinancialItems', 'NetResult'
                }
                balansrakning   = {
                    Build-LedgerArchiveStatementBlocks -Title 'Balansräkning' -Context $context `
                        -Lines @(Get-LedgerBalanceSheet -JournalPath $journalDir -FiscalYear $FiscalYear) `
                        -SumGroups 'TotalAssets', 'TotalEquityAndLiabilities' -NegateSections 'EquityAndLiabilities' `
                        -Note 'Eget kapital och skulder visas med positivt tecken.'
                }
                momsrapport     = {
                    Build-LedgerArchiveVatBlocks -Context $context `
                        -Lines @(Get-LedgerVatReport -JournalPath $journalDir -FiscalYear $FiscalYear -FromDate $start -ToDate $end)
                }
            }
            foreach ($name in $reports.Keys) {
                try {
                    $blocks = @(& $reports[$name])
                    Write-LedgerArchiveReport -Block $blocks -BasePath (Join-Path $reportsDir $name)
                }
                catch {
                    Write-Warning "Skipped report '$name': $($_.Exception.Message)"
                    $omitted.Add("reports/$name`: $($_.Exception.Message)")
                }
            }
            try {
                $blocks = @(Build-LedgerAnnualReportBlocks -JournalPath $journalDir -FiscalYear $FiscalYear)
                [System.IO.File]::WriteAllText((Join-Path $reportsDir 'arsredovisning.md'), (ConvertTo-LedgerReportMarkdown -Block $blocks), $utf8)
                ConvertTo-LedgerReportDocx -Block $blocks -Path (Join-Path $reportsDir 'arsredovisning.docx')
                ConvertTo-LedgerReportPdf -Block $blocks -Path (Join-Path $reportsDir 'arsredovisning.pdf')
            }
            catch {
                Write-Warning "Skipped the annual report: $($_.Exception.Message)"
                Get-ChildItem -LiteralPath $reportsDir -Filter 'arsredovisning.*' | Remove-Item -Force
                $omitted.Add("reports/arsredovisning: $($_.Exception.Message)")
            }

            # --- manifest.txt, README.txt, checksums.txt -----------------------
            $manifest = [System.Collections.Generic.List[string]]::new()
            $manifest.Add('; PSLedger archive manifest')
            $fields = [ordered]@{
                ArchiveFormat    = $script:LedgerArchiveFormatVersion
                Journal          = $journal.Name
                OrgNumber        = $journal.OrgNumber
                FiscalYear       = $FiscalYear
                StartDate        = $context.StartDate
                EndDate          = $context.EndDate
                YearStatus       = $year.Status
                Preliminary      = $preliminary
                Created          = $created
                PSLedgerVersion  = $version
                SchemaVersion    = $journal.SchemaVersion
                IntegrityStatus  = $integrity.Status
                ChainHash        = $integrity.ChainHash
                Verifications    = $entries.Count
                Attachments      = @(Get-ChildItem -LiteralPath $yearDir -Directory -Filter 'ver*' | Get-ChildItem -File).Count
                Invoices         = $invoices
                SupplierInvoices = $supplierInvoices
                Payslips         = $payslips
                BankStatements   = $statements
            }
            foreach ($key in $fields.Keys) {
                $manifest.Add("$key`t$(ConvertTo-LedgerTextField ([string]$fields[$key]))")
            }
            foreach ($o in $omitted) { $manifest.Add("Omitted`t$(ConvertTo-LedgerTextField $o)") }
            [System.IO.File]::WriteAllText((Join-Path $root $script:LedgerArchiveManifestFile), (($manifest -join "`n") + "`n"), $utf8)

            $prelimText = if ($preliminary) { "`nOBS: räkenskapsåret var inte stängt när arkivet skapades. Arkivet är preliminärt.`n" } else { '' }
            $readme = @"
Arkiv för räkenskapsår $FiscalYear ($($context.StartDate) - $($context.EndDate))
$($journal.Name) $($journal.OrgNumber)
Skapat $created med PSLedger $version.
$prelimText
Innehåll
  manifest.txt   uppgifter om arkivet (företag, år, integritetskontroll, kedjans hash)
  checksums.txt  SHA-256 för alla övriga filer
  sie/           räkenskapsåret som SIE 4-fil (kan läsas in i andra bokföringsprogram)
  reports/       grundbok, huvudbok, saldobalans, resultaträkning, balansräkning och
                 momsrapport (.txt och .pdf) samt årsredovisningen (.md, .docx, .pdf)
  journal/       bokföringen i PSLedgers textformat: verifikationer (verNNNN.txt),
                 bilagor (verNNNN/), årets dokument, integrity.txt, register,
                 fakturor, leverantörsfakturor, lönebesked och bankutdrag för året

Alla textfiler är UTF-8. Filformatet beskrivs i docs/File-format.md i PSLedger
(https://github.com/hansEricG/PSLedger).

Kontrollera arkivet
  PowerShell med PSLedger:  Test-LedgerArchive -Path <arkiv>
  Linux/macOS:              sha256sum -c checksums.txt
"@
            [System.IO.File]::WriteAllText((Join-Path $root 'README.txt'), $readme.Replace("`r`n", "`n"), $utf8)

            $checksums = foreach ($rel in (Get-LedgerArchiveRelativeFile -Root $root)) {
                "$(Get-LedgerArchiveFileHash -Path (Join-Path $root $rel))  $rel"
            }
            [System.IO.File]::WriteAllText((Join-Path $root $script:LedgerArchiveChecksumFile), (($checksums -join "`n") + "`n"), $utf8)

            # --- move into place -----------------------------------------------
            if ($AsDirectory) {
                if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
                Move-Item -LiteralPath $root -Destination $target
            }
            else {
                $tmpZip = Join-Path $staging "$packageName.zip"
                [System.IO.Compression.ZipFile]::CreateFromDirectory($root, $tmpZip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
                [System.IO.File]::Move($tmpZip, $target, $true)
            }
        }
        finally {
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
        }

        Get-Item -LiteralPath $target
    }
}
