# Changelog

## [Unreleased]

### Added
- **Income tax return export (inkomstdeklaration 2, SRU).**
  `Export-LedgerIncomeTaxReturn` writes a fiscal year as a Skatteverket SRU
  submission — the two files `INFO.SRU` (submitter metadata) and `BLANKETTER.SRU`
  (declaration blocks) — that can be uploaded in the filöverföringstjänst. It
  produces the three blankett blocks for an aktiebolag: **INK2R** (räkenskapsschema),
  derived automatically from the trial balance via the official BAS→SRU mapping;
  **INK2** (huvudblankett) with the fiscal year dates and the surplus/deficit; and
  **INK2S** (skattemässiga justeringar) with årets resultat, the non-deductible
  booked income tax and any adjustments supplied via `-TaxAdjustment`, ending in
  fields 8020/8021. Balance-sheet assets are reported with their natural sign,
  equity/liabilities and income-statement lines are negated to SRU sign
  conventions, and årets resultat is folded into fritt eget kapital so the balance
  sheet ties out. Amounts are whole kronor (öre truncated), the organisation
  number is written in 12-digit form and the files use ISO-8859-1 encoding, as the
  format requires. Submitter postal code/city (mandatory in INFO.SRU) come from
  `-PostalCode`/`-City` or the journal metadata. See
  [docs/Inkomstdeklaration.md](docs/Inkomstdeklaration.md).
- **VAT declaration export (momsdeklaration).** `Export-LedgerVatDeclaration`
  writes a period's VAT report as a Skatteverket eSKD file
  (`<eSKDUpload Version="6.0">`) that can be uploaded in the e-service *Lämna
  momsdeklaration via fil*. It reuses `Get-LedgerVatReport`, reads the company
  organisation number from the journal metadata and emits one XML element per
  declaration box — ruta 05 (`ForsMomsEjAnnan`), 10 (`MomsUtgHog`), 11
  (`MomsUtgMedel`), 12 (`MomsUtgLag`), 48 (`MomsIngaende`) and the derived 49
  (`MomsBetala`, output − input VAT). Amounts are reported in whole kronor and the
  file is written with ISO-8859-1 encoding as the format requires. The reporting
  period defaults to the month of `-ToDate` and can be overridden with `-Period`
  (YYYYMM); `-Force` overwrites an existing file.

## [0.9.0] - 2026-08-31

### Added
- **Invoice management (fakturahantering).** A customer register plus a customer
  invoice workflow layered on top of the ledger. `Add-LedgerCustomer`,
  `Get-LedgerCustomer` and `Set-LedgerCustomer` manage a `customers.txt` register
  (kundnummer, namn, org.nr, e-post, betalningsvillkor). `New-LedgerInvoice`
  creates a draft invoice (stored under `invoices/`), `Invoke-LedgerInvoicePosting`
  posts it to the ledger (debit 1510 Kundfordringar, credit revenue and output VAT)
  and `Add-LedgerInvoicePayment` registers full or partial payments (debit 1930/kassa,
  credit 1510). Each invoice tracks its status (Draft → Booked → Partial → Paid) and
  the verifications it created, so open receivables always reconcile against the
  general ledger. `Get-LedgerInvoice` lists invoices with computed totals and an
  `-Unpaid` filter for open receivables. `Get-LedgerAccountsReceivable` reports
  open receivables with aging buckets (Current / 1-30 / 31-60 / 61-90 / 90+ days)
  and a `-Summary` per-bucket total. `Export-LedgerInvoice` exports a single invoice
  as a printable document — PDF (via a built-in dependency-free PDF writer), Word,
  Markdown or plain text — including seller, customer, rows, VAT, totals and payment
  details from journal metadata (bankgiro/plusgiro/IBAN/BIC). `Add-LedgerCreditInvoice`
  credits (reverses) a posted, unpaid invoice: it books the reversing verification and
  marks both the original and the new credit note `Credited` so the receivable nets to
  zero. See [docs/Fakturahantering.md](docs/Fakturahantering.md).
