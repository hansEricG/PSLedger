# Changelog

## [Unreleased]

### Changed
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

