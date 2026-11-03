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
- **Tamper detection** — verifications and attachments are sealed in a SHA-256 hash
  chain per fiscal year, so later edits can be detected (varaktighet)
- **Archiving** — export a closed fiscal year as a self-contained package (SIE, grundbok,
  huvudbok and statements as text and PDF, annual report, all vouchers and attachments)
  with SHA-256 checksums, for the seven-year retention period
- **SIE 4 import/export** — exchange data with other Swedish accounting systems (incl. dimensions)
- **Dimensions & objects** — cost centres, projects with SIE round-trip support
- **Accruals** — automated accrual + reversal across fiscal years
- **Recurring entries** — monthly templates with idempotent auto-generation
- **Bank import & reconciliation** — import camt.053/CSV statements, auto-match OCR and
  supplier payments, posting rules, and bank reconciliation (bankavstämning)
- **Time reporting** — register or import time per project, customer and person,
  hourly rates per customer/project, time reports with margin, and invoicing of time
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
    @{ Account = '1510'; Amount = 62500 }
    @{ Account = '3040'; Amount = -50000 }
    @{ Account = '2610'; Amount = -12500 }
)
Add-LedgerEntry -FiscalYear '2024-01_2024-12' `
    -Date '2024-03-15' -Description 'Konsultarvode faktura #101' -Rows $rows

# ...or with New-LedgerEntryRow so you never juggle the debit/credit sign
$rows = @(
    New-LedgerEntryRow -Debit  '1510' 62500
    New-LedgerEntryRow -Credit '3040' 50000
    New-LedgerEntryRow -Credit '2610' 12500
)
Add-LedgerEntry -FiscalYear '2024-01_2024-12' `
    -Date '2024-03-15' -Description 'Konsultarvode faktura #101' -Rows $rows

# 6. View reports
Get-LedgerBalance -FiscalYear '2024-01_2024-12' |
    Format-Table AccountNumber, AccountName, Debit, Credit, Balance