- **Payment reminders and OCR references.** `Add-LedgerInvoiceReminder` records a
  payment reminder on a posted, unpaid invoice (incrementing `ReminderCount` and
  setting `LastReminderDate`) and can optionally write a reminder document — PDF,
  Word, Markdown or plain text — showing the overdue amount, an optional reminder
  fee (document-only, not booked) and the invoice OCR reference. Every invoice now
  exposes an `OcrReference`: a Swedish OCR number derived from the invoice number
  with a Luhn (mod-10) check digit and a length-control digit, printed on exported
  invoices and reminders for automatic payment matching.
- **Booked late charges (fees and interest).** `Add-LedgerInvoiceFee` books a
  reminder fee or late-payment compensation (påminnelseavgift / förseningsersättning)
  and `Add-LedgerInvoiceInterest` calculates and books late-payment interest
  (dröjsmålsränta = remaining amount × annual rate × days overdue / 365, or an
  explicit amount) on a posted, unpaid invoice. Each charge debits the receivable
  and credits an income account (3590 for fees, 8310 for interest; no VAT) and is
  recorded in a new `Charges` section on the invoice, so it increases the invoice
  total and the open receivable while staying reconciled against the general ledger.
  `Add-LedgerInvoiceReminder` gains a `-BookFee` switch to book the reminder fee as
  it is issued.
- **Supplier ledger (leverantörsreskontra).** A supplier register plus a supplier
  invoice workflow that mirrors the customer ledger. `Add-LedgerSupplier`,
  `Get-LedgerSupplier` and `Set-LedgerSupplier` manage a `suppliers.txt` register.
  `New-LedgerSupplierInvoice` registers a draft supplier invoice (stored under
  `supplierinvoices/`, capturing the supplier's own invoice number and payment
  reference), `Invoke-LedgerSupplierInvoicePosting` posts it (debit cost accounts
  and input VAT 2640, credit 2440 Leverantörsskulder) and `Add-LedgerSupplierPayment`
  registers full or partial payments (debit 2440, credit 1930). `Get-LedgerSupplierInvoice`
  lists supplier invoices with an `-Unpaid` filter and `Get-LedgerAccountsPayable`
  reports open payables with aging buckets (Current / 1-30 / 31-60 / 61-90 / 90+ days)
  and a `-Summary` per-bucket total. See
  [docs/Leverantorsreskontra.md](docs/Leverantorsreskontra.md).
- **Full årsredovisning (annual report) support.** `Export-LedgerAnnualReport` now
  renders a complete K2 (BFNAR 2016:10) annual report for a small limited company —
  förvaltningsberättelse (verksamhet, väsentliga händelser, flerårsöversikt, förslag
  till vinstdisposition), resultaträkning och balansräkning with a Not column and a
  comparison year, noter (redovisningsprinciper, medelantal anställda, and
  auto-detected notes for anläggningstillgångar, aktier och andelar och eget kapital)
  and underskrifter with a fastställelseintyg. A new `-Format Word` option writes a
  `.docx` document (dependency-free Open XML package) in addition to `Text` and
  `Markdown`.
- `Set-LedgerReportInput` / `Get-LedgerReportInput` store and read year-specific
  narrative and decision data (väsentliga händelser, föreslagen utdelning, medelantal
  anställda, marknadsvärde för värdepapper, ort/datum för underskrift) in an optional
  per-year `report.txt` file, in the same spirit as `ib.txt`.
- `Get-LedgerCompanyProfile` collects the stable company information used in an annual
  report (säte, verksamhetsföremål, antal aktier, aktiekapital, styrelseledamöter)
  from the journal metadata.
- `Get-LedgerMultiYearOverview` produces a flerårsöversikt (nettoomsättning, resultat
  efter finansiella poster, årets resultat, balansomslutning) over several years.
- `Get-LedgerEquityReconciliation` builds the förändring av eget kapital note, and
  `Get-LedgerProfitDisposition` computes the förslag till vinstdisposition (including
  utdelning per aktie).
