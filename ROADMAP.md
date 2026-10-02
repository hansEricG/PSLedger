# Roadmap to PSLedger 1.0

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

- [ ] Write a file format specification covering every file (journal, accounts,
      verifications, ib, holdings, report, dimensions/objects, customers,
      invoices, suppliers, employees, payslips, bank, time).
- [ ] Document when `SchemaVersion` is bumped: from 1.0 every breaking change
      needs an `Invoke-Ledger*Migration` step and `Update-LedgerJournal` support.

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

- [ ] `Test-LedgerIntegrity`: checksums or a hash chain per verification so
      changes to posted entries can be detected (supports the permanence
      requirement, varaktighet).

### 7. Archiving
- [ ] Export a closed fiscal year as an archive package (SIE, PDF/Markdown
      reports and all supporting documents) suitable for seven years' storage.

## Later (1.x)

- VAT return and employer declaration (AGI) submitted directly to Skatteverket.
- Foreign currency on customer and supplier invoices.
- Period locking (per month) and multi-user workflows.