# 7. Year-end (save the returned ChainHash outside the journal)
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
| `Convert-LedgerChart` | Convert accounts from earlier PSLedger templates to standard BAS |
| `Add-LedgerAccount` | Add a single account to the chart |
| `Get-LedgerAccount` | List or look up accounts |
| `New-LedgerFiscalYear` | Create a fiscal year |
| `Get-LedgerFiscalYear` | List fiscal years |
| `Close-LedgerFiscalYear` | Lock a fiscal year (no more entries) and return its final chain hash |
| `Test-LedgerIntegrity` | Detect changed, missing or unsealed verifications and attachments |
| `Protect-LedgerFiscalYear` | Seal existing verifications and attachments in a fiscal year |
| `Export-LedgerArchive` | Export a fiscal year as an archive package for long-term storage |
| `Test-LedgerArchive` | Verify an archive package against its checksums and integrity chain |
| `Add-LedgerEntry` | Create a verification (journal entry) |
| `New-LedgerEntryRow` | Build a verification row using -Debit/-Credit (no sign juggling) |
| `Get-LedgerEntry` | Query entries with optional filters |
| `Add-LedgerReversal` | Correct an entry via reversal |
| `Get-LedgerBalance` | Trial balance (saldobalans) |
| `Get-LedgerIncomeStatement` | Income statement (resultaträkning) |
| `Get-LedgerBalanceSheet` | Balance sheet (balansräkning), `-Detailed` for equity split |
| `Get-LedgerAnnualReport` | Combined income statement + balance sheet with comparison year |
| `Export-LedgerAnnualReport` | Write a full K2 or K3 årsredovisning to Text, Markdown or Word (.docx) |
| `Get-LedgerMultiYearOverview` | Flerårsöversikt (multi-year key figures) |
| `Get-LedgerEquityReconciliation` | Förändringar i eget kapital (förvaltningsberättelse) |
| `Get-LedgerProfitDisposition` | Förslag till vinstdisposition |
| `Add-LedgerProfitDisposition` | Book the resultatdisposition (2099 → 2091, dividend on 2898) after the AGM |
| `Get-LedgerFixedAssetNote` | Anläggningsregisternot (roll-forward) |
| `Get-LedgerShareholdingNote` | Not för aktier och andelar (bokfört + marknadsvärde) |
| `Get-LedgerEmployeeNote` | Not för medelantal anställda |
| `Get-LedgerAccountingPrinciple` | Standard K2 redovisnings- och värderingsprinciper |
| `Get-LedgerCompanyProfile` | Stable company info for the annual report (säte, aktier, styrelse) |
| `Set-LedgerReportInput` | Store year-specific annual report input (report.txt) |
| `Get-LedgerReportInput` | Read year-specific annual report input |
| `Set-LedgerHolding` | Record or update a securities holding at the balance date (holdings.txt) |
| `Get-LedgerHolding` | List holdings with market value and comparison to book value |
| `Remove-LedgerHolding` | Remove a securities holding |
| `Copy-LedgerHolding` | Roll securities holdings over to a new year |
| `Add-LedgerImpairment` | Book a write-down (nedskrivning) or its reversal (`-Reverse`), optionally of a holding against its market value |
| `Copy-LedgerOpeningBalance` | Roll over balances to a new year |
| `Update-LedgerJournal` | Migrate a journal to the current on-disk format |
| `Backup-LedgerJournal` | Create a timestamped zip backup (with retention) |
| `Restore-LedgerJournal` | Restore a journal from a zip backup |
| `Export-LedgerSie` | Export a fiscal year to a SIE 4E file |
| `Import-LedgerSie` | Import verifications from a SIE 4 file |
| `Test-LedgerSie` | Validate a SIE file without importing |
| `Get-LedgerGeneralLedger` | General ledger (huvudbok) per account |
| `Get-LedgerVatReport` | VAT declaration report (momsdeklaration) |
| `Get-LedgerVatReportDetail` | Explain each account's VAT contribution, mapping rule and source |
| `Export-LedgerVatDeclaration` | Export a VAT declaration to a Skatteverket eSKD file |
| `Export-LedgerIncomeTaxReturn` | Export an income tax return (INK2) to Skatteverket SRU files |
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
| `Add-LedgerEmployee` | Add an employee to the employee register |
| `Get-LedgerEmployee` | List or look up employees |
| `Set-LedgerEmployee` | Update employee details |
| `New-LedgerPayslip` | Create a payslip (draft) |
| `Get-LedgerPayslip` | List payslips, filter by status or employee |
| `Invoke-LedgerPayrollPosting` | Post a payslip to the ledger (verification) |
| `Add-LedgerPayrollTaxPayment` | Book payment of withheld tax and employer contributions |
| `Add-LedgerVacationLiability` | Book the change in the vacation pay liability (2920/7290) |
| `Export-LedgerPayslip` | Export a payslip to PDF, Word, Markdown or text |
| `Export-LedgerEmployerDeclaration` | Export the employer declaration on individual level (AGI) as XML |
| `Import-LedgerBankStatement` | Import a bank statement (camt.053 or CSV) |
| `Get-LedgerBankStatement` | List imported bank statements with balances |
| `Get-LedgerBankTransaction` | List bank transactions, filter by status or period |
| `Invoke-LedgerBankMatching` | Match and post unmatched bank transactions automatically |
| `Set-LedgerBankTransaction` | Post, link, ignore or reset a bank transaction by hand |
| `Get-LedgerBankReconciliation` | Reconcile the bank account against the ledger (bankavstämning) |
| `Add-LedgerBankRule` | Add a posting rule for recurring bank transactions |
| `Get-LedgerBankRule` | List bank posting rules |
| `Remove-LedgerBankRule` | Remove a bank posting rule |
| `Add-LedgerTimeResource` | Add a person who reports time (self, employee or subcontractor) |
| `Get-LedgerTimeResource` | List time resources |
| `Set-LedgerTimeResource` | Update a time resource or make it the default |
| `Add-LedgerProject` | Add a project with customer and hourly rate |
| `Get-LedgerProject` | List projects |
| `Set-LedgerProject` | Update, close or reopen a project |
| `Add-LedgerTimeEntry` | Register time |
| `Get-LedgerTimeEntry` | List time entries, filter by period, project, person or status |
| `Set-LedgerTimeEntry` | Change a time entry that is not invoiced |
| `Remove-LedgerTimeEntry` | Remove a time entry that is not invoiced |
| `Import-LedgerTimeEntry` | Import time from a CSV file |
| `Get-LedgerTimeReport` | Summarise time per customer, project, person, month or week |
| `New-LedgerTimeInvoice` | Create a customer invoice from open billable time |

## Annual Report (Årsredovisning)

