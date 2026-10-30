# Roadmap to PSLedger 1.0

> **Done:** every item below was completed and PSLedger 1.0.0 was released on
> 2026-10-02. See [Later (1.x)](#later-1x) for what comes next.

PSLedger already covers the bookkeeping features a small Swedish company needs:
ledger, VAT, annual report, SIE, invoicing, supplier invoices, payroll, bank
reconciliation and time reporting. Version 1.0 is about **stability and
promises**: the file format, the commands and the installation should not
change without a migration path.

Items are listed in the suggested order.

## Must have for 1.0

### 1. Correct PowerShell requirement
The manifest declares `PowerShellVersion = '5.1'`, but the code uses
PowerShell 7 features in at least 35 places (`[System.Globalization.ISOWeek]`,
`Join-Path` with several child paths, `??`, `?.`).

- [x] Set `PowerShellVersion = '7.4'` and `CompatiblePSEditions = @('Core')`.
- [x] State the requirement in the README.

### 2. Continuous integration and Pester 6
There is no GitHub Actions workflow; tests only run when someone runs them.

- [x] Upgrade the test suite to Pester 6 (verified: all 1494 tests pass
      unchanged on Pester 6.2.0, and the run is faster than on 5.7.1).
- [x] Require Pester 6 in the workflow and in the Build & Test instructions.
- [x] Add a workflow that runs `Invoke-Pester ./Tests` on Windows and Linux.
- [x] Run PSScriptAnalyzer in the workflow and fix or suppress its findings.
- [ ] Optionally move to the new `Should-*` assertions gradually.

### 3. Documented and frozen file format
The text files are the product, so their format is the most important contract.

- [x] Write a file format specification covering every file (journal, accounts,
      verifications, ib, holdings, report, dimensions/objects, customers,
      invoices, suppliers, employees, payslips, bank, time).
- [x] Document when `SchemaVersion` is bumped: from 1.0 every breaking change
      needs an `Invoke-Ledger*Migration` step and `Update-LedgerJournal` support.

Done: [docs/File-format.md](docs/File-format.md), guarded by the contract test
`Tests/FileFormat.Tests.ps1`.

### 4. Command review before freezing the API
There are 129 public commands; renaming after 1.0 is expensive.

- [x] Review names and parameters for consistency across the registers
      (e.g. how number, date and account parameters are named).
- [x] Consistent `-PassThru`, `-WhatIf`/`-Confirm` and pipeline support.
- [x] Every public command has complete comment-based help with at least two
      examples (add a test that enforces it).

### 5. Publishing
- [x] Explicit `FunctionsToExport` list instead of `'*'` (extensions are still
      exported at import time).
- [x] Remove `testResults.xml` from the repository and ignore it.
- [x] Publish to the PowerShell Gallery from a tagged release in CI.

## Important for bookkeeping law (BFL)

### 6. Tamper detection
Verifications are plain text files and can be edited afterwards.

- [x] `Test-LedgerIntegrity`: a SHA-256 hash chain per fiscal year
      (`integrity.txt`) seals verifications and attachments, so changes to
      posted entries can be detected (supports the permanence requirement,
      varaktighet). `Protect-LedgerFiscalYear` seals existing journals, and
      `Close-LedgerFiscalYear` returns the final chain hash.

### 7. Archiving
- [x] Export a closed fiscal year as an archive package (SIE, PDF/Markdown
      reports and all supporting documents) suitable for seven years' storage:
      `Export-LedgerArchive` writes a zip with SHA-256 checksums and the
      year's chain hash, and `Test-LedgerArchive` verifies it.

## Later (1.x)

Items are grouped and listed in the suggested order: correctness first, then
technical debt, tooling, and features. Findings come from a code review in
October 2026.

### Correctness

#### 8. VAT declaration mapping
`Private/VatBasMapping.ps1` mapped every account 3000–3799 to box 05 and only
knew boxes 05, 10–12 and 48.

- [x] Map exports and EU sales to their own boxes instead of box 05 (for
      example 3105 → 36, 3108 → 35, 3305/3308 → 39–40).
- [x] Map reverse-charge output VAT (2614, 2624, 2634) to boxes 30–32 and the
      purchase bases to boxes 20–24. Today a purchase booked with 2645 is
      deducted in box 48 while the matching output VAT is missing, so the
      declaration overstates the refund.
- [x] Import VAT (box 50 and 60–62) and the remaining boxes (06–08, 41–42).
- [x] Write box 48 with the eSKD tag `MomsIngAvdr` (it was `MomsIngaende`).
- [x] Use standard BAS accounts in the BAS-Komplett and BAS-Smaforetag
      templates, a journal-level `vat.txt` to override the mapping, and
      `Convert-LedgerChart` for journals created from the earlier templates.

#### 9. Balance check on rounded amounts
`Add-LedgerEntry` rounds only the sum, so rows such as `10.004` and `-10.001`
are accepted and stored although the entry is 0.003 off.

- [x] Reject (or round) row amounts with more than two decimals, so every
      stored verification balances exactly.

#### 10. Closed-year guards
`Add-LedgerEntry`, holdings and projects reject a closed year, but
`Add-LedgerAttachment`, `Remove-LedgerAttachment`, `Add-LedgerDocument`,
`Remove-LedgerDocument`, `Copy-LedgerOpeningBalance` and
`Set-LedgerReportInput` do not.

- [ ] One shared guard for year-scoped writes, with a test that runs every
      writing command against a closed year.

#### 11. Integrity chain robustness and coverage
- [ ] `Write-LedgerIntegrityRecord` appends with `File.AppendAllText` outside
      the atomic write helper; make the read-head-and-append step safe against
      concurrent writers.
- [ ] Report a duplicate `Verification` record for the same key as a chain
      error instead of silently keeping the first one.
- [ ] Consider sealing `ib.txt` and `year.txt` as well: a changed opening
      balance changes every balance in the year without being detected.

#### 12. Concurrent writers
Verification numbers come from scanning `ver*.txt`, and register files
(`Add-LedgerFileLine`) are read-modify-write, so two processes writing at the
same time can pick the same number or lose a line.

- [ ] Create verification files with create-if-absent (`FileMode.CreateNew`)
      and retry on conflict, or take a journal lock file around writes.
      Prerequisite for multi-user workflows (step 21).

### Technical debt

#### 13. One verification reader
Verification files are parsed in more than one place (for example
`Get-LedgerBalance` reads `ver*.txt` itself instead of going through
`Get-LedgerEntry`).

- [ ] Move parsing into one private reader used by every command, so there is
      a single interpretation of the file format.
- [ ] Consider caching the parsed verifications per fiscal year (invalidated
      on write) to speed up reports on large years.

#### 14. Shared register store
Customers, suppliers and employees are read and written by hand-written
tab-splitting in each public command, while invoices, time and bank have
private stores.

- [ ] One generic tab-separated register reader/writer with field-count
      validation, used by all registers.
- [ ] Avoid rereading `accounts.txt` and the registers for every row and
      avoid `+=` array growth in the stores.

#### 15. Fewer places to register a public function
A new public function must be added to the dot-source list and
`$script:BuiltInFunctions` in `PSLedger.psm1` and to `FunctionsToExport` in
`PSLedger.psd1`.

- [ ] Generate the dot-source list and `$script:BuiltInFunctions` from
      `Public/`, keeping the explicit `FunctionsToExport` (checked by
      `Tests/Manifest.Tests.ps1`).

#### 16. Split the annual report code
- [ ] Split `Private/AnnualReportModel.ps1` (about 49 KB) and
      `Private/AnnualReportRender.ps1` into smaller files per section
      (management report, income statement, balance sheet, notes).

#### 17. Yearly rates in one place
The employer contribution rate 31.42 % is a default in both
`New-LedgerPayslip` and `Add-LedgerVacationLiability`, and other yearly
values (SRU mapping, tax rates) live in code.

- [ ] Keep yearly rates in a data file per year (like the chart templates),
      including reduced employer contributions by age.

### Testing, CI and documentation

#### 18. Tests
- [ ] Performance test (or benchmark script) with about 10 000 verifications
      in a year, measuring the common reports.
- [ ] Property-style test: random balanced entries, reversals and SIE
      round-trips always keep every verification and the year balanced.
- [ ] Run selected tests under both `sv-SE` and `en-US` culture.
- [ ] SIE import tests with anonymised files from Fortnox, Visma and other
      common systems.
- [ ] Optionally move to the new `Should-*` assertions gradually (carried over
      from step 2).

#### 19. CI and release
- [ ] Add macOS to the test matrix (the README promises macOS support).
- [ ] Run PSScriptAnalyzer on `Tests/` as well.
- [ ] Code coverage report from Pester.
- [ ] Dependabot for GitHub Actions; consider pinning actions by SHA.
- [ ] Run `Test-ModuleManifest` on the package before publishing.
- [ ] Review the broad rule exclusions in `PSScriptAnalyzerSettings.psd1`
      (for example `PSUseShouldProcessForStateChangingFunctions`) and use
      targeted suppressions instead.

#### 20. Documentation
- [ ] Shorten `README.md` (about 41 KB) to installation, quick start and a
      command index; move the walkthroughs to `docs/`.
- [ ] `CONTRIBUTING.md` and an `about_PSLedger` help topic.
- [ ] Pages in `docs/` for extensions and year-end routines that are only in
      the README today.

### Features

#### 21. Period locking and multi-user
- [ ] Lock a fiscal year per month (for example after the VAT return), so new
      verifications cannot be dated in a locked period. Fits with the
      integrity chain.
- [ ] Multi-user workflows (builds on step 12), including who did what in the
      integrity chain.

#### 22. VAT: reverse charge, EU and periods
- [ ] Invoice and supplier invoice rows with VAT type (domestic, reverse
      charge construction, EU goods/services, export, import) that pick the
      right accounts and boxes (see step 8).
- [ ] Periodisk sammanställning (EC Sales List) for EU B2B sales, using the
      customer's VAT number.
- [ ] VAT period (month/quarter/year) and kontantmetoden as journal settings.

#### 23. Foreign currency on invoices
- [ ] Currency and exchange rate on customer and supplier invoices, posted in
      SEK, with realised exchange differences (3960/7960) on payment.

#### 24. Invoicing gaps
- [ ] Credit paid and partially paid invoices (today only booked, unpaid
      invoices can be credited), including partial credits and refunds.
- [ ] Supplier credit notes.
- [ ] Customer prepayments (förskott) and confirmed bad debts (kundförluster)
      with VAT correction.
- [ ] ROT/RUT deduction on invoices, with the claim to Skatteverket.

#### 25. Payments
- [ ] Payment file export for supplier invoices (ISO 20022 pain.001 /
      Bankgirot), matched back by the existing bank import.

#### 26. Payroll
- [ ] Benefits (bilförmån), mileage and per diem (milersättning,
      traktamente), expense reimbursements and board fees.
- [ ] Reduced employer contributions (age, växa-stöd) and pension with
      särskild löneskatt.

#### 27. Year-end and tax
- [ ] Periodiseringsfond lifecycle (allocate, reverse, schablonintäkt) and
      överavskrivningar, feeding INK2.
- [ ] K10 for owners of fåmansföretag (gränsbelopp, dividends).

#### 28. Reports and exports
- [ ] Income statement per object/project and per month, with prior-year
      comparison columns.
- [ ] Trial balance (saldobalans) for any period.
- [ ] CSV/Excel export of the general ledger and reports.

#### 29. Direct submission to Skatteverket
- [ ] VAT return and employer declaration (AGI) submitted directly through
      Skatteverket's API (requires BankID/e-legitimation; large effort).

#### Other ideas
- E-invoicing (Peppol BIS Billing / Svefaktura) for customer invoices.
- Budget and forecast per account and object.
- Fixed asset register (anläggningsregister) driving `Add-LedgerDepreciation`.
- Importing supplier invoices from PDF/e-invoice files.
- Recurring invoices (subscriptions) and invoice number series.
- Cash sales and kassabok for businesses with cash registers.
- Enskild firma (NE-bilaga) and ekonomisk förening.
- Inventory (lager) with stock valuation.
