# PSLedger

A simple command-line double-entry bookkeeping system built as a PowerShell module, using plain text files as storage. Designed for Swedish small businesses following the BAS account structure.

## Features

- **Plain text storage** — all data in readable `.txt` files, version-controllable with Git
- **Double-entry enforcement** — every entry must balance (debit = credit)
- **BAS chart templates** — built-in Swedish account plans (Mini, Småföretag, Komplett)
- **Validation** — account existence, date range, closed-year protection
- **Reports** — trial balance, income statement, balance sheet, general ledger, VAT report
- **Annual report (årsredovisning)** — full K2 report (förvaltningsberättelse, noter,
  flerårsöversikt, vinstdisposition) exported to Text, Markdown or Word (`.docx`)
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

# 1b. (optional) Store extra company info, e.g. a VAT number
Set-LedgerJournal -JournalPath .\MinFirma.ledger -Metadata @{ VatNumber = 'SE556677889901' }

# 2. Set it as current (optional — saves typing -JournalPath on every command)
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

# 3. Import a chart of accounts
Import-LedgerChart -Template 'BAS-Smaforetag'

# 4. Create a fiscal year
New-LedgerFiscalYear -StartDate '2024-01-01' -EndDate '2024-12-31'

# 5. Add entries — either as hashtables...
$rows = @(
    @{ Account = '1910'; Amount = 50000 }
    @{ Account = '3040'; Amount = -50000 }
)
Add-LedgerEntry -FiscalYear '2024-01_2024-12' `
    -Date '2024-03-15' -Description 'Konsultarvode faktura #101' -Rows $rows

# ...or with New-LedgerEntryRow so you never juggle the debit/credit sign
$rows = @(
    New-LedgerEntryRow -Debit  '1910' 50000
    New-LedgerEntryRow -Credit '3040' 50000
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
| `Set-LedgerJournal` | Update company name / org number / metadata |
| `Import-LedgerChart` | Import chart of accounts from template or file |
| `Add-LedgerAccount` | Add a single account to the chart |
| `Get-LedgerAccount` | List or look up accounts |
| `New-LedgerFiscalYear` | Create a fiscal year |
| `Get-LedgerFiscalYear` | List fiscal years |
| `Close-LedgerFiscalYear` | Lock a fiscal year (no more entries) |
| `Add-LedgerEntry` | Create a verification (journal entry) |
| `New-LedgerEntryRow` | Build a verification row using -Debit/-Credit (no sign juggling) |
| `Get-LedgerEntry` | Query entries with optional filters |
| `Add-LedgerReversal` | Correct an entry via reversal |
| `Get-LedgerBalance` | Trial balance (saldobalans) |
| `Get-LedgerIncomeStatement` | Income statement (resultaträkning) |
| `Get-LedgerBalanceSheet` | Balance sheet (balansräkning), `-Detailed` for equity split |
| `Get-LedgerAnnualReport` | Combined income statement + balance sheet with comparison year |
| `Export-LedgerAnnualReport` | Write a full K2 årsredovisning to Text, Markdown or Word (.docx) |
| `Get-LedgerMultiYearOverview` | Flerårsöversikt (multi-year key figures) |
| `Get-LedgerEquityReconciliation` | Förändring av eget kapital (equity note) |
| `Get-LedgerProfitDisposition` | Förslag till vinstdisposition |
| `Get-LedgerFixedAssetNote` | Anläggningsregisternot (roll-forward) |
| `Get-LedgerShareholdingNote` | Not för aktier och andelar (bokfört + marknadsvärde) |
| `Get-LedgerEmployeeNote` | Not för medelantal anställda |
| `Get-LedgerAccountingPrinciples` | Standard K2 redovisnings- och värderingsprinciper |
| `Get-LedgerCompanyProfile` | Stable company info for the annual report (säte, aktier, styrelse) |
| `Set-LedgerReportInput` | Store year-specific annual report input (report.txt) |
| `Get-LedgerReportInput` | Read year-specific annual report input |
| `Copy-LedgerOpeningBalance` | Roll over balances to a new year |
| `Update-LedgerJournal` | Migrate a journal to the current on-disk format |
| `Backup-LedgerJournal` | Create a timestamped zip backup (with retention) |
| `Restore-LedgerJournal` | Restore a journal from a zip backup |
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
| `Add-LedgerCustomer` | Add a customer to the customer register |
| `Get-LedgerCustomer` | List or look up customers |
| `Set-LedgerCustomer` | Update customer details |
| `New-LedgerInvoice` | Create a customer invoice (draft) |
| `Get-LedgerInvoice` | List invoices, `-Unpaid` for open receivables |
| `Invoke-LedgerInvoicePosting` | Post an invoice to the ledger (verification) |
| `Add-LedgerInvoicePayment` | Register a full or partial invoice payment |
| `Get-LedgerAccountsReceivable` | Open receivables with aging buckets (`-Summary`) |
| `Export-LedgerInvoice` | Export an invoice to PDF, Word, Markdown or text |
| `Add-LedgerCreditInvoice` | Credit (reverse) a posted invoice |
| `Add-LedgerInvoiceReminder` | Record a payment reminder (optional document with fee and OCR) |
| `Add-LedgerInvoiceFee` | Book a reminder fee / late-payment compensation on an invoice |
| `Add-LedgerInvoiceInterest` | Calculate and book late-payment interest on an invoice |
| `Add-LedgerSupplier` | Add a supplier to the supplier register |
| `Get-LedgerSupplier` | List or look up suppliers |
| `Set-LedgerSupplier` | Update supplier details |
| `New-LedgerSupplierInvoice` | Register a supplier invoice (draft) |
| `Get-LedgerSupplierInvoice` | List supplier invoices, `-Unpaid` for open payables |
| `Invoke-LedgerSupplierInvoicePosting` | Post a supplier invoice to the ledger (verification) |
| `Add-LedgerSupplierPayment` | Register a full or partial supplier payment |
| `Get-LedgerAccountsPayable` | Open payables with aging buckets (`-Summary`) |

## Annual Report (Årsredovisning)

PSLedger can produce a complete K2 (BFNAR 2016:10) annual report for a small
limited company and export it to plain text, Markdown or a Word (`.docx`)
document. Stable company facts (registered office, object of the business, number
of shares, board members) live in the journal metadata; year-specific narrative
and decisions (significant events, proposed dividend, average employees, market
value of securities, signing place/date) live in an optional per-year `report.txt`
set with `Set-LedgerReportInput`.

Fixed-asset and shareholding notes are auto-detected from the standard BAS account
ranges — a note is only included when the relevant accounts carry a balance.

> For a full step-by-step walkthrough of the year-end close and annual report, see
> [docs/Bokslut-och-arsredovisning.md](docs/Bokslut-och-arsredovisning.md).

```powershell
# One-time: stable company facts on the journal
Set-LedgerJournal -JournalPath .\HEG.ledger -Metadata @{
    RegisteredOffice = 'Gävle'
    BusinessObject   = 'Konsultverksamhet inom IT.'
    NumberOfShares   = '1000'
    ShareCapital     = '100000'
    BoardMembers     = 'Hans-Erik Grönlund'
}