PSLedger can produce a complete K2 (BFNAR 2016:10) annual report for a small
limited company and export it to plain text, Markdown or a Word (`.docx`)
document. Stable company facts (registered office, object of the business, number
of shares, board members) live in the journal metadata; year-specific narrative
and decisions (significant events, proposed dividend, average employees, market
value of securities, signing place/date) live in an optional per-year `report.txt`
set with `Set-LedgerReportInput`. Securities holdings can be recorded per balance
date with `Set-LedgerHolding` (`holdings.txt`); their total market value then
replaces the manual `SecuritiesMarketValue`, and holdings below book value are
flagged for impairment assessment.

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
Get-LedgerGeneralLedger -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' -Account '1910'

# Generate a VAT report for a quarter
Get-LedgerVatReport -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' `
    -FromDate '2024-01-01' -ToDate '2024-03-31'
```

The VAT report maps BAS accounts to the boxes of the VAT return, for example
3308 to box 39 (services to another EU country), 4535 to box 21 and 2614 to box 30
(reverse charge). If your chart deviates from BAS, map accounts to boxes in a
`vat.txt` file in the journal directory (account or range, a tab, the box; `-`
for no box):

```
; PSLedger VAT mapping: Account or range, Box
3060	39
3800-3899	-
```

To explain the figures before exporting a declaration:

```powershell
Get-LedgerVatReportDetail -JournalPath .\Konsultbyrån.ledger -FiscalYear '2024-01_2024-12' `
    -FromDate '2024-01-01' -ToDate '2024-03-31' |
    Format-Table AccountNumber, AccountName, Balance, Box, Amount, Source, Rule, Status
```

`Balance` is the signed movement in the period (debit positive); `Amount` is
the contribution to the VAT box, using the same signs as the summary.
`Source` is `BAS`, `vat.txt` or `None`. `Status` distinguishes an explicit
mapping (`Mapped`), the BAS catch-all to box 05 (`Implicit`), an explicit
exclusion (`Excluded`) and no matching rule (`Unmapped`). Excluded and unmapped
accounts have no `Box` or `Amount`, but retain their balance. Unmapped bank or
expense accounts are normally expected, not necessarily errors. Accounts with
zero net movement are retained if they had entries in the period; opening
balances are excluded. Box 49 is derived by the summary, not assigned to an
individual account.

Journals created from the BAS-Komplett or BAS-Smaforetag templates of PSLedger
1.0.0 and earlier used some non-BAS accounts (e.g. 3300 for EU services).
`Convert-LedgerChart` adds the BAS accounts and the `vat.txt` rules for them:

```powershell
Convert-LedgerChart -JournalPath .\MinFirma.ledger -Date '2025-07-01'
```

With `-Date`, conversion validates the open year, date, amounts and effective
source/target VAT boxes before changing files. Conflicting `vat.txt` rules are
reported as errors, not overwritten; omit `-Date` to add accounts and mappings
without a transfer.