- `Get-LedgerFixedAssetNote`, `Get-LedgerShareholdingNote` and `Get-LedgerEmployeeNote`
  produce the anläggnings-, värdepappers- respektive personalnoter.
- `Get-LedgerAccountingPrinciples` returns the standard K2 redovisnings- och
  värderingsprinciper text.

### Changed
- `Get-LedgerBalanceSheet` gained a `-Detailed` switch that splits eget kapital into
  Aktiekapital, Bundna reserver, Balanserat resultat och Årets resultat and short-term
  liabilities into Aktuella skatteskulder och Övriga skulder. The aggregate lines are
  still returned, so the extra rows are additive.

## [0.8.0] - 2026-07-03

### Changed
- `Add-LedgerAttachment` now accepts multiple files in a single call — `-Path`
  takes an array (e.g. `-Path .\faktura.pdf, .\kvitto.jpg`). All source files are
  validated before any are copied/moved, and one result object is returned per
  file.

### Added
- `Backup-LedgerJournal` creates a timestamped zip backup of a journal
  (`<Name>_yyyy-MM-dd_HHmmss.zip`). Backups go to a `backups` folder next to the
  journal by default (override with `-DestinationPath`), and the five most recent
  are retained (`-KeepCount`, `0` keeps all). Supports `-WhatIf`/`-Confirm` and
  does not enforce the schema version, so a backup can be taken before
  `Update-LedgerJournal`.
- `Restore-LedgerJournal` extracts a backup archive, recreating the journal
  directory in the destination (default: current directory). Validates the
  archive contains a single journal folder with `journal.txt`, refuses to
  overwrite an existing journal unless `-Force` is given, and supports
  `-WhatIf`/`-Confirm`.
- `Add-LedgerEntry` gained an optional `-Attachment` parameter that attaches one
  or more files to the verification as it is created (delegating to
  `Add-LedgerAttachment`). Attachment files are validated before the verification
  is written, so a missing file leaves no partial verification behind.
- `Add-LedgerEntry` gained a `-PassThru` switch that returns an object describing
  the created verification (`VerificationNumber`, `FiscalYear`, `Date`,
  `Description`, `Path`, `Attachments`). Without `-PassThru` the command remains
  silent, preserving existing behaviour.

## [0.7.0] - 2026-07-01

### Changed
- **Opening balances (ingående balans) are now stored as metadata, not as a
  verification.** Each fiscal year keeps its opening balance in an `ib.txt` file
  (tab-separated `account\tamount`, signed like SIE `#IB`) instead of a
  `ver0001.txt` verification with the description `Ingående balans`. As a result,
  imported and regular verifications keep their source numbering
  (`ver0001..verN`) instead of being shifted by one. This affects:
  - `Import-LedgerSie` — writes `#IB` (year index `0`) to `ib.txt`; `#VER`
    records import as `ver0001..verN`.
  - `Copy-LedgerOpeningBalance` — writes `ib.txt` in the target year (and now
    refuses only if an opening balance already exists, independent of
    verifications).
  - `Get-LedgerBalance` / `Get-LedgerLedger` — read the opening balance from
    `ib.txt`.
- `Export-LedgerSie` now emits proper balance metadata: opening balances
  (`#IB`), closing balances for balance-sheet accounts (`#UB`) and the period
  result for result accounts (`#RES`). The opening balance is no longer exported
  as a `#VER`.

### Added
- `Set-LedgerJournal` — updates the company `Name`, `OrgNumber` and/or arbitrary
  metadata fields in an existing journal's `journal.txt` after creation. Only the
  supplied fields change; comments and the `SchemaVersion` are preserved. Passing
  an empty `-OrgNumber` (or an empty metadata value) removes the field. Supports
  `-WhatIf`/`-Confirm`.
