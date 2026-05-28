# Changelog

## [0.2.0] - Unreleased

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

