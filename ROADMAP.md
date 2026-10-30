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

The numbered items below are a backlog with stable identifiers, not a release
sequence. The milestones define the suggested order. Findings come from code
reviews in October 2026; a checked implementation task does not by itself mean
that the whole workflow is ready to release.

The next release cycle focuses on reliable bookkeeping for small Swedish
service companies (AB), rather than adding more business types and integrations.
Existing functionality for other users remains supported.

### Milestones and release criteria

| Order | Milestone | Scope | Done when |
|-------|-----------|-------|-----------|
| A | Finish the correctness fixes | 8–10 | Conversion works with opening balances, preserves effective VAT boxes, and rejects invalid plans before writing; VAT special cases have independent reference examples; legacy corrections and closed-year document replacement have explicit policies. |
| B | Reliable storage and recovery | 11–12, 30 | Number allocation, ledger writes and integrity records share one locking boundary; interrupted operations can be diagnosed and retried without lost or duplicate bookkeeping. |
| C | Consistent validation | 13 and correctness tests from 18 | Writers, readers, imports and checks agree on amounts, dates and required fields; supported legacy data has a documented correction path. |
| D | Finalised periods and reproducible reports | 21, 31 | Locked periods reject all affected posting paths, while submitted reports retain their original inputs, rule versions and correction history. |
| E | Complete existing business workflows | Priority parts of 17, 22, 24 | Effective-dated rules, EU VAT reporting, credit notes and refunds work end to end for the target users. |

Relevant tests and release checks from 18–19 belong to every milestone, not to
a later cleanup phase. Refactoring in 14–16 and documentation work in 20 should
support these outcomes. Currency, payment integrations, expanded payroll,
K10, ROT/RUT and new business types remain demand-driven backlog items.

### 1.1.0 — released 2026-10-30

This additive feature release completed milestone A and the following
directly related improvements:

- [x] Complete the reviewed correctness fixes in 8–10.
- [x] Account-level VAT explanations (`Get-LedgerVatReportDetail`): amounts,
      matched rules and sources, explicit exclusions versus unmapped accounts.
- [x] Regression coverage for duplicate verification seals with valid chain
      hashes. Detection already existed; no integrity-format change is needed.
- [x] Independent VAT report/export examples for import, credit notes,
      triangular trade and separately calculated VMB.
- [x] Configure macOS CI and restore/import checks on the actual module
      package; publish the verified artifact, not a second build.
- [x] Require successful Windows, Linux and macOS CI runs before release.
- [x] Set `ModuleVersion` to 1.1.0 and prepare the changelog.
- [x] Tag and publish the release after the cross-platform checks pass.

Locking, interrupted-operation recovery and period locks remain subsequent
milestones, not prerequisites silently added to this release.

### Correctness

#### 8. VAT declaration mapping
`Private/VatBasMapping.ps1` mapped every account 3000–3799 to box 05 and only
knew boxes 05, 10–12 and 48.

- [x] Map exports and EU sales to their own boxes instead of box 05 (for
      example 3105 → 36, 3108 → 35, 3305/3308 → 39–40).
- [x] Map reverse-charge output VAT (2614, 2624, 2634) to boxes 30–32 and the
      purchase bases to boxes 20–24, instead of deducting input VAT without
      reporting the matching output VAT.
- [x] Import VAT (box 50 and 60–62) and the remaining boxes (06–08, 41–42).
- [x] Write box 48 with the eSKD tag `MomsIngAvdr` (it was `MomsIngaende`).
- [x] Use standard BAS accounts in the BAS-Komplett and BAS-Smaforetag
      templates, a journal-level `vat.txt` to override the mapping, and
      `Convert-LedgerChart` for journals created from the earlier templates.
- [x] Correct the special-case rules for negative VMB and other taxable rent,
      using BAS definitions and Skatteverket reference examples.
- [x] Support conversion with a normal multi-row opening balance.
- [x] Validate source and target accounts' effective VAT rules before a
      transfer; reject conflicts rather than changing a user's overrides.
- [x] Validate the transfer date, fiscal year and rows before changing the
      chart or VAT rules. Interrupted multi-file writes are tracked in step 30.

VMB support here is limited to an already calculated positive taxable margin
booked separately on 3211, and exclusion of negative VMB sales on 3212. It does
not calculate margins automatically or implement simplified VMB.

#### 9. Balance check on rounded amounts
Previously `Add-LedgerEntry` rounded only the sum, so rows such as `10.004` and
`-10.001` were accepted and stored although the entry was 0.003 off.