The default VMB mapping assumes the taxable positive margin excluding VAT has
already been calculated and booked separately on 3211. Negative VMB sales on
3212 do not affect the VAT boxes; this is not an automatic margin calculation or
support for simplified VMB. Voluntarily taxed rent (3913) goes to box 08, while
other taxable rent (3914) goes to box 05. See the
[BAS chart](https://www.bas.se/kontoplaner/) and
[Skatteverket's box instructions](https://www.skatteverket.se/foretag/moms/deklareramoms/fyllaimomsdeklarationen.4.3a2a542410ab40a421c80004214.html).

If the non-taxable purchase-price component of a VMB sale is booked separately
on another sales account, exclude that account in `vat.txt` too (for example,
`3223` followed by a tab and `-`). The reference cases in
`Tests/Export-LedgerVatDeclaration.Tests.ps1` demonstrate this convention, import
VAT, credit notes and triangular trade with independently calculated amounts.

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
    New-LedgerEntryRow -Credit '1930' 8000
)
Add-LedgerEntry -FiscalYear '2024-01_2024-12' -Date '2024-03-01' `
    -Description 'Hyra' -Rows $rows

# ...or as a Comment key on a row hashtable
$rows = @(
    @{ Account = '5010'; Amount = 8000; Comment = 'Hyra mars' }
    @{ Account = '1930'; Amount = -8000 }
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

# Rows can carry text, quantity, unit and unit price; Amount is then computed
$rows = @(
    @{ Account = '3010'; Description = 'Systemutveckling mars'; Quantity = 32.5; Unit = 'h'; UnitPrice = 1100; VatRate = 0.25; VatAccount = '2610' }
)
New-LedgerInvoice -CustomerNumber '10' -Date '2024-03-31' -Description 'Konsulttjänster mars' -Rows $rows

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
# marks both the original and the credit note 'Credited'. Booked fees and interest
# are reversed too. Repeat to resume.
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

If `Invoke-LedgerInvoicePosting` is interrupted, run the same command again:

```powershell
Invoke-LedgerInvoicePosting -JournalPath .\HEG.ledger -InvoiceNumber 1
```

The command resumes its saved posting plan in `invoices/posting/inv0001.txt`.
It reuses the reserved verification number, checks the invoice and verification
hashes and operation identity, finishes sealing if needed, and saves the invoice's
booked status. A matching saved verification can be linked even after year
closure, but a missing verification cannot be created in a closed year. If the
invoice was already fully posted, the command still reports "already posted".

Keep these immutable plans after success and in backups; never delete them to
clear an error or free a reserved number. Changed invoice data, conflicting
verification content or a damaged integrity chain stop recovery and require
diagnosis rather than automatic repair.

For **customer-invoice payments**, retain a GUID before the first attempt and
reuse it for retries:

```powershell
$paymentId = New-Guid  # Save this ID before registering the payment.
Add-LedgerInvoicePayment -JournalPath .\HEG.ledger -InvoiceNumber 1 `
    -Date '2024-04-10' -Amount 5000 -PaymentId $paymentId
# Resume, or return the current invoice if this payment already completed:
Add-LedgerInvoicePayment -JournalPath .\HEG.ledger -InvoiceNumber 1 `
    -PaymentId $paymentId -PassThru
```

An omitted date, amount, bank account or fiscal year uses the saved plan on a
retry. Explicit conflicting inputs are rejected. Distinct IDs allow two real
payments with the same date and amount. Without `-PaymentId`, each call starts
a new payment: do not repeat an unkeyed call blindly after an uncertain result.
Inspect `invoices/payments/<guid>.txt` and retry with that ID. An unfinished
payment blocks further payments and invoice changes and reports the recovery
command. A matching saved verification may complete the payment after year
closure, but a missing verification cannot be created in a closed year.

Keep payment plans after success and in backups, just like posting plans.

**Bank matching against customer invoices is also recoverable.** If the payment
was started by bank matching, repeat the same manual match or rerun automatic
matching:

```powershell
Set-LedgerBankTransaction -JournalPath .\HEG.ledger -TransactionId 15 -InvoiceNumber 1
# Alternatively, resume saved matches before applying ordinary matching rules:
Invoke-LedgerBankMatching -JournalPath .\HEG.ledger
```

The payment plan retains the bank transaction's identity and input hash.
Recovery finishes both the payment and the bank link, even if the invoice is
already paid or has later payments. Changed bank inputs or conflicting links
stop recovery. The reserved verification cannot be claimed by another bank
transaction with the same date and amount.

`-Reset` clears the link but retains payment ownership. Only relinking the same
payment is permitted afterwards; resetting never undoes or frees the payment
for another invoice. Bookkeeping corrections require separate handling.

An unfinished payment started outside bank matching still needs to be resumed
with its `PaymentId` first, then linked with `-VerificationNumber` and
`-FiscalYear`; do not register another payment.

**Charges and credit notes are recoverable too.** Give a fee, interest charge or
booked reminder fee a stable `-ChargeId` to resume it, or to return the current
invoice if the charge already completed:

```powershell
$chargeId = New-Guid  # Save this ID before booking the charge.
Add-LedgerInvoiceReminder -JournalPath .\HEG.ledger -InvoiceNumber 1 -Fee 60 -BookFee -ChargeId $chargeId
```

The plan in `invoices/charges/<guid>.txt` stores the charge type, date, amount,
account and reserved verification. A retry with conflicting inputs is rejected,
and interest resumes with the planned amount. Without `-ChargeId`, each call
books a new charge. An unfinished charge blocks other changes to the invoice and
reports the ID to resume with. `-ChargeId` on a reminder requires `-BookFee`.

`Add-LedgerCreditInvoice` saves a plan in `invoices/credits/invNNNN.txt` (keyed
by the original invoice) that reserves both the credit-note number and the
verification. If crediting is interrupted, repeat the same command to complete
it with the planned date; repeating after completion returns the existing credit
note. An unfinished credit blocks payments and charges on the invoice.

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
    -Description 'Lokalhyra mars' -SupplierReference 'F-99123' -Rows $rows

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

**Supplier payments and their bank matches are recoverable**, using the same
rules as customer payments:

```powershell
$paymentId = New-Guid
Add-LedgerSupplierPayment -InvoiceNumber 1 -Date '2024-04-05' -Amount 5000 -PaymentId $paymentId
# After interruption, reuse the saved ID; omitted inputs come from the plan:
Add-LedgerSupplierPayment -InvoiceNumber 1 -PaymentId $paymentId -PassThru

# For a payment started by bank matching, repeat the same match instead:
Set-LedgerBankTransaction -TransactionId 16 -SupplierInvoiceNumber 1
# Or resume it through automatic matching:
Invoke-LedgerBankMatching
```

Different IDs allow identical real partial payments; without an ID, each call
starts a new payment. An unfinished payment reports the ID to resume and blocks
conflicting writes. IDs are unique across customer and supplier payments, while
invoice numbers belong to separate series. Plans are kept in
`supplierinvoices/payments/<guid>.txt`, retained after completion and included in
archives. Do not remove them from backups. Recovery in a closed year may finish
an existing verification's payment, but never create a new verification.

Bank Reset retains ownership: only the same supplier payment can be relinked,
not a customer invoice with the same number or another supplier invoice.

**Supplier invoice posting is resumable** in the same way as customer invoice
posting. If `Invoke-LedgerSupplierInvoicePosting` is interrupted, run the same
command again. It resumes the immutable plan in
`supplierinvoices/posting/sup0001.txt` with its reserved verification number,
operation identity and hashes. The plan is marked `InvoiceType: Supplier`, so
customer and supplier invoices with the same number never share a plan.
Changed invoice data, a conflicting verification or integrity errors stop
recovery without writing. In a closed year only an already-saved verification
can be completed. Keep these plans after success and in backups; archives
include them.

For a full walkthrough see [docs/Leverantorsreskontra.md](docs/Leverantorsreskontra.md).

## Payroll (Lönehantering)

Manage an employee register and payslips for a simple Swedish payroll. Posting a
payslip creates an ordinary verification, so the payroll liability accounts (2710
Personalskatt, 2730 Arbetsgivaravgift skuld) always reconcile against the ledger.

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

# 1. Register an employee (default salary account 7210, optional default tax rate)
Add-LedgerEmployee -EmployeeNumber '1' -Name 'Anna Andersson' `
    -PersonalNumber '19850101-1234' -SalaryAccount '7210' -TaxRate 0.30

# 2. Create a payslip — gross salary; tax from -TaxRate/-TaxAmount or the default
New-LedgerPayslip -EmployeeNumber '1' -GrossSalary 30000 `
    -PeriodStart '2024-03-01' -PeriodEnd '2024-03-31' -PayDate '2024-03-25'

# 3. Post it to the ledger (creates the verification):
#      7210 Löner                    +30000
#      2710 Personalskatt             -9000
#      1930 Företagskonto            -21000
#      7510 Arbetsgivaravgifter       +9426
#      2730 Arbetsgivaravgift skuld   -9426
Invoke-LedgerPayrollPosting -PayslipNumber 1

# 4. Print a payslip (PDF, Word, Markdown or text)
Export-LedgerPayslip -PayslipNumber 1 -Path .\lonebesked-1.pdf

# 5. Pay the withheld tax (2710) and employer contributions (2730) to the tax
#    account, settling the liabilities:
#      2710 Personalskatt            +9000
#      2730 Arbetsgivaravgift skuld  +9426
#      1930 Företagskonto           -18426
Add-LedgerPayrollTaxPayment -Date '2024-04-12'

# 6. Book the change in the vacation pay liability at year end (debit 7290,
#    credit 2920):
Add-LedgerVacationLiability -Date '2024-12-31' -Amount 45000

# 7. Export the monthly employer declaration on individual level (AGI) as XML
#    for upload in Skatteverket's e-service (one IU per employee, HU totals):
Export-LedgerEmployerDeclaration -Period '202403' -Path .\agi-2024-03.xml
```

For a full walkthrough see [docs/Lonehantering.md](docs/Lonehantering.md).

## Bank Import & Reconciliation (Bankavstämning)

Import bank statements, let PSLedger match and post the transactions, and
reconcile the bank account against the ledger. Supports ISO 20022 camt.053 and
CSV exports from the internet bank (columns such as Swedbank's are recognised
automatically).

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

# 1. Import a statement (duplicates from overlapping files are skipped)
Import-LedgerBankStatement -Path .\kontoutdrag-2024-03.xml

# 2. Posting rules for recurring transactions (first match wins)
Add-LedgerBankRule -Pattern 'Bankavgift' -Account 6570 -Description 'Bankavgift'
Add-LedgerBankRule -Pattern 'Telia*' -Account 6212 -VatRate 0.25 -VatAccount 2640

# 3. Match and post: links existing verifications, registers OCR payments on
#    customer invoices and payments of supplier invoices, then applies rules
Invoke-LedgerBankMatching

# 4. Handle what is left by hand
Get-LedgerBankTransaction -Status Unmatched
Set-LedgerBankTransaction -TransactionId 12 -Account 8310
Set-LedgerBankTransaction -TransactionId 18 -InvoiceNumber 7

# 5. Reconcile 1930 against the bank's balance
Get-LedgerBankReconciliation -AsOf '2024-12-31'
```

For a full walkthrough see [docs/Bankavstamning.md](docs/Bankavstamning.md).

**Rule and manual account postings are also recoverable.** After interruption,
rerun `Invoke-LedgerBankMatching` or repeat the original
`Set-LedgerBankTransaction -TransactionId <id> -Account <account>`.
Saved plans take precedence over current rules, including with `-NoRules`;
changing or deleting a rule never changes an already-planned posting. Explicitly
conflicting retry inputs, changed bank data or damaged verifications stop recovery.
In a closed year, only an already-saved verification can be completed.

Plans in `bank/posting/` retain the verification reservation and bank identity.
Keep this directory after success and in backups; archive packages include the
plans and their source statements. `-Reset` permits only relinking the same
posting, not changing its account, ignoring it or paying an invoice with it.

Transfers without VAT can link both bank sides to one verification, including
a counterpart imported later. The selected counterpart's identity and input hash
are saved before either bank link is updated. If several candidates are equally
close in date, **the selected transaction is booked once, but no counterpart is
guessed**. A warning requests an explicit choice:

```powershell
Set-LedgerBankTransaction -TransactionId 27 -VerificationNumber 42 -FiscalYear '2024-01_2024-12'
```

An ambiguity marker prevents a later automatic run from silently choosing instead.
Both sides retain ownership through Reset and retries. Recovery does not undo
bookkeeping; corrections remain separate operations.

## Time Reporting (Tidrapportering)

Register time for yourself, employees and subcontractors, and invoice it.
Time is priced by an hourly rate per project or per customer and becomes
invoice rows with hours, rate and text.

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

# 1. Who reports time (the first resource is the default) and what it costs
Add-LedgerTimeResource -ResourceId 'HEG' -Name 'Hans-Eric'
Add-LedgerTimeResource -ResourceId 'KON' -Name 'Kalle Konsult' -SupplierNumber 200 -CostRate 750

# 2. Hourly rates per customer and/or project (the project rate wins)
Set-LedgerCustomer -CustomerNumber 10 -HourlyRate 1050
Add-LedgerProject -ProjectNumber 'P100' -Name 'Webbshop' -CustomerNumber 10 -HourlyRate 1200

# 3. Register time, or import it from a CSV export (Excel, Toggl, Harvest ...)
Add-LedgerTimeEntry -Hours '7:30' -ProjectNumber P100 -Date '2024-03-04' -Text 'Design'
Import-LedgerTimeEntry -Path .\tid-mars.csv

# 4. Follow up and invoice the open time
Get-LedgerTimeReport -GroupBy Project, Resource -FromDate '2024-03-01' -ToDate '2024-03-31'
New-LedgerTimeInvoice -CustomerNumber 10 -Through '2024-03-31'
```

For a full walkthrough see [docs/Tidrapportering.md](docs/Tidrapportering.md).

## Tamper Detection (Varaktighet)

Each fiscal year has an append-only hash chain, `integrity.txt`. `Add-LedgerEntry`
and `Add-LedgerAttachment` seal what they write; a sealed attachment can only be
removed with `Remove-LedgerAttachment`, which records the removal in the chain.

```powershell
# Check every fiscal year
Test-LedgerIntegrity -JournalPath .\MinFirma.ledger

# Journals created with older PSLedger versions: seal what is already there
Protect-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

# Closing returns the final chain hash. Store it somewhere else (e-mail, the
# signed annual report) and check against it later.
$closed = Close-LedgerFiscalYear -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'
Test-LedgerIntegrity -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12' `
    -ExpectedHash $closed.ChainHash
```

The chain detects edits made without rebuilding it. Someone who rewrites both
the files and the chain is only caught by `-ExpectedHash`. Opening balances,
`year.txt`, year documents and the registers are not part of the chain.

### Concurrent writes and interrupted operations

Verification posting (including reversals), customer-invoice posting and payments,
charges, reminders, bank imports and matching, attachment changes, sealing, fiscal-year closing,
chart conversion and credit-note rollback share a journal-level write lock.
The verification writer holds it across validation, number allocation, file
creation and integrity registration. Nested calls reuse the same lock. A
competing process waits for up to 30 seconds, then reports that the journal is
busy. New verification files never overwrite an existing filename.

The lock uses `.write.lock` in the journal root on a local filesystem with
normal .NET file locking enabled. The file is empty and remains after use;
its existence does **not** mean the journal is locked. The operating system
releases the open handle when the operation finishes or its process exits.
Do not delete or replace the file while writers may be running. `-WhatIf`
does not acquire the lock or create this file.

This is not a transaction across files: an interrupted process can still leave
a saved verification without its integrity record or all attachments. If a
posting reports such a partial failure, inspect the saved verification and run
`Test-LedgerIntegrity` before taking recovery action; do not simply post it
again. `Invoke-LedgerInvoicePosting`, `Invoke-LedgerSupplierInvoicePosting`,
`Add-LedgerInvoicePayment -PaymentId` and `Add-LedgerSupplierPayment -PaymentId`
can resume their saved plans as described above, as can customer/supplier bank
matches, bank rule/account postings, invoice charges (`-ChargeId`), credit
notes, `Invoke-LedgerPayrollPosting` and `Close-LedgerFiscalYear`.
`Convert-LedgerChart` needs no plan: repeating it skips existing accounts and
VAT rules and finds the transferred balance already moved. `Import-LedgerSie`
validates the whole file before writing and saves `<year>/import.txt`, which
reserves the verification numbers; repeat the import with the same file to
complete an interrupted one without duplicates.

Other register and metadata writers, older PSLedger versions and external
editors do not all participate in the lock. Readers and backups do not acquire
a consistent-snapshot lock either. Avoid running those operations concurrently
with writes. Shared network filesystems and simultaneous writes through Git,
OneDrive or similar synchronisation are not supported by this mechanism.

## Archiving (Arkivering)

Bokföringslagen requires the accounting records to be kept for seven years in a
readable form. `Export-LedgerArchive` writes a closed fiscal year as one zip file
that does not need PSLedger to be read:

```
MinFirma_2024-01_2024-12_archive/
├── README.txt        # What the package contains and how to verify it
├── manifest.txt      # Company, fiscal year, integrity status, final chain hash
├── checksums.txt     # SHA-256 of every file (sha256sum -c compatible)
├── sie/              # The year as a SIE 4 file
├── reports/          # Grundbok, huvudbok, saldobalans, resultat- och balansräkning,
│                     # momsrapport (.txt + .pdf), årsredovisning (.md, .docx, .pdf)
└── journal/          # The year's verifications, attachments, documents and
                      # integrity.txt, the registers, and the year's invoices,
                      # supplier invoices, payslips and bank statements
```

```powershell
# Archive a closed year next to the journal (.\archive\)
Export-LedgerArchive -JournalPath .\MinFirma.ledger -FiscalYear '2024-01_2024-12'

# Archive every closed year to an external disk, then verify the packages
Get-LedgerFiscalYear -JournalPath .\MinFirma.ledger | Where-Object Status -eq 'Closed' |
    Export-LedgerArchive -JournalPath .\MinFirma.ledger -DestinationPath E:\Arkiv
Get-ChildItem E:\Arkiv -Filter '*_archive.zip' | Test-LedgerArchive |
    Format-Table FiscalYear, Status, Files
```

`journal/` is itself a PSLedger journal, so the archived year can also be read with
`Get-LedgerEntry`, `Test-LedgerIntegrity` and the other commands after unpacking.
An open year, or a year whose integrity check fails, is only archived with `-Force`
(an open year is marked as preliminary).

## Custom Extensions

Extend PSLedger with your own PowerShell functions. Extensions are `.ps1` files
loaded from configurable directories:

| Source | Path | Loaded when |
|--------|------|-------------|
| Environment | `$env:PSLEDGER_EXTENSIONS` (semicolon-separated) | Module import |
| User | `$HOME\.psledger\Extensions\` (or `$env:PSLEDGER_USER_EXTENSIONS`) | Module import |
| Journal | `<journal>\Extensions\` | `Set-LedgerCurrentJournal` is called |

**Env/User extensions** are loaded at module import and can use internal helpers.
**Journal extensions** are loaded when the journal is selected and can also use
internal helpers. All extension functions are created as global functions (they
are not part of the module's exported commands) and are removed again when the
module is removed or the journal is cleared.

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
├── bank/                    # Imported bank statements and posting rules
│   ├── rules.txt
│   └── stmt0001.txt
├── time/                    # Time reporting
│   ├── resources.txt        # Who reports time
│   ├── projects.txt         # Projects with customer and hourly rate
│   └── 2024-03.txt          # Time entries, one file per month
├── Extensions/              # Per-journal custom extensions (.ps1)
│   └── Add-PreliminärskattEntry.ps1
└── 2024-01_2024-12/         # Fiscal year
    ├── year.txt             # StartDate, EndDate, Status
    ├── ib.txt               # Opening balance metadata (optional)
    ├── report.txt           # Annual report input (optional)
    ├── holdings.txt         # Securities holdings at the balance date (optional)
    ├── integrity.txt        # Hash chain sealing verifications and attachments
    ├── ver0001.txt          # Verification #1
    └── ver0002.txt          # Verification #2
```

All files are UTF-8 encoded plain text. Tab (`\t`) is the field delimiter.
The complete specification of every file, and the policy for when the
`SchemaVersion` changes, is in [docs/File-format.md](docs/File-format.md).

## Installation

PSLedger requires [PowerShell 7.4](https://aka.ms/powershell) or later
(Windows, macOS or Linux). Windows PowerShell 5.1 is not supported.

```powershell
Install-Module PSLedger
```

## Development

### Prerequisites
- PowerShell 7.4+
- [Pester](https://github.com/pester/Pester) 6.x (testing framework)
- [TDDUtils](https://github.com/hansEricG/TDDUtils) 1.0.6+ (test utilities)
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) (linting)
- Microsoft.PowerShell.PSResourceGet 1.1.0+ (package verification)

```powershell
Install-Module Pester -MinimumVersion 6.0.0 -Scope CurrentUser -SkipPublisherCheck
Install-Module TDDUtils -MinimumVersion 1.0.6 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser
Install-Module Microsoft.PowerShell.PSResourceGet -MinimumVersion 1.1.0 -Scope CurrentUser
```

### Running Tests
```powershell
Invoke-Pester ./Tests
Invoke-ScriptAnalyzer -Path ./PSLedger -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
./scripts/Test-ModulePackage.ps1 -DestinationPath ./artifacts
```

GitHub Actions runs Pester and package verification on Windows, Linux and macOS,
and linting on Linux, for every push and pull request (`.github/workflows/ci.yml`).
The package check uses an explicitly local repository, restores the `.nupkg`
into a temporary versioned module directory, and validates the manifest, exports
and a journal/chart/posting/VAT/integrity flow in a fresh PowerShell process.
It does not publish to the Gallery or install PSLedger globally. Temporary data
and the local repository registration are removed; the verified package is
retained in the destination directory, without overwriting an existing package.

### Releasing
1. Set `ModuleVersion` in `PSLedger/PSLedger.psd1` and move the `[Unreleased]`
   entries in `CHANGELOG.md` to a `## [x.y.z] - yyyy-MM-dd` section.
2. Commit, then tag and push: `git tag vx.y.z; git push origin vx.y.z`.
3. CI runs the checks on all three platforms, verifies that the tag matches
   `ModuleVersion`, publishes the exact verified Ubuntu `.nupkg` artifact to the
   PowerShell Gallery (without rebuilding it), and creates a GitHub release with
   the CHANGELOG section as release notes.

Publishing needs a PowerShell Gallery API key in the `PSGALLERY_API_KEY` secret
of the `psgallery` environment (Settings → Environments).

## License
MIT