# Per year: narrative and board decisions for this fiscal year
Set-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -SignificantEvents 'Inga väsentliga händelser har inträffat under året.' `
    -ProposedDividend 50000 -AverageEmployees 1 -SecuritiesMarketValue 95000 `
    -SigningPlace 'Gävle' -SigningDate '2025-11-15'

# Export the full annual report as a Word document (also: Text, Markdown)
Export-LedgerAnnualReport -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08' `
    -Path .\arsredovisning.docx -Format Word

# Individual building blocks are available as data cmdlets too
Get-LedgerMultiYearOverview   -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'
Get-LedgerProfitDisposition   -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'
Get-LedgerEquityReconciliation -JournalPath .\HEG.ledger -FiscalYear '2024-09_2025-08'
```

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

## Row comments

Each row can carry its own free-text comment, useful for clarifying what an
amount refers to. Comments round-trip through `Get-LedgerEntry` as the row's
`Comment` property.

```powershell
# Via New-LedgerEntryRow
$rows = @(
    New-LedgerEntryRow -Debit  '5010' 8000 -Comment 'Hyra mars, Sveavägen'
    New-LedgerEntryRow -Credit '1910' 8000
)
Add-LedgerEntry -FiscalYear '2024-01_2024-12' -Date '2024-03-01' `
    -Description 'Hyra' -Rows $rows

# ...or as a Comment key on a row hashtable
$rows = @(
    @{ Account = '5010'; Amount = 8000; Comment = 'Hyra mars' }
    @{ Account = '1910'; Amount = -8000 }
)

# Read the comment back
$entry = Get-LedgerEntry -FiscalYear '2024-01_2024-12' -VerificationNumber 1
$entry.Rows | Format-Table Account, Amount, Comment
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

# Attach several files at once
Add-LedgerAttachment -VerificationNumber 3 -Path .\faktura-101.pdf, .\kvitto.jpg, .\avtal.pdf

# Attach and move (removes original)
Add-LedgerAttachment -VerificationNumber 3 -Path .\kvitto.jpg -Move

# Attach files while creating the entry (returns the new verification with -PassThru)
Add-LedgerEntry -FiscalYear '2024-01_2024-12' -Date '2024-03-15' `
    -Description 'Hyra kontor' -Rows $rows `
    -Attachment .\hyresfaktura.pdf, .\betalbevis.pdf -PassThru

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

## Invoicing (Fakturahantering)

Manage a customer register and the full customer-invoice lifecycle — create,
post to the ledger and register payments. Invoices are layered *on top of* the
bookkeeping: posting an invoice and registering a payment both create ordinary
verifications, so open receivables always reconcile against the general ledger.

An invoice moves through the statuses **Draft → Booked → Partial → Paid**.

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

# 1. Register a customer (default payment terms 30 days)
Add-LedgerCustomer -CustomerNumber '10' -Name 'Volvo AB' `
    -OrgNumber '556012-5790' -Email 'faktura@volvo.se' -PaymentTermsDays 30