- [x] Reject new row amounts with more than two decimals and sum as decimal.
- [x] Provide an explicit correction path for historical entries with extra
      decimals, without rewriting the original verifications or silently
      rounding their reversals. `Add-LedgerReversal` mirrors the amounts under
      the legacy balance rule and warns; the rule for new manual entries is
      not relaxed.
- [x] Make fiscal-year checks and the file-format contract distinguish legacy
      precision from the stricter rules for new entries.

#### 10. Closed-year guards
- [x] Reuse the fiscal-year guard in `Add-LedgerAttachment`,
      `Remove-LedgerAttachment`, `Remove-LedgerDocument` and
      `Copy-LedgerOpeningBalance` (target year), with regression cases for
      these commands. This is not an exhaustive test of every writing command.
- [x] Keep report input and new documents allowed after closing: the annual
      report and its signed copy are produced after the bookkeeping is closed.
- [x] Reject replacement of existing documents in a closed year, including
      `Add-LedgerDocument -Force`, while still allowing new filenames.

#### 11. Integrity chain robustness and coverage
Implement the locking part together with step 12, not as a separate append lock.

- [x] Protect the integrity read-head-and-append step within the same journal
      lock as verification and attachment writes, sealing and credit rollback.
      The chain remains append-only; interrupted-operation recovery is separate.
- [x] Confirm that duplicate `Verification` records are reported even with
      valid chain hashes, including a repeated key with a different content
      hash. The earlier review mistook the state reader keeping the first seal
      for missing detection; `Test-LedgerIntegrity` already reports duplicates.
- [ ] Seal opening balances and relevant fiscal-year metadata, with an explicit
      lifecycle for legitimate updates and a compatibility plan for old chains.
      A changed opening balance changes every balance in the year.

#### 12. Concurrent writers
Verification numbers come from scanning `ver*.txt` and saved invoice-posting
reservations. Register files (`Add-LedgerFileLine`) are read-modify-write;
writers outside the shared lock can still collide or lose a line.

- [x] Introduce a journal-level lock around verification validation, number
      allocation, content writes and integrity records, including nested calls.
      Attachment changes, sealing, closing and credit rollback participate.
      Lock contention waits up to 30 seconds before returning an explicit error.
- [x] Publish new verifications with create-if-absent conflict detection;
      never silently overwrite a concurrently created verification.
- [x] Add real-process tests for concurrent posting/sealing, lock contention,
      closing while a writer waits and process termination after a file save.
      Document local-filesystem assumptions and retained `.write.lock` files.
- [x] Hold the lock across customer-invoice posting and recovery, from invoice
      validation and reservation through verification sealing and booked status.
- [x] Extend that boundary to customer payments and dependent invoice updates
      (charges, reminders, credit notes), including interest calculation.
      Bank-matching writers use the lock and respect unfinished customer payments.
- [x] Serialize bank-import identity allocation and create-if-absent statement
      writes; reject duplicate bank transaction identities when matching.
- [ ] Extend operation-wide locking and conflict detection to remaining
      registers, invoices, payments, payroll, imports and metadata writers.
      Pair this with recovery in step 30; the first increment is not general
      multi-user support or a consistent reader/backup snapshot (see step 32).

### Shared validation and technical debt

#### 13. One verification reader and consistent validation
Verification files are parsed in more than one place (for example
`Get-LedgerBalance` reads `ver*.txt` itself instead of going through
`Get-LedgerEntry`).

- [ ] Move parsing into one private reader used by every command, so there is
      a single interpretation of the file format.
- [ ] Share validation of decimal precision, exact balance, dates, account
      references and required fields across writing, importing and checking.
      Define explicit errors for malformed input and supported legacy cases.
- [ ] Consider caching the parsed verifications per fiscal year (invalidated
      on write) only after the benchmark in step 18 demonstrates a need.

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
      (management report, income statement, balance sheet, notes), where this
      improves change isolation. Preserve report output with reference cases;
      file size alone is not a release priority.

#### 17. Yearly rates in one place
The employer contribution rate 31.42 % is a default in both
`New-LedgerPayslip` and `Add-LedgerVacationLiability`, and other yearly
values (SRU mapping, tax rates) live in code.

- [ ] Store rates and rule mappings as versioned data with authoritative
      sources and effective-from/to dates, including mid-year changes and
      reduced employer contributions by age.
- [ ] Retain the rule version used for historical calculations; do not
      recalculate old payroll or declarations with today's defaults.

### Testing, CI and documentation

#### 18. Tests
- [x] Independent VAT report/export examples for import VAT, credit notes,
      triangular trade and positive/negative VMB with an explicit mapping
      override. Expected amounts and eSKD order are not derived from the mapping
      implementation; sources are recorded beside the examples.