- **Free-form company metadata** — `New-LedgerJournal` and `Set-LedgerJournal`
  accept a `-Metadata` hashtable for extra company fields (e.g.
  `@{ VatNumber = 'SE556677889901' }`), stored as `Key: Value` lines in
  `journal.txt`. `Get-LedgerJournal` exposes them via a `Metadata` property
  (e.g. `$journal.Metadata.VatNumber`). Reserved keys (`Name`, `OrgNumber`,
  `SchemaVersion`) use their dedicated parameters.
- **Journal schema versioning** — each journal now records a `SchemaVersion`
  field in `journal.txt`, and the module knows which on-disk format version it
  supports. Writing commands refuse to operate on an out-of-date journal and
  point to the exact migration command to run; reading commands still work but
  emit a one-time warning per journal. Journals from newer module versions are
  likewise flagged with a prompt to upgrade. `Get-LedgerJournal` now exposes the
  `SchemaVersion` property (legacy journals without the field report version 1).
- `Update-LedgerJournal` — evergreen migration command that brings a journal up
  to the schema version this module supports by applying every pending migration
  step, then stamping the journal with the current `SchemaVersion`. The first
  step (v1 → v2) extracts each `Ingående balans` verification into `ib.txt`,
  deletes it, and renumbers the remaining verifications (and their attachment
  directories) down by one. Idempotent and supports `-WhatIf`.

### Breaking
- Journals created with earlier versions must be migrated with
  `Update-LedgerJournal` before writing commands will operate on them.
  Writing to an un-migrated journal now fails with a message naming the
  migration command; reading still works but warns. This also fixes the previous
  behaviour where opening balances were no longer detected from a verification.

## [0.6.0] - 2026-06-30

### Added
- **Fiscal-year documents** — store general supporting material (underlag) that
  is scoped to a whole fiscal year rather than a single verification, e.g. a bank
  statement (kontoutdrag) backing several entries. Files live in a `documents/`
  subdirectory of the fiscal year:
  - `Add-LedgerDocument` — copies (or moves) a file into the fiscal year's
    `documents/` directory (created on demand)
  - `Get-LedgerDocument` — lists documents for a fiscal year; supports a
    `-FileName` wildcard filter and accepts fiscal year pipeline input
  - `Remove-LedgerDocument` — deletes a document; cleans up the empty
    directory; supports `-WhatIf`

### Changed
- Removed the `Name` alias from the `-FiscalYear` parameter of the attachment
  commands (`Add-/Get-/Remove-LedgerAttachment`). The alias shadowed `-Name` so
  it could no longer be mistaken for a file-name filter and conflict with an
  explicit `-FiscalYear`. Pipeline binding still works via the `FiscalYear`
  property. `Remove-LedgerAttachment` now also binds `-VerificationNumber` and
  `-FileName` from the pipeline, so `Get-LedgerAttachment | Remove-LedgerAttachment`
  works directly.
- Renamed the session-state journal commands so they no longer look like a
  getter/setter pair with the disk-reading `Get-LedgerJournal`. The session
  "current journal" trio now uses a dedicated `CurrentJournal` noun:
  - `Set-LedgerJournal` → `Set-LedgerCurrentJournal`
  - `Clear-LedgerJournal` → `Clear-LedgerCurrentJournal`
  - `Get-LedgerJournal -Current` → `Get-LedgerCurrentJournal`
  `Get-LedgerJournal` is now a pure metadata reader and only accepts `-Path`.
  This is a breaking change; update scripts to the new command names.
- `Get-LedgerIncomeStatement` now returns a detailed resultaträkning instead of
  seven summary rows. Revenue is split into Nettoomsättning and Övriga
  rörelseintäkter; costs into Material- och varukostnader, Övriga rörelsekostnader
  m.m, Personalkostnader and Avskrivningar, with running subtotals for
  Rörelseresultat efter avskrivningar, Finansiella intäkter och kostnader,
  Resultat efter finansiella poster, Övriga poster, Skatt and Årets resultat.
  Each object gains a `Section` property.
