# PSLedger

A simple command-line double-entry bookkeeping system built as a PowerShell module, using plain text files as storage. Designed for Swedish small businesses following the BAS account structure.

## Features

- **Plain text storage** — all data in readable `.txt` files, version-controllable with Git
- **Double-entry enforcement** — every entry must balance (debit = credit)
- **BAS chart templates** — built-in Swedish account plans (Mini, Småföretag, Komplett)
- **Validation** — account existence, date range, closed-year protection
- **Reports** — trial balance, income statement, balance sheet, general ledger, VAT report
- **Year-end workflow** — close fiscal year, copy opening balances
- **Corrections** — reversal entries following Swedish bookkeeping law
- **SIE 4 import/export** — exchange data with other Swedish accounting systems (incl. dimensions)
- **Dimensions & objects** — cost centres, projects with SIE round-trip support
- **Accruals** — automated accrual + reversal across fiscal years
- **Recurring entries** — monthly templates with idempotent auto-generation
- **Custom extensions** — load your own functions from `$HOME\.psledger\Extensions\` or per-journal
- **Current journal** — set a session default to skip `-JournalPath` on every call

## Quick Start

```powershell
Import-Module PSLedger

# 1. Create a journal
New-LedgerJournal -Path .\MinFirma.ledger -Name 'MinFirma AB' -OrgNumber '556677-8899'

# 2. Set it as current (optional — saves typing -JournalPath on every command)
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

# 3. Import a chart of accounts
Import-LedgerChart -Template 'BAS-Smaforetag'

# 4. Create a fiscal year
New-LedgerFiscalYear -StartDate '2024-01-01' -EndDate '2024-12-31'

# 5. Add entries
$rows = @(
    @{ Account = '1910'; Amount = 50000 }
    @{ Account = '3040'; Amount = -50000 }
)
Add-LedgerEntry -FiscalYear '2024-01_2024-12' `
    -Date '2024-03-15' -Description 'Konsultarvode faktura #101' -Rows $rows

# 6. View reports
Get-LedgerBalance -FiscalYear '2024-01_2024-12' |
    Format-Table AccountNumber, AccountName, Debit, Credit, Balance

# 7. Year-end
Close-LedgerFiscalYear -FiscalYear '2024-01_2024-12'
New-LedgerFiscalYear -StartDate '2025-01-01' -EndDate '2025-12-31'
Copy-LedgerOpeningBalance -FromFiscalYear '2024-01_2024-12' -ToFiscalYear '2025-01_2025-12'
```

## Commands

| Command | Description |
|---------|-------------|
| `New-LedgerJournal` | Create a new journal (company) |
| `Get-LedgerJournal` | Read journal metadata |
| `Import-LedgerChart` | Import chart of accounts from template or file |
| `Add-LedgerAccount` | Add a single account to the chart |
| `Get-LedgerAccount` | List or look up accounts |
| `New-LedgerFiscalYear` | Create a fiscal year |
| `Get-LedgerFiscalYear` | List fiscal years |
| `Close-LedgerFiscalYear` | Lock a fiscal year (no more entries) |
| `Add-LedgerEntry` | Create a verification (journal entry) |
| `Get-LedgerEntry` | Query entries with optional filters |
| `Add-LedgerReversal` | Correct an entry via reversal |
| `Get-LedgerBalance` | Trial balance (saldobalans) |
| `Get-LedgerIncomeStatement` | Income statement (resultaträkning) |
| `Get-LedgerBalanceSheet` | Balance sheet (balansräkning) |
| `Copy-LedgerOpeningBalance` | Roll over balances to a new year |
| `Export-LedgerSie` | Export a fiscal year to a SIE 4E file |
| `Import-LedgerSie` | Import verifications from a SIE 4 file |
| `Test-LedgerSie` | Validate a SIE file without importing |
| `Get-LedgerLedger` | General ledger (huvudbok) per account |
| `Get-LedgerVatReport` | VAT declaration report (momsdeklaration) |
| `Add-LedgerDimension` | Add a dimension (e.g. cost centre, project) |
| `Get-LedgerDimension` | List dimensions |
| `Add-LedgerObject` | Add an object to a dimension |
| `Get-LedgerObject` | List objects |
| `Add-LedgerAccrual` | Create accrual + automatic reversal |
| `New-LedgerRecurringEntry` | Create a recurring entry template |
| `Get-LedgerRecurringEntry` | List recurring entry templates |
| `Remove-LedgerRecurringEntry` | Remove a recurring entry template |
| `Invoke-LedgerRecurringEntry` | Generate entries from templates |
| `Set-LedgerCurrentJournal` | Set session default journal (skip `-JournalPath`) |
| `Clear-LedgerCurrentJournal` | Clear session default journal |
| `Get-LedgerCurrentJournal` | Read metadata for the current session journal |
| `Get-LedgerExtension` | List loaded custom extensions |
| `Get-LedgerFirstFiscalYear` | Get the oldest fiscal year |
| `Get-LedgerLatestFiscalYear` | Get the most recent fiscal year |
| `Get-LedgerLatestOpenFiscalYear` | Get the most recent open fiscal year |
| `Get-LedgerNextFiscalYear` | Get the next fiscal year (pipeline-ready) |
| `Add-LedgerAttachment` | Attach a file to a verification |
| `Get-LedgerAttachment` | List attachments for a verification |
| `Remove-LedgerAttachment` | Remove an attachment |
| `Add-LedgerDocument` | Add a shared supporting document to a fiscal year |
| `Get-LedgerDocument` | List a fiscal year's shared documents |
| `Remove-LedgerDocument` | Remove a fiscal year document |