- [ ] Extend independent reference examples to other tax exports. Internal
      export/import round-trips alone cannot establish accounting correctness.
- [ ] Fault-injection and retry tests for multi-file writes, imports, posting
      and closing, plus concurrent-writer tests for steps 11–12 and 30.
- [ ] Legacy compatibility cases that cover reading, validation and correction,
      not just successful module import.
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
- [x] Add macOS to the test matrix (the README promises macOS support).
- [ ] Run PSScriptAnalyzer on `Tests/` as well.
- [ ] Code coverage report from Pester.
- [ ] Dependabot for GitHub Actions; consider pinning actions by SHA.
- [x] Restore the actual package, run `Test-ModuleManifest`, import in a fresh
      process and check exports plus a bookkeeping flow on all three platforms.
      Gate publication on these checks and publish the verified artifact.
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

#### 21. Period locking
- [ ] Lock a fiscal year per month (for example after the VAT return), so new
      verifications cannot be dated in a locked period. Fits with the
      integrity chain.
- [ ] Apply the same period check to manual entries, imports, reversals and
      indirect posting commands. Define how corrections of submitted periods
      are recorded, together with step 31.

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

#### 30. Interrupted operations and safe retries
Atomic replacement of one file is not a transaction across several files.
Customer-invoice posting now retains a durable plan across the verification and
invoice-status writes. Other multi-file workflows still need equivalent protection.

- [x] Resume customer-invoice posting by repeating `Invoke-LedgerInvoicePosting`.
      Validate before saving an immutable plan with an operation identity,
      reserved verification number and invoice/verification hashes.
- [x] Reuse the matching verification and finish its seal and invoice status;
      stop explicitly on changed inputs, conflicts or integrity damage.
      A saved verification may complete status after year closure, but recovery
      must never create a new verification in a closed year.
- [x] Exercise process termination after plan, verification, seal and status
      writes, plus concurrent retries and interleaved number allocation.
      Preserve recovery records in archive packages and document backup retention.
- [x] Resume customer payments with an optional stable `PaymentId`, including
      replay after completion. Separate IDs allow identical real partial payments;
      unfinished payments block conflicting invoice changes and unrelated bank matching.
      Cover process termination, concurrent same/different IDs, remaining-balance
      validation, closed years, conflicting inputs and archive retention.
- [x] Complete customer-invoice bank matches across payment and bank-state writes.
      Retain bank identity/input hashes in payment plans, resume before heuristics,
      reserve verifications for their originating transaction, and preserve
      ownership through Reset. Cover interruption, later invoice/statement changes,
      identical real payments, conflicts, concurrency and archive retention.
- [ ] Extend bank-matching recovery to supplier payments and rule/account postings,
      including both sides of own-account transfers.
- [ ] Define recoverable operation boundaries for remaining invoice/payment/payroll
      posting, SIE import, chart conversion and fiscal-year closing.
- [ ] Extend durable operation identity and progress to those workflows without
      losing or duplicating bookkeeping.
- [ ] Validate their complete plans before the first write; report partial failures
      with actionable recovery instructions instead of a success-shaped result.
- [ ] Integrate their recovery with the locks and integrity chain in steps 11–12.

#### 31. Reproducible declarations and final reports
The journal-wide `vat.txt` can change how old periods are reported. Closing
bookkeeping is also distinct from finalising and signing the annual report.

- [ ] Save each final declaration/report with its period, input snapshot,
      effective mapping/rule versions and PSLedger version.
- [ ] Retain submitted versions and link corrections to the version corrected;
      never silently replace a historical submission with a regenerated report.
- [ ] Define finalisation separately from fiscal-year closing, and include
      report versions and supporting metadata in archive packages.

#### 32. Multi-user workflows
- [ ] Define the supported deployment and storage model before promising
      multi-user operation; build on steps 11–12 and 30.
- [ ] Record who performed each operation with a documented identity/trust
      model. An actor field in a hash chain is not authentication by itself.

#### Other ideas
- E-invoicing (Peppol BIS Billing / Svefaktura) for customer invoices.
- Budget and forecast per account and object.
- Fixed asset register (anläggningsregister) driving `Add-LedgerDepreciation`.
- Importing supplier invoices from PDF/e-invoice files.
- Recurring invoices (subscriptions) and invoice number series.
- Cash sales and kassabok for businesses with cash registers.
- Enskild firma (NE-bilaga) and ekonomisk förening.
- Inventory (lager) with stock valuation.