- `Get-LedgerBalanceSheet` now returns a detailed balansräkning instead of two
  summary rows. Assets are split into Anläggningstillgångar, Lager och pågående
  arbeten, Kundfordringar, Övriga kortfristiga fordringar and Likvida medel;
  equity and liabilities into Eget kapital, Resultat (the unclosed result for the
  year from account classes 3-8), Obeskattade reserver och avsättningar,
  Långfristiga skulder and Kortfristiga skulder. Each section ends with a total
  row. Amounts now carry their natural sign (assets positive, equity/liabilities
  negative) and each object gains a `Section` property.

### Fixed
- The bundled `BAS-Komplett` chart template used non-standard BAS numbering for
  year-end appropriations and extraordinary items: bokslutsdispositioner were at
  8500-8590 and extraordinära poster at 8810-8820. They are now corrected to
  standard BAS (bokslutsdispositioner 8800-8890, extraordinära 8710-8750) so they
  are classified correctly in `Get-LedgerIncomeStatement` — bokslutsdispositioner
  under Övriga poster (account group 88) and extraordinära poster under
  Finansiella intäkter och kostnader (account groups 80-87).
- `Get-LedgerIncomeStatement` now excludes account 8999 (Årets resultat) from the
  Skatt line and Årets resultat total. Previously, if a year-end result
  appropriation had been booked to 8999 (e.g. imported from another system), it
  was counted as tax and zeroed out the reported result.

## [0.5.0] - 2026-06-23

### Changed
- `Import-LedgerSie` now refuses to auto-create a fiscal year (from `#RAR 0`)
  that would leave a gap in the journal's fiscal year series, i.e. a year that
  is not contiguous with the existing years. The error reports the missing date
  range. `-Force` bypasses the guard for intentional out-of-order imports.
- `Import-LedgerSie` now refuses to import into a fiscal year that already
  contains verifications, preventing accidental double-imports that would
  duplicate all entries. A new `-Force` switch overrides the guard for
  intentional re-imports.
- `Get-LedgerLedger` now shows the opening balance (from the 'Ingående balans'
  verification) as a leading row (ingående saldo) and starts the running balance
  from it, instead of listing it as an ordinary transaction. The opening balance
  is excluded from the period Debit/Credit columns. When `-FromDate` is set, the
  opening row reflects the carried-forward balance at that date (opening balance
  plus transactions dated before `-FromDate`).
- `Get-LedgerBalance` now reports the opening balance separately. Each account
  object gains an `OpeningBalance` field (from the 'Ingående balans' verification),
  while `Debit`/`Credit` now reflect period transactions only. `Balance` remains
  the closing balance (`OpeningBalance + Debit - Credit`), so it matches the
  ingående saldo / debet / kredit / utgående saldo layout used by accounting
  software.

### Fixed
- `Import-LedgerSie` now tolerates a small rounding difference (öresdifferens) in
  the opening balances (`#IB`): if the rows do not sum to zero but the difference
  is within `-RoundingTolerance` (default 1.00), it is posted to `-RoundingAccount`
  (default BAS 3740, Öres- och kronutjämning) so the opening balance entry
  balances. Larger differences still abort the import. The result object reports
  the adjustment as `OpeningBalanceRounding`. Also fixes the floating-point noise
  previously shown in the imbalance error (the sum is now computed in decimal).
- `Import-LedgerSie` now imports opening balances (`#IB` records for the current
  year, year index `0`) as the first verification (`ver0001.txt`) with the
  description `Ingående balans`. Previously only `#VER` records were imported, so
  balance-sheet accounts lost their opening balance and `Get-LedgerBalance`
  showed only the current year's transactions. The result object gains an
  `ImportedOpeningBalance` flag.

## [0.4.1] - 2026-05-28

### Changed
- `Import-LedgerSie` now auto-detects the fiscal year from the SIE file's
  `#RAR 0` record when `-FiscalYear` is omitted, and creates the fiscal year
  automatically if it does not exist in the journal.

