# Changelog

## [Unreleased]

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

