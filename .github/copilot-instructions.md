# Copilot Instructions for PSLedger

## Build & Test

```powershell
# Run all tests
Invoke-Pester ./Tests

# Run tests for a single function
Invoke-Pester ./Tests/Add-LedgerEntry.Tests.ps1

# Run a specific test by name filter
Invoke-Pester ./Tests -Filter @{ FullName = '*Should create a verification file*' }
```

No build step — this is a script module loaded directly via `Import-Module ./PSLedger/PSLedger.psd1`.

### Test dependencies

Tests require two external modules from the same author:

- **TDDUtils** — provides `Test-TDDCmdletBinding` and similar assertion helpers
- **TDDSeams** — provides mockable seam infrastructure

## Architecture

PSLedger is a double-entry bookkeeping system that stores all data as **plain text files** in a directory hierarchy:

```
<journal>.ledger/
├── journal.txt          # Metadata (Name, OrgNumber, SchemaVersion)
├── accounts.txt         # Chart of accounts (tab-separated: number\tname)
└── <yyyy-MM>_<yyyy-MM>/ # Fiscal year directory
    ├── year.txt         # StartDate, EndDate, Status
    ├── ib.txt           # Opening balance metadata (tab-separated: number\tamount), optional
    ├── ver0001.txt      # Verification (entry) files
    └── ver0002.txt
```

Key domain concepts:
- **Journal** — the top-level container (one per company/organisation)
- **Fiscal year** — a date range; directory named `{StartYYYY-MM}_{EndYYYY-MM}`
- **Verification** — a balanced ledger entry; auto-numbered `ver0001.txt`, `ver0002.txt`, etc.
- **Opening balance** (`ib.txt`) — ingående balans stored as metadata (like SIE `#IB`), **not** as a verification, so verification numbers match the source system
- **Schema version** — `journal.txt` records a `SchemaVersion`; writing commands throw on out-of-date journals (naming the migration command), reading commands warn. Bump `$script:CurrentSchemaVersion` and register a migration in `Private/JournalSchema.ps1` when the on-disk format changes
- **Chart of accounts** (`accounts.txt`) — flat file of account numbers and names

All entries enforce **double-entry balance** — the sum of all row amounts must equal zero.

## Module conventions

- Standard PowerShell module layout: `PSLedger.psm1` dot-sources files from `Public/`; the `Private/` folder is reserved for internal helpers.
- All public functions use `[CmdletBinding()]` and mandatory parameters.
- Functions follow the verb-noun pattern with the `Ledger` noun prefix (e.g., `New-LedgerJournal`, `Add-LedgerEntry`).
- File encoding is always **UTF-8** (supporting Swedish characters like å, ä, ö).
- Tab characters (`\t`) are the field delimiter in `accounts.txt` and verification row data.

## Test conventions

- One test file per public function, named `<FunctionName>.Tests.ps1` in `Tests/`.
- Tests are structured with two contexts: **Function metadata** (parameter types, mandatory flags, CmdletBinding) and **Behavior** (actual logic).
- Tests use Pester's `$TestDrive` for isolated file system operations.
- Each test imports the module fresh with `Import-Module ... -Force` in `BeforeAll`.

## Documentation conventions

- All public functions must have comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`).
- Include at least two `.EXAMPLE` blocks per function — one simple, one more realistic.
- Examples should use Swedish company names and BAS account numbers to reflect real-world usage.
- Help text is written in English.