### Fixed
- Relative file paths (e.g. `2007-2008.SE`) now resolve correctly against
  PowerShell's `$PWD` instead of the .NET process working directory.
- Balance check no longer fails on floating-point rounding residuals when
  importing verifications with many rows.

## [0.4.0] - 2026-05-28

### Added
- **Custom extensions** — load user-defined `.ps1` functions into PSLedger:
  - Extensions loaded from `$env:PSLEDGER_EXTENSIONS` (semicolon-separated paths)
  - Extensions loaded from `$HOME\.psledger\Extensions\` (or
    `$env:PSLEDGER_USER_EXTENSIONS`)
  - Per-journal extensions loaded from `<journal>\Extensions\` when
    `Set-LedgerJournal` is called
  - Env/User extensions are dot-sourced into the module scope (access to
    internal helpers); journal extensions run in global scope
  - Broken extensions emit a warning and don't prevent the module from loading
  - `Get-LedgerExtension` — lists all loaded extensions with source and
    function names; optional `-Source` filter
- **Current journal session state** — optional complement to stateless
  `-JournalPath`:
  - `Set-LedgerJournal -Path <path>` — sets the session default journal,
    validates it, and loads per-journal extensions
  - `Clear-LedgerJournal` — clears the default and unloads journal extensions
  - `Get-LedgerJournal -Current` — returns metadata for the current journal
- **Fiscal year navigation** — pipeline-ready functions for iterating fiscal years:
  - `Get-LedgerFirstFiscalYear` — returns the oldest fiscal year
  - `Get-LedgerLatestFiscalYear` — returns the most recent fiscal year
  - `Get-LedgerLatestOpenFiscalYear` — returns the most recent open fiscal year
  - `Get-LedgerNextFiscalYear` — returns the next fiscal year (pipeline input)
- **Attachments** — associate files (invoices, receipts) with verifications:
  - `Add-LedgerAttachment` — copies (or moves) a file into the verification's
    attachment directory (`ver0001/`, created on demand)
  - `Get-LedgerAttachment` — lists attachments per verification or all;
    accepts pipeline input from `Get-LedgerEntry`
  - `Remove-LedgerAttachment` — deletes an attachment; cleans up empty
    directory; supports `-WhatIf`

### Changed
- All 26 public commands that previously required `-JournalPath` now accept it
  as optional — when omitted, the current journal set via `Set-LedgerJournal`
  is used. If neither is provided, a clear error message guides the user.
- All 13 commands with `-FiscalYear` now accept it as optional — when omitted,
  the latest fiscal year is used automatically. The parameter also accepts
  pipeline input via `ValueFromPipelineByPropertyName` (binds to the `Name`
  property of fiscal year objects).
- `Import-LedgerSie` now auto-detects the fiscal year from the SIE file's
  `#RAR 0` record when `-FiscalYear` is omitted, and creates the fiscal year
  automatically if it does not exist in the journal.
- Module manifest `FunctionsToExport` changed to `'*'` to support dynamic
  extension loading; actual export list is controlled by `Export-ModuleMember`
  in the `.psm1`.

## [0.3.0] - 2026-05-28

### Added
- **General ledger** (`Get-LedgerLedger`) — chronological per-account view with
  running balance, date filtering via `-FromDate`/`-ToDate`
- **VAT report** (`Get-LedgerVatReport`) — maps BAS accounts to Skatteverkets
  momsdeklaration boxes (05, 10, 11, 12, 48, 49) with period filtering
- **Dimensions and objects**:
  - `Add-LedgerDimension` / `Get-LedgerDimension` — manage cost centre/project
    dimensions stored in `dimensions.txt`
  - `Add-LedgerObject` / `Get-LedgerObject` — manage objects within dimensions
    stored in `objects.txt`
  - `Add-LedgerEntry` extended with optional `Objects` hashtable per row
    (format: `@{1='sthlm'; 2='proj-a'}`)
  - `Get-LedgerEntry` returns `Objects` property on each row
  - Backward-compatible file format: third tab-field `{dim:obj,...}` is optional