## SIE Import/Export

[SIE](https://sie.se/) is the Swedish standard for exchanging bookkeeping data
between systems. PSLedger speaks SIE type 4 (full verification export).
Files are written in CP437 (PC-8) encoding as required by the standard.

```powershell
# Export the current fiscal year to a SIE file (e.g. to send to an accountant)
Export-LedgerSie -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' `
    -Path .\minfirma-2024.se

# Validate a SIE file received from another system before importing
$result = Test-LedgerSie -Path .\fromfortnox.se
$result.IsValid
$result.Errors

# Import into a fresh journal, creating any missing accounts on the fly
New-LedgerJournal -Path .\Imported.ledger -Name 'Imported AB'
New-LedgerFiscalYear -JournalPath .\Imported.ledger -StartDate '2024-01-01' -EndDate '2024-12-31'
Import-LedgerSie -JournalPath .\Imported.ledger -FiscalYear '2024-01_2024-12' `
    -Path .\fromfortnox.se -CreateMissingAccounts
```

## General Ledger & VAT

```powershell
# View all transactions for a specific account
Get-LedgerLedger -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Account '1910'

# Generate a VAT report for a quarter
Get-LedgerVatReport -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' `
    -FromDate '2024-01-01' -ToDate '2024-03-31'
```

## Dimensions & Objects

```powershell
# Set up cost centres and projects
Add-LedgerDimension -JournalPath .\MinFirma.ledger -DimensionNumber 1 -Name 'Kostnadsställe'
Add-LedgerObject -JournalPath .\MinFirma.ledger -DimensionNumber 1 -ObjectNumber 'sthlm' -Name 'Stockholm'

# Add entries with object tags
$rows = @(
    @{ Account = '5010'; Amount = 8000; Objects = @{1='sthlm'} }
    @{ Account = '2440'; Amount = -8000 }
)
Add-LedgerEntry -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' `
    -Date '2024-03-01' -Description 'Hyra Stockholm' -Rows $rows
```

## Accruals & Recurring Entries

```powershell
# Accrue a prepaid expense across fiscal years
Add-LedgerAccrual -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' `
    -Date '2024-12-31' -Description 'Förutbetald försäkring Q1 2025' `
    -ExpenseAccount '6310' -AccrualAccount '1730' -Amount 12000 `
    -ReversalFiscalYear '2025-01_2025-12' -ReversalDate '2025-01-01'

# Set up a monthly recurring entry
New-LedgerRecurringEntry -JournalPath .\MinFirma.ledger -Name 'Hyra' `
    -Description 'Kontorshyra' -Schedule 'monthly' -DayOfMonth 1 `
    -StartDate '2024-01-01' -EndDate '2024-12-31' -Rows @(
    @{ Account = '5010'; Amount = 10000 }
    @{ Account = '2440'; Amount = -10000 }
)

# Generate all pending entries through today
Invoke-LedgerRecurringEntry -JournalPath .\MinFirma.ledger
```

## Attachments

Associate files (invoices, receipts, contracts) with verifications:

```powershell
# Attach a PDF invoice to verification 3
Add-LedgerAttachment -VerificationNumber 3 -Path .\faktura-101.pdf

# Attach and move (removes original)
Add-LedgerAttachment -VerificationNumber 3 -Path .\kvitto.jpg -Move

# List attachments
Get-LedgerAttachment -VerificationNumber 3

# List all attachments in the fiscal year
Get-LedgerAttachment

# Pipeline: get attachments for the latest entry
Get-LedgerEntry | Select-Object -Last 1 | Get-LedgerAttachment

# Remove an attachment
Remove-LedgerAttachment -VerificationNumber 3 -FileName 'kvitto.jpg'
```

Files are stored in a subdirectory named after the verification:
```
2024-01_2024-12/
├── ver0003.txt
└── ver0003/
    ├── faktura-101.pdf
    └── kvitto.jpg
```

## Documents (shared supporting material)

Attachments belong to a single verification. For supporting material (underlag)
that backs *several* verifications — such as a bank statement (kontoutdrag)
covering many entries — use fiscal-year documents instead:

```powershell
# Add a bank statement as supporting material for the whole year
Add-LedgerDocument -Path .\kontoutdrag-jan.pdf

# Add and move (removes original)
Add-LedgerDocument -Path .\kontoutdrag-feb.pdf -Move

# List all documents in the latest fiscal year
Get-LedgerDocument

# Filter by file name
Get-LedgerDocument -FileName 'kontoutdrag-*'

# Remove a document
Remove-LedgerDocument -FileName 'kontoutdrag-jan.pdf'
```

Documents are stored in a `documents/` subdirectory of the fiscal year,
independent of any verification:
```
2024-01_2024-12/
├── year.txt
├── ver0001.txt
└── documents/
    ├── kontoutdrag-jan.pdf
    └── kontoutdrag-feb.pdf
```

## Custom Extensions

Extend PSLedger with your own PowerShell functions. Extensions are `.ps1` files
loaded from configurable directories:

| Source | Path | Loaded when |
|--------|------|-------------|
| Environment | `$env:PSLEDGER_EXTENSIONS` (semicolon-separated) | Module import |
| User | `$HOME\.psledger\Extensions\` (or `$env:PSLEDGER_USER_EXTENSIONS`) | Module import |
| Journal | `<journal>\Extensions\` | `Set-LedgerCurrentJournal` is called |

**Env/User extensions** are dot-sourced into the module scope and can use internal
helpers. **Journal extensions** are loaded at runtime into global scope and can
call all public PSLedger commands.

### Example: Custom quick-entry function

Create `$HOME\.psledger\Extensions\Add-PreliminärskattEntry.ps1`:

```powershell
function Add-PreliminärskattEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][decimal]$Amount,
        [Parameter(Mandatory)][datetime]$Date,
        [Parameter(Mandatory)][string]$FiscalYear
    )

    $rows = @(
        @{ Account = '2518'; Amount = -$Amount }
        @{ Account = '1630'; Amount = $Amount }
    )
    Add-LedgerEntry -FiscalYear $FiscalYear -Date $Date `
        -Description "Preliminärskatt $($Date.ToString('yyyy-MM'))" -Rows $rows
}
```