# 2. Create a draft invoice — one row per revenue line (net amount + VAT)
$rows = @(
    @{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' }
)
New-LedgerInvoice -CustomerNumber '10' -Date '2024-03-15' `
    -Description 'Konsultarvode mars' -Rows $rows
# DueDate defaults to InvoiceDate + the customer's payment terms

# 3. Post it to the ledger (creates the verification):
#      1510 Kundfordringar  +12500
#      3010 Försäljning      -10000
#      2610 Utgående moms     -2500
Invoke-LedgerInvoicePosting -InvoiceNumber 1

# 4. Register payment (debit 1930 Bank, credit 1510). Full payment marks it Paid.
Add-LedgerInvoicePayment -InvoiceNumber 1 -Date '2024-04-10'

# Partial payments are supported and leave the invoice in 'Partial' status
Add-LedgerInvoicePayment -InvoiceNumber 2 -Amount 5000 -Date '2024-04-10'

# List open receivables (posted but not fully paid)
Get-LedgerInvoice -Unpaid |
    Format-Table InvoiceNumber, CustomerName, DueDate, Total, RemainingAmount, Status

# Accounts receivable with aging buckets (Current / 1-30 / 31-60 / 61-90 / 90+)
Get-LedgerAccountsReceivable
Get-LedgerAccountsReceivable -Summary       # one row per bucket with the total

# Export an invoice to a printable document (PDF by default; also Word/Markdown/Text)
Export-LedgerInvoice -InvoiceNumber 1 -Path .\faktura-1.pdf

# Credit (reverse) a posted, unpaid invoice — books the reversing verification and
# marks both the original and the credit note 'Credited'
Add-LedgerCreditInvoice -InvoiceNumber 1

# Send a payment reminder for an overdue invoice — records the reminder (no ledger
# posting) and optionally writes a document with a reminder fee and the OCR reference
Add-LedgerInvoiceReminder -InvoiceNumber 1 -Date '2024-05-01' -Fee 60 -Path .\paminnelse-1.pdf

# Book a reminder fee / late-payment compensation as an actual charge (debit 1510,
# credit 3590) so it increases the open receivable
Add-LedgerInvoiceFee -InvoiceNumber 1 -Amount 60 -Date '2024-05-01'

# Calculate and book late-payment interest (remaining × rate × days / 365; credit 8310)
Add-LedgerInvoiceInterest -InvoiceNumber 1 -AnnualRate 0.105 -Date '2024-06-01'
```

A VAT-free row simply omits the VAT (`VatRate = 0` and no `VatAccount`). Override
the receivable account with `-ReceivableAccount` and the cash/bank account with
`-Account` on the payment. Each invoice records the verifications it created
(`BookedVerification`, and one per payment) so it can be traced back to the ledger.

`Export-LedgerInvoice` produces the PDF with a built-in, dependency-free writer.
Add payment details (bankgiro, plusgiro, IBAN/BIC) to the document by storing them
as journal metadata, e.g. `Set-LedgerJournal -Metadata @{ Bankgiro = '123-4567' }`.
Every invoice also carries a Swedish **OCR reference** (`OcrReference`, a
Luhn-checked number derived from the invoice number) that is printed on invoices
and reminders for automatic payment matching.

For a full walkthrough see [docs/Fakturahantering.md](docs/Fakturahantering.md).

## Supplier Ledger (Leverantörsreskontra)

Manage a supplier register and the full supplier-invoice lifecycle — register,
post to the ledger and pay. Like the customer ledger, posting and paying both
create ordinary verifications, so open payables always reconcile against account
2440 Leverantörsskulder.

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

# 1. Register a supplier (default payment terms 30 days)
Add-LedgerSupplier -SupplierNumber '100' -Name 'Kontorsbolaget AB' `
    -OrgNumber '556006-8420' -PaymentTermsDays 30

# 2. Register a supplier invoice — one row per cost line (net amount + input VAT)
$rows = @(
    @{ Account = '5010'; Amount = 8000; VatRate = 0.25; VatAccount = '2640' }
)
New-LedgerSupplierInvoice -SupplierNumber '100' -Date '2024-03-10' `
    -Description 'Lokalhyra mars' -SupplierInvoiceNo 'F-99123' -Rows $rows

# 3. Post it to the ledger (creates the verification):
#      5010 Lokalhyra           +8000
#      2640 Ingående moms        +2000
#      2440 Leverantörsskulder  -10000
Invoke-LedgerSupplierInvoicePosting -InvoiceNumber 1

# 4. Pay it (debit 2440, credit 1930). Full payment marks it Paid.
Add-LedgerSupplierPayment -InvoiceNumber 1 -Date '2024-04-05'

# Accounts payable with aging buckets (Current / 1-30 / 31-60 / 61-90 / 90+)
Get-LedgerAccountsPayable
Get-LedgerAccountsPayable -Summary       # one row per bucket with the total
```

For a full walkthrough see [docs/Leverantorsreskontra.md](docs/Leverantorsreskontra.md).

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
├── journal.txt              # Name, OrgNumber, SchemaVersion
├── accounts.txt             # Tab-separated: 1910\tKassa och bank
├── dimensions.txt           # Tab-separated: 1\tKostnadsställe
├── objects.txt              # Tab-separated: 1\tsthlm\tStockholm
├── customers.txt            # Tab-separated: 10\tVolvo AB\t...\t30
├── invoices/                # Customer invoices
│   ├── inv0001.txt
│   └── inv0002.txt
├── recurring/               # Recurring entry templates
│   └── Hyra.txt
├── Extensions/              # Per-journal custom extensions (.ps1)
│   └── Add-PreliminärskattEntry.ps1
└── 2024-01_2024-12/         # Fiscal year
    ├── year.txt             # StartDate, EndDate, Status
    ├── ib.txt               # Opening balance metadata (optional)
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