- **SIE 4 dimension support**:
  - `Export-LedgerSie` writes `#DIM`, `#OBJEKT` and object tags on `#TRANS`
  - `Import-LedgerSie` parses and imports dimensions, objects and row tags
  - `Test-LedgerSie` validates object references against declared dimensions
- **Accruals** (`Add-LedgerAccrual`) — creates coupled accrual + reversal
  verifications across fiscal years with cross-reference descriptions
- **Recurring entries**:
  - `New-LedgerRecurringEntry` — create monthly templates in `recurring/` dir
  - `Get-LedgerRecurringEntry` — list or filter templates
  - `Remove-LedgerRecurringEntry` — delete a template
  - `Invoke-LedgerRecurringEntry` — idempotent generation of verifications
    from templates through a specified date

### Changed
- Verification row file format extended (backward-compatible) to support
  object tags as optional third tab-separated field
- `Export-LedgerSie` / `Import-LedgerSie` / `Test-LedgerSie` enhanced for
  full dimension/object round-trip support

## [0.2.0] - 2026-05-28

### Added
- `Export-LedgerSie` — export a fiscal year to a SIE 4E file (CP437/PC-8 encoded)
  - Writes `#FLAGGA`, `#PROGRAM`, `#FORMAT PC8`, `#GEN`, `#SIETYP 4`, `#FNAMN`,
    `#ORGNR`, `#RAR`, `#KONTO`, `#VER`/`#TRANS` blocks
  - `-Force` to overwrite an existing destination file
- `Import-LedgerSie` — import verifications from a SIE 4 file into a journal
  - Validates the file before importing (no partial writes)
  - Requires the target fiscal year to exist and be open
  - `-CreateMissingAccounts` adds referenced accounts automatically using
    names from the SIE file's `#KONTO` records
  - Returns a summary object with `ImportedEntries`
- `Test-LedgerSie` — validate a SIE file without importing
  - Checks `#VER` balance, account references and duplicate verification numbers
  - Warns on missing or unexpected `#SIETYP`
  - Returns a result object with `IsValid`, `Errors`, `Warnings` and counts
- Internal CP437 encoding helpers and a SIE tokenizer/parser in `Private/`
- Decimal amounts are read tolerantly (`.` or `,`) and written with `.` and
  invariant culture

## [0.1.0] - Unreleased

### Added
- `New-LedgerJournal` — create a journal directory with company metadata
- `Get-LedgerJournal` — read journal information
- `Add-LedgerAccount` — add a single account to the chart of accounts
- `Get-LedgerAccount` — list or look up accounts in the chart
- `Import-LedgerChart` — import chart of accounts from built-in templates or external file
  - Built-in templates: BAS-Mini (~30), BAS-Smaforetag (~70), BAS-Komplett (~250)
  - `-ListAvailable` to discover templates
  - `-Force` to replace existing chart
- `New-LedgerFiscalYear` — create a fiscal year directory
- `Get-LedgerFiscalYear` — list fiscal years with status
- `Close-LedgerFiscalYear` — lock a fiscal year, preventing new entries
- `Add-LedgerEntry` — create a balanced verification with validations:
  - Double-entry balance enforcement (sum must be zero)
  - Account existence check against chart of accounts
  - Date-within-fiscal-year validation
  - Closed-year protection
- `Get-LedgerEntry` — query verifications with filters:
  - `-VerificationNumber` for specific entry
  - `-Account` for entries involving a specific account
  - `-FromDate` / `-ToDate` for date range filtering
- `Add-LedgerReversal` — create a correction entry with negated amounts
- `Get-LedgerBalance` — trial balance (saldobalans) per account
- `Get-LedgerIncomeStatement` — income statement grouped by revenue, costs, operating expenses, financial items
- `Get-LedgerBalanceSheet` — balance sheet showing assets vs equity and liabilities
- `Copy-LedgerOpeningBalance` — roll over closing balances to a new fiscal year (including year's result to account 2099)