Then use it:

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger
Add-PreliminärskattEntry -Amount 12000 -Date '2024-02-12' -FiscalYear '2024-01_2024-12'
```

### Listing loaded extensions

```powershell
Get-LedgerExtension                  # all loaded extensions
Get-LedgerExtension -Source Journal  # only per-journal extensions
```

## Fiscal Year Navigation

All commands that take `-FiscalYear` default to the **latest fiscal year** when
omitted. They also accept pipeline input from fiscal year objects:

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

# These are equivalent:
Get-LedgerBalance
Get-LedgerBalance -FiscalYear '2024-01_2024-12'
Get-LedgerLatestFiscalYear | Get-LedgerBalance

# Navigate through fiscal years
Get-LedgerFirstFiscalYear | Get-LedgerNextFiscalYear | Get-LedgerBalance

# Work with the latest open year specifically
Get-LedgerLatestOpenFiscalYear | Add-LedgerEntry -Date '2024-06-15' `
    -Description 'Försäljning' -Rows $rows
```

## Chart Templates

List available templates:

```powershell
Import-LedgerChart -ListAvailable
```

| Template | Accounts | Use case |
|----------|----------|----------|
| `BAS-Mini` | ~30 | Enskild firma, enklaste möjliga |
| `BAS-Smaforetag` | ~70 | Litet AB, vanligaste bokföringen |
| `BAS-Komplett` | ~250 | Större företag, full BAS-täckning |

You can also import a custom chart from any tab-separated file:

```powershell
Import-LedgerChart -JournalPath .\MinFirma.ledger -Path .\min-kontoplan.tsv
```

## File Format

```
MinFirma.ledger/
├── journal.txt              # Name, OrgNumber
├── accounts.txt             # Tab-separated: 1910\tKassa och bank
├── dimensions.txt           # Tab-separated: 1\tKostnadsställe
├── objects.txt              # Tab-separated: 1\tsthlm\tStockholm
├── recurring/               # Recurring entry templates
│   └── Hyra.txt
├── Extensions/              # Per-journal custom extensions (.ps1)
│   └── Add-PreliminärskattEntry.ps1
└── 2024-01_2024-12/         # Fiscal year
    ├── year.txt             # StartDate, EndDate, Status
    ├── ver0001.txt          # Verification #1
    └── ver0002.txt          # Verification #2
```

All files are UTF-8 encoded plain text. Tab (`\t`) is the field delimiter.

## Installation

```powershell
Install-Module PSLedger
```

## Development

### Prerequisites
- PowerShell 5.1+
- [Pester](https://github.com/pester/Pester) (testing framework)
- [TDDUtils](https://github.com/hansEricG/TDDUtils) (test utilities)
- [TDDSeams](https://github.com/hansEricG/TDDSeams) (mockable seams)

### Running Tests
```powershell
Invoke-Pester ./Tests
```

## License
MIT
