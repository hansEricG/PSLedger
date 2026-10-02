# PSLedger file format

This document specifies how a PSLedger journal is stored on disk. The text
files are the product: they are the bookkeeping, and any tool (or a person with
a text editor) can read them without PowerShell.

The format described here is **schema version 2**, the version written by
PSLedger 0.13 and later. From version 1.0 the format is frozen: a change that
makes existing files invalid requires a new schema version and a migration (see
[Schema versions and compatibility](#schema-versions-and-compatibility)).

Words in capitals (MUST, SHOULD, MAY) describe what a writer (PSLedger or
another tool) has to do. The *Reading* notes describe what PSLedger tolerates
when it reads a file; they are not an invitation to write files that way.

## Contents

- [General conventions](#general-conventions)
- [Directory layout](#directory-layout)
- [Journal-level files](#journal-level-files): `journal.txt`, `accounts.txt`,
  `dimensions.txt`, `objects.txt`
- [Fiscal years](#fiscal-years): `year.txt`, `verNNNN.txt`, `verNNNN/`, `ib.txt`,
  `holdings.txt`, `report.txt`, `documents/`
- [Recurring entries](#recurring-entries): `recurring/`
- [Customers and invoices](#customers-and-invoices): `customers.txt`, `invoices/`
- [Suppliers and supplier invoices](#suppliers-and-supplier-invoices):
  `suppliers.txt`, `supplierinvoices/`
- [Payroll](#payroll): `employees.txt`, `payslips/`
- [Bank](#bank): `bank/stmtNNNN.txt`, `bank/rules.txt`
- [Time reporting](#time-reporting): `time/`
- [Other directories](#other-directories)
- [Schema versions and compatibility](#schema-versions-and-compatibility)

## General conventions

### Encoding and line endings

- Files MUST be UTF-8. PSLedger writes them without a byte order mark; readers
  also accept a BOM.
- Lines end with the platform's line ending: CRLF on Windows, LF on Linux and
  macOS. Readers accept both, so a journal can move between platforms.
- A final line ending is optional.

### Values

| Kind | Format | Example |
|------|--------|---------|
| Date | `yyyy-MM-dd` (ISO 8601) | `2024-03-25` |
| Amount | Invariant decimal: optional `-`, digits, optional `.` and fraction digits. No thousands separator, no currency. | `12500.00`, `-45`, `9000.0` |
| Rate | Decimal fraction, not a percentage | `0.25` (25 %), `0.3142` |
| Account | BAS account number, digits only | `1930` |
| Fiscal year id | Name of the fiscal-year directory | `2024-01_2024-12` |
| Flag | `1` for true; `0` or empty for false (see each file) | `1` |

- Amounts never use a decimal comma in stored files, whatever the culture of
  the computer that wrote them.
- The number of fraction digits is not significant: `12500`, `12500.0` and
  `12500.00` are the same amount.

### Signs

In verifications, opening balances and recurring entries a **positive amount is
a debit and a negative amount is a credit**. The rows of a verification MUST sum
to zero, after rounding to two decimals.

### Text fields

Free-text values (names, descriptions, references, comments) MUST be on a single
line and MUST NOT contain a tab. There is no quoting or escape syntax. PSLedger
writers replace each run of tabs and line breaks in free text with one space and
trim the value. Identifiers (customer, supplier, employee, account and object
numbers, recurring entry names) are never changed: a command given one that
contains a tab or a line break fails. The exception is `report.txt`, which has its
own syntax for text that spans several lines.

### Line styles

PSLedger files use three line styles. Each file uses one of them, or a
combination described in its own section:

1. **`Key: value`**: the key, a colon, a space and the value. Used by
   `journal.txt`, `year.txt`, verification headers and `report.txt`.
2. **`Key:<TAB>value`**: the key, a colon, a tab and the value. Used by the
   document files (invoices, supplier invoices, payslips, bank statements,
   recurring entries). An empty value is written as `Key:<TAB>` with nothing after
   the tab.
3. **Tab-separated records**: one record per line, fields separated by a single
   tab, fields in a fixed order. Missing trailing fields are read as empty or as
   the field's default. Columns after the last one listed in this document are
   ignored.

### Comments and blank lines

- Lines starting with `;` are comments in files that begin with a `; PSLedger …`
  line, and in all files under `time/` and `bank/`.
- `report.txt` uses `#` for comments.
- The register files (`accounts.txt`, `customers.txt`, `suppliers.txt`,
  `employees.txt`, `dimensions.txt`, `objects.txt`) have no comment syntax.
- Blank lines are ignored everywhere except where a section says otherwise.

### Numbered files

Verifications (`verNNNN.txt`), invoices (`invNNNN.txt`), supplier invoices
(`supNNNN.txt`), payslips (`payNNNN.txt`) and bank statements (`stmtNNNN.txt`)
are named by a prefix and a number zero-padded to at least four digits.

- Number 10000 is written `ver10000.txt`; nothing is truncated.
- A new document gets the highest existing number plus one, or 1 if there is
  none. Gaps are allowed.
- Verifications are numbered per fiscal year. Every other kind of document is
  numbered across the whole journal.

### Writing

PSLedger writes every journal file atomically: it writes the complete new content
to a temporary file (`.tmp_<guid>`) in the same directory and then renames it over
the target, so a reader sees either the old or the new file, never a half-written
one. Registers such as `customers.txt` are rewritten in full this way when a line
is added. Attachments and documents are copied or moved into place. A leftover
`.tmp_*` file after a crash can be deleted.

### Unknown content

Readers ignore keys and columns they do not know.

When PSLedger rewrites a file, it writes only the keys and columns listed in
this document, so unknown content is lost on the next update. Tools that need
to store their own data SHOULD use their own files.

## Directory layout

```
<name>.ledger/
├── journal.txt                 required: company metadata and schema version
├── accounts.txt                chart of accounts
├── dimensions.txt              dimensions (SIE #DIM)
├── objects.txt                 objects within dimensions (SIE #OBJEKT)
├── customers.txt               customer register
├── suppliers.txt               supplier register
├── employees.txt               employee register
├── <yyyy-MM>_<yyyy-MM>/        one directory per fiscal year
│   ├── year.txt                required: dates and status
│   ├── ib.txt                  opening balance
│   ├── holdings.txt            securities holdings at the balance date
│   ├── report.txt              annual report input
│   ├── ver0001.txt             verifications
│   ├── ver0001/                attachments of verification 1
│   └── documents/              other documents for the year
├── recurring/<name>.txt        recurring entry templates
├── invoices/inv0001.txt        customer invoices and credit notes
├── supplierinvoices/sup0001.txt
├── payslips/pay0001.txt
├── bank/
│   ├── stmt0001.txt            imported bank statements and their transactions
│   └── rules.txt               bank posting rules
├── time/
│   ├── resources.txt           people who report time
│   ├── projects.txt
│   └── 2024-04.txt             time entries, one file per calendar month
└── Extensions/                 PowerShell extensions for this journal
```

Only `journal.txt` and, for each fiscal year, `year.txt` are required. Every
other file and directory is created the first time it is needed, and a missing
file means "no records".

## Journal-level files

### `journal.txt`

Company metadata. Its presence is what makes a directory a journal.

```
; PSLedger Journal
; Created: 2024-01-15 09:30:00

SchemaVersion: 2
Name: Exempel AB
OrgNumber: 556677-8899
CompanyType: AB
VatNumber: SE556677889901
```

Style: `Key: value`. The `;` lines and the blank line are written by
`New-LedgerJournal` and are ignored when read.

| Key | Required | Value |
|-----|----------|-------|
| `SchemaVersion` | yes | Integer. The schema version of the whole journal; `2` for this specification. A journal without the key is version 1. |
| `Name` | yes | Company name. |
| `OrgNumber` | no | Organisation or personal identity number, e.g. `556677-8899`. |
| `CompanyType` | no | `AB`, `EF`, `HB` or `KB`. |
| *other* | no | Free metadata (`Set-LedgerJournal -Metadata`). The key starts with a letter followed by letters, digits or `_`. The value is a single line. Keys used by PSLedger include `VatNumber`, `Address`, `PostalCode`, `City`, `Phone`, `Email`, `Bankgiro`, `Plusgiro` and `Iban`. |

### `accounts.txt`

Chart of accounts, one account per line, in the order they were added.

```
1930<TAB>Företagskonto
2440<TAB>Leverantörsskulder
```

| # | Field | Value |
|---|-------|-------|
| 1 | Account number | Digits. Unique. |
| 2 | Name | Account name. |

Lines that do not start with digits and a tab are ignored. If the file exists,
every account used in a verification MUST be listed in it.

### `dimensions.txt`

```
1<TAB>Kostnadsställe
6<TAB>Projekt
```

| # | Field | Value |
|---|-------|-------|
| 1 | Dimension number | Integer, unique. Numbers follow SIE: 1 = cost centre, 6 = project. |
| 2 | Name | Dimension name. |

### `objects.txt`

```
1<TAB>10<TAB>Administration
```

| # | Field | Value |
|---|-------|-------|
| 1 | Dimension number | MUST exist in `dimensions.txt`. |
| 2 | Object number | Unique within the dimension. |
| 3 | Name | Object name. |

## Fiscal years

### Fiscal-year directory

A fiscal year is a directory named `<start yyyy-MM>_<end yyyy-MM>`, for example
`2024-01_2024-12` or `2024-07_2025-06` (a broken fiscal year). Directories whose
names do not match `^\d{4}-\d{2}_\d{4}-\d{2}$` are not fiscal years.

### `year.txt`

```
StartDate: 2024-01-01
EndDate: 2024-12-31
Status: Open
```

Style: `Key: value`. All three keys are required.

| Key | Value |
|-----|-------|
| `StartDate` | First day of the fiscal year. |
| `EndDate` | Last day of the fiscal year. |
| `Status` | `Open` or `Closed`. No verification can be added to a closed year. |

### `verNNNN.txt` — verifications

One file per verification (verifikation).

```
Date: 2024-02-01
Description: Kontorsmaterial

6110<TAB>800<TAB>{1:10}<TAB>Pennor
2640<TAB>200
1930<TAB>-1000
```

**Header** (style `Key: value`):

| Key | Required | Value |
|-----|----------|-------|
| `Date` | yes | Transaction date. MUST fall within the fiscal year. |
| `Description` | yes | Text of the verification. |

A blank line follows the header.

**Rows**: each line that starts with digits and a tab is a row.

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Account | yes | Account number. |
| 2 | Amount | yes | Positive for debit, negative for credit. |
| 3 | Objects | no | Object tag, see below. |
| 4 | Comment | no | Row text (radtext). |

- **Field 3 or 4.** Field 3 is read as the object tag only if it is enclosed in
  `{}`. Otherwise it is read as the comment, so a row MAY have a comment without
  objects.
- **Object tag.** Pairs of `dimension:object`, separated by commas and enclosed in
  braces, written in ascending dimension order, for example `{1:10,6:P1}`. Every
  dimension and object MUST exist in `dimensions.txt` and `objects.txt`.
- **Balance.** The amounts MUST sum to zero, after rounding to two decimals.
- **Immutability.** A verification is never changed after it has been written.
  Corrections are made with a new verification (`Add-LedgerReversal`).
- **Opening balance.** The opening balance is not a verification (see `ib.txt`),
  so the verification numbers match those of the source system after an SIE
  import.

### `verNNNN/` — attachments

Files attached to a verification (receipts, invoices) are stored unchanged in a
directory named after the verification, for example `ver0001/kvitto.pdf`. The
directory is optional.

File names are plain leaf names: no `/`, `\`, `.` or `..`.

### `ib.txt` — opening balance

The opening balance (ingående balans, SIE `#IB`), stored as metadata.

```
1930<TAB>25000
2081<TAB>-25000
```

| # | Field | Value |
|---|-------|-------|
| 1 | Account | Balance sheet account. |
| 2 | Amount | Opening balance, debit positive. |

- Accounts with a zero balance are left out.
- The rows SHOULD sum to zero; `Test-LedgerFiscalYear` reports it if they do not.
- Rows with a malformed account or amount are skipped with a warning.

### `holdings.txt` — securities holdings

Holdings of shares and funds at the balance date. They are used for the
shareholding note (not 1300/1399) and for the market value of the securities.

This is the only file with a header row. The header names the columns, so
readers map columns by name and accept them in any order.

```
Account<TAB>Name<TAB>Isin<TAB>Quantity<TAB>Price<TAB>Currency<TAB>FxRate<TAB>PriceDate<TAB>Source<TAB>BookValue<TAB>Cost
1310<TAB>Investor B<TAB>SE0015811963<TAB>100<TAB>250.5<TAB>SEK<TAB>1<TAB>2024-12-30<TAB><TAB>20000<TAB>20000
```

| Column | Required | Value |
|--------|----------|-------|
| `Account` | yes | Balance sheet account the holding is booked on. |
| `Name` | yes | Name of the security. (`Account`, `Name`) identifies the holding. |
| `Isin` | no | ISIN code. |
| `Quantity` | yes | Number of shares or units. |
| `Price` | yes | Price per share or unit in `Currency`. |
| `Currency` | no | Currency code, e.g. `SEK`. |
| `FxRate` | no | Rate to SEK (`1` for SEK). |
| `PriceDate` | no | Date of the price. |
| `Source` | no | Where the price came from (free text). |
| `BookValue` | no | Book value in SEK. |
| `Cost` | no | Acquisition cost in SEK. |

- Rows are written sorted by `Account` and `Name`.
- The file is deleted when its last holding is removed.

### `report.txt` — annual report input

Text and figures for the annual report that cannot be derived from the
bookkeeping.

```
# PSLedger annual report input
AverageEmployees: 1
SigningPlace: Stockholm
SigningDate: 2025-03-15

## SignificantEvents
Bolaget har startat sin verksamhet.
Under året har två nya kunder tillkommit.
```

- **Single-line values** use the style `Key: value`.
- **Multi-line values.** A value that spans several lines is written as a block:
  a line `## Key`, followed by the text. A block runs until the next `## ` line or
  the end of the file. Blank lines at the end of a block are removed.
- **Order.** All single-line values come before any block.
- **Comments.** Lines starting with `#` (but not `## `) are comments.

| Key | Value |
|-----|-------|
| `SignificantEvents` | Väsentliga händelser under räkenskapsåret. |
| `ProposedDividend` | Proposed dividend (amount). |
| `AverageEmployees` | Integer. |
| `SecuritiesMarketValue` | Amount. |
| `SigningPlace`, `SigningDate` | Place and date of signing. |
| `AnnualMeetingDate` | Date of the annual general meeting. |
| `CertificatePlace`, `CertificateSigner` | Fastställelseintyg. |
| `Framework` | `K2` or `K3`. |
| `ComparativeFiguresNote`, `TransitionNote`, `DeferredTaxStatement` | Text. |
| `PledgedAssets`, `ContingentLiabilities` | Ställda säkerheter and eventualförpliktelser (text). |
| `Ownership`, `EventsAfterBalanceDate` | Text. |

An empty value is not written. When `Set-LedgerReportInput` updates the file,
keys other than those listed above are dropped.

### `documents/`

Documents that belong to the fiscal year but not to a single verification (for
example contracts or the signed annual report). They are stored unchanged under
their original file names.

## Recurring entries

### `recurring/<name>.txt`

A template for a verification that is booked every month
(`Invoke-LedgerRecurringEntry`). The file name is the template's name.

```
Name:<TAB>hyra
Description:<TAB>Lokalhyra
Schedule:<TAB>Monthly
DayOfMonth:<TAB>1
StartDate:<TAB>2024-01-01
EndDate:<TAB>2024-12-31
LastGenerated:<TAB>2024-03-01
Rows:
5010<TAB>5000
1930<TAB>-5000
```

**Header** (style `Key:<TAB>value`), followed by a line `Rows:`:

| Key | Required | Value |
|-----|----------|-------|
| `Name` | yes | Same as the file name. |
| `Description` | yes | Description of the generated verifications. |
| `Schedule` | yes | `monthly` (the only supported schedule). Stored as given; readers compare case-insensitively. |
| `DayOfMonth` | yes | 1–28. |
| `StartDate` | yes | First possible date. |
| `EndDate` | no | Last possible date. Empty means no end. |
| `LastGenerated` | no | Date of the last generated verification. Empty until the first run. |

**Rows**: tab-separated records of account and amount (debit positive). The
amounts MUST sum to zero.

## Customers and invoices

### `customers.txt`

```
10<TAB>Volvo AB<TAB>556012-5790<TAB>faktura@volvo.example<TAB>30<TAB>1100
```

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Customer number | yes | Unique, no tab. |
| 2 | Name | yes | |
| 3 | Org number | no | |
| 4 | Email | no | |
| 5 | Payment terms | no | Days, 0–3650. Empty means 30. |
| 6 | Hourly rate | no | Default hourly rate for time reporting, excluding VAT. |

### `invoices/invNNNN.txt` — customer invoices

Customer invoices and credit notes share one number series.

```
; PSLedger Invoice
InvoiceNumber:<TAB>1
CustomerNumber:<TAB>10
InvoiceDate:<TAB>2024-03-01
DueDate:<TAB>2024-03-31
Description:<TAB>Konsultuppdrag
Status:<TAB>Paid
ReceivableAccount:<TAB>1510
BookedVerification:<TAB>2
BookedFiscalYear:<TAB>2024-01_2024-12
ReminderCount:<TAB>0
LastReminderDate:<TAB>
Rows:
3010<TAB>10000<TAB>0.25<TAB>2610<TAB>Konsulttimmar<TAB>10<TAB>h<TAB>1000
Payments:
2024-03-25<TAB>12500<TAB>3<TAB>2024-01_2024-12
Charges:
```

The file has four parts, in this order: a header (style `Key:<TAB>value`), then
the sections `Rows:`, `Payments:` and `Charges:`. Each section starts with its
name on a line of its own and contains tab-separated records. All three section
lines are always written, even when a section is empty.

**Header**

| Key | Required | Value |
|-----|----------|-------|
| `InvoiceNumber` | yes | Same as the number in the file name. |
| `CustomerNumber` | yes | MUST exist in `customers.txt`. |
| `InvoiceDate` | yes | |
| `DueDate` | yes | |
| `Description` | yes | |
| `Status` | yes | See the status list below. |
| `ReceivableAccount` | yes | Usually `1510`. |
| `BookedVerification` | after posting | Number of the verification that posted the invoice. |
| `BookedFiscalYear` | after posting | Fiscal year of that verification. |
| `ReminderCount` | no | Number of reminders sent. Empty means 0. |
| `LastReminderDate` | no | Date of the last reminder. |

The OCR reference is not stored. It is computed from the invoice number (Luhn
check digit with length digit).

**Status** goes through these values:

- `Draft`: created, not yet posted.
- `Booked`: posted.
- `Partial`: partly paid.
- `Paid`: fully paid.
- `Credited`: credited. Only a `Booked` invoice can be credited. The original
  and its credit note both get status `Credited`. The credit note has negated
  rows and the description `Kreditfaktura för faktura N`.

**`Rows:`**

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Account | yes | Revenue account. |
| 2 | Net amount | yes | Excluding VAT. Negative on credit notes. |
| 3 | VAT rate | no | Fraction; empty means 0. |
| 4 | VAT account | if VAT rate > 0 | Output VAT account, e.g. `2610`. |
| 5 | Description | no | Row text on the invoice. |
| 6 | Quantity | no | |
| 7 | Unit | no | E.g. `h`, `st`. |
| 8 | Unit price | no | Excluding VAT. |

The VAT amount is computed for each row as net amount × VAT rate, rounded to
two decimals. It is not stored.

**`Payments:`**

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Date | yes | Payment date. |
| 2 | Amount | yes | Amount paid. |
| 3 | Verification | no | Number of the verification that booked the payment. |
| 4 | Fiscal year | no | Fiscal year of that verification. |

**`Charges:`** fees and interest added after posting. Reminder fees are only
stored here when they are booked.

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Date | yes | |
| 2 | Type | yes | `Fee` or `Interest`. |
| 3 | Amount | yes | No VAT. |
| 4 | Account | yes | Revenue account the charge was booked on. |
| 5 | Verification | no | |
| 6 | Fiscal year | no | |

The totals are computed from the rows, charges and payments:

- *Total* = net amounts + VAT + charges.
- *Remaining* = Total − payments.

## Suppliers and supplier invoices

### `suppliers.txt`

```
100<TAB>Telia AB<TAB>556103-4249<TAB>faktura@telia.example<TAB>20
```

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Supplier number | yes | Unique, no tab. |
| 2 | Name | yes | |
| 3 | Org number | no | |
| 4 | Email | no | |
| 5 | Payment terms | no | Days, 0–3650. Empty means 30. |

### `supplierinvoices/supNNNN.txt`

```
; PSLedger Supplier Invoice
InvoiceNumber:<TAB>1
SupplierNumber:<TAB>100
SupplierInvoiceNo:<TAB>T-4711
InvoiceDate:<TAB>2024-03-05
DueDate:<TAB>2024-03-25
Description:<TAB>Telefoni mars
Status:<TAB>Paid
PayableAccount:<TAB>2440
Reference:<TAB>
BookedVerification:<TAB>4
BookedFiscalYear:<TAB>2024-01_2024-12
Rows:
6210<TAB>400<TAB>0.25<TAB>2640
Payments:
2024-03-25<TAB>500.00<TAB>5<TAB>2024-01_2024-12
```

The file is a header followed by the sections `Rows:` and `Payments:`.

| Key | Required | Value |
|-----|----------|-------|
| `InvoiceNumber` | yes | PSLedger's own number (löpnummer). |
| `SupplierNumber` | yes | MUST exist in `suppliers.txt`. |
| `SupplierInvoiceNo` | no | The supplier's invoice number. Shown by the commands as `SupplierReference`. |
| `InvoiceDate`, `DueDate`, `Description` | yes | |
| `Status` | yes | `Draft`, `Booked`, `Partial` or `Paid`. |
| `PayableAccount` | yes | Usually `2440`. |
| `Reference` | no | OCR number or message to use when paying. |
| `BookedVerification`, `BookedFiscalYear` | after posting | |

- **Rows:** account, net amount, VAT rate, VAT account. These are the same as the
  first four columns of a customer invoice row; the VAT account is input VAT,
  e.g. `2640`.
- **Payments:** same as for customer invoices.

## Payroll

### `employees.txt`

```
1<TAB>Anna Andersson<TAB>19800101-1234<TAB>7210<TAB>0.3
```

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Employee number | yes | Unique, no tab. |
| 2 | Name | yes | |
| 3 | Personal identity number | no | `YYYYMMDD-XXXX`. |
| 4 | Salary account | no | Empty means `7210`. |
| 5 | Tax rate | no | Fraction for preliminary tax; empty means 0. |

### `payslips/payNNNN.txt`

```
; PSLedger Payslip
PayslipNumber:<TAB>1
EmployeeNumber:<TAB>1
PayDate:<TAB>2024-03-25
PeriodStart:<TAB>2024-03-01
PeriodEnd:<TAB>2024-03-31
Description:<TAB>Lön
Status:<TAB>Booked
GrossSalary:<TAB>30000
TaxAmount:<TAB>9000.0
EmployerContributionRate:<TAB>0.3142
SalaryAccount:<TAB>7210
TaxLiabilityAccount:<TAB>2710
NetPayAccount:<TAB>1930
EmployerContributionAccount:<TAB>7510
EmployerContributionLiabilityAccount:<TAB>2730
BookedVerification:<TAB>6
BookedFiscalYear:<TAB>2024-01_2024-12
```

Style: `Key:<TAB>value` only, with no sections.

| Key | Required | Value |
|-----|----------|-------|
| `PayslipNumber` | yes | Same as the number in the file name. |
| `EmployeeNumber` | yes | MUST exist in `employees.txt`. |
| `PayDate` | yes | |
| `PeriodStart`, `PeriodEnd` | no | Salary period. |
| `Description` | yes | |
| `Status` | yes | `Draft` or `Booked`. |
| `GrossSalary` | yes | Greater than 0. |
| `TaxAmount` | yes | Preliminary tax withheld, between 0 and `GrossSalary`. |
| `EmployerContributionRate` | yes | Fraction, e.g. `0.3142`. |
| `SalaryAccount`, `TaxLiabilityAccount`, `NetPayAccount`, `EmployerContributionAccount`, `EmployerContributionLiabilityAccount` | yes | Accounts used for posting (defaults 7210, 2710, 1930, 7510, 2730). |
| `BookedVerification`, `BookedFiscalYear` | after posting | |

The following values are computed when the payslip is read and are not stored:

- Net pay = `GrossSalary` − `TaxAmount`.
- Employer contribution = `GrossSalary` × `EmployerContributionRate`, rounded to
  two decimals.

## Bank

### `bank/stmtNNNN.txt` — bank statements

Each import creates one statement file. The file holds the statement metadata
and its transactions. Each transaction records whether and how it has been
matched to the bookkeeping.

```
; PSLedger Bank Statement
StatementNumber:<TAB>1
BankAccount:<TAB>1930
Source:<TAB>Csv
FileName:<TAB>bank.csv
StatementId:<TAB>
AccountId:<TAB>
Currency:<TAB>
FromDate:<TAB>2024-03-25
ToDate:<TAB>2024-03-31
OpeningBalance:<TAB>24500.00
ClosingBalance:<TAB>36455.00
ImportedDate:<TAB>2024-04-02
Transactions:
1<TAB>2024-03-25<TAB>12500.00<TAB><TAB>133<TAB><TAB>Volvo AB<TAB>Matched<TAB>Entry<TAB>2024-01_2024-12/3<TAB>2024-01_2024-12<TAB>3
3<TAB>2024-03-31<TAB>-45.00<TAB><TAB><TAB><TAB>Bankavgift<TAB>Matched<TAB>Rule<TAB>Bankavgift<TAB>2024-01_2024-12<TAB>7
```

**Header** (style `Key:<TAB>value`), followed by a line `Transactions:`:

| Key | Required | Value |
|-----|----------|-------|
| `StatementNumber` | yes | Same as the number in the file name. |
| `BankAccount` | yes | The ledger account the statement belongs to, e.g. `1930` or `1630` (tax account). |
| `Source` | yes | Import format: `Camt053` or `Csv` (case-insensitive). |
| `FileName` | no | Name of the imported file. |
| `StatementId` | no | The bank's statement id (camt.053). |
| `AccountId` | no | The bank account, normally an IBAN. A ledger account is tied to one `AccountId`. |
| `Currency` | no | E.g. `SEK`. |
| `FromDate`, `ToDate` | no | Period covered. |
| `OpeningBalance`, `ClosingBalance` | no | The bank's balances. |
| `ImportedDate` | yes | Date of the import. |

**Transactions** are tab-separated records. Each needs at least the first three
fields:

| # | Field | Value |
|---|-------|-------|
| 1 | Transaction id | Integer, unique across all statements in the journal. |
| 2 | Date | Booking date. |
| 3 | Amount | Positive for money in, negative for money out. |
| 4 | Bank reference | The bank's unique id for the transaction. |
| 5 | Reference | OCR number or message. |
| 6 | Counterparty | |
| 7 | Text | |
| 8 | Status | `Unmatched` (also when empty), `Matched` or `Ignored`. |
| 9 | Match type | `Entry`, `CustomerInvoice`, `SupplierInvoice`, `Rule` or `Manual`; `Ignored` for ignored transactions; empty if unmatched. |
| 10 | Match reference | What the transaction was matched to. Its value depends on the match type: `<fiscal year>/<verification>` for `Entry`; the invoice number for `CustomerInvoice` and `SupplierInvoice`; the rule pattern for `Rule`; the account for `Manual`. |
| 11 | Fiscal year | Fiscal year of the linked verification. |
| 12 | Verification | Number of the linked verification. |

- **Links between bank accounts.** A transfer between two of the company's own
  bank accounts is booked once. Both accounts' transactions then link to the same
  fiscal year and verification.
- **Duplicates.** A transaction counts as already imported in two cases:
  - it has the same bank reference as an existing transaction on the same ledger
    account;
  - it has no bank reference, but the same date, amount, reference and text as an
    existing transaction.

### `bank/rules.txt` — posting rules

Rules used by `Invoke-LedgerBankMatching`. The first rule that matches wins.

```
; PSLedger bank rules: Pattern, Account, Description, VatRate, VatAccount
Bankavgift<TAB>6570<TAB>Bankavgift<TAB>0<TAB>
Telia*<TAB>6210<TAB>Telefoni<TAB>0.25<TAB>2640
```

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Pattern | yes | Matched against the counterparty, text and reference, ignoring case. A pattern without `*` or `?` matches when the field contains it; with `*` or `?` it is a wildcard pattern. |
| 2 | Account | yes | Account the transaction is posted against. |
| 3 | Description | no | Description of the verification. |
| 4 | VAT rate | no | Empty means 0. If set, VAT is split out of the amount. |
| 5 | VAT account | if VAT rate > 0 | |

## Time reporting

All time-reporting files are tab-separated records without a header row. Lines
starting with `;` are comments.

### `time/resources.txt`

People who report time: yourself, employees and subcontractors.

```
anna<TAB>Anna Andersson<TAB>1<TAB><TAB>450<TAB>1
```

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Resource id | yes | Unique. |
| 2 | Name | yes | |
| 3 | Employee number | no | Link to `employees.txt`. |
| 4 | Supplier number | no | Link to `suppliers.txt` (subcontractor). |
| 5 | Cost rate | no | Cost per hour, used for margin. |
| 6 | Default | no | `1` for the resource used when none is given. At most one resource has it. |

### `time/projects.txt`

```
P1<TAB>Volvo integration<TAB>10<TAB>1200<TAB>Active
```

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Project number | yes | Unique. |
| 2 | Name | yes | |
| 3 | Customer number | no | Empty for an internal project; time on it is never billable. |
| 4 | Hourly rate | no | Overrides the customer's hourly rate. |
| 5 | Status | no | `Active` (also when empty) or `Closed`. No new time can be reported on a closed project. |

### `time/yyyy-MM.txt` — time entries

One file per calendar month, named after the month of the entries' date (e.g.
`2024-04.txt`). A month file is deleted when its last entry is removed.

```
1<TAB>2024-04-02<TAB>anna<TAB>P1<TAB>10<TAB>7.5<TAB>1<TAB>1200<TAB>Analys<TAB>2
2<TAB>2024-04-03<TAB>anna<TAB>P1<TAB>10<TAB>2<TAB>0<TAB>1200<TAB>Möte<TAB>
```

| # | Field | Required | Value |
|---|-------|----------|-------|
| 1 | Entry id | yes | Integer, unique across all month files. |
| 2 | Date | yes | |
| 3 | Resource id | yes | MUST exist in `resources.txt`. |
| 4 | Project number | no | |
| 5 | Customer number | if billable | Taken from the project when there is one. |
| 6 | Hours | yes | Decimal hours, greater than 0 and at most 24 (`7.5` = 7 h 30 min). |
| 7 | Billable | no | `0` = not billable; `1` or anything else (including empty or missing) = billable. |
| 8 | Rate | if billable | Hourly rate when the entry was created: the explicit rate, otherwise the project rate, otherwise the customer rate. |
| 9 | Text | no | |
| 10 | Invoice number | no | The invoice the entry was billed on. |

Lines with fewer than six fields are skipped.

Invoiced entries are locked: they cannot be changed or removed.

- An entry counts as invoiced when field 10 refers to an invoice that exists and
  whose status is not `Credited`.
- Crediting the invoice unlocks its entries again.

## Other directories

- **`Extensions/`** holds PowerShell scripts (`*.ps1`) that are loaded when the
  journal is selected with `Set-LedgerCurrentJournal`. They are code, not
  bookkeeping data, and are not covered by the schema version.
- **Backups** (`Backup-LedgerJournal`) are zip files of the whole journal
  directory, named `<journal>_yyyy-MM-dd_HHmmss.zip`. They are stored outside the
  journal and contain the files exactly as specified here.

## Schema versions and compatibility

### What the schema version is

`SchemaVersion` in `journal.txt` is the version of this file format. It is
independent of the module version: a new PSLedger release does not change it
unless the format changes.

| Schema version | Introduced | Change |
|----------------|------------|--------|
| 1 | — | Original format, without the `SchemaVersion` key. The opening balance was stored as verification 1 with the description `Ingående balans`. |
| 2 | 0.10 | The opening balance moved to `ib.txt`, and the remaining verifications were renumbered from 1. |

PSLedger checks the schema version of the journal before it reads or writes:

- **Older journal.** Reading commands warn once per session. Writing commands
  stop with an error that points to `Update-LedgerJournal`, which runs the
  migrations in order and then updates `SchemaVersion`.
- **Newer journal** (written by a later PSLedger). Writing commands stop and
  reading commands warn. Upgrade PSLedger before you write to such a journal.

### When the schema version is bumped

From version 1.0, the rules are as follows.

**Breaking changes bump the version.** A change is breaking if a file that is
valid under the current schema would be invalid or mean something else under
the new one. Examples:

- renaming, removing or reordering a key or column;
- changing the format or meaning of a value (a date format, the sign of amounts,
  a status value);
- moving or renaming a file or directory;
- making an optional field required.

A breaking change requires all of the following, in the same release:

1. Increase `$script:CurrentSchemaVersion` in `Private/JournalSchema.ps1`.
2. Write a migration function `Invoke-Ledger<Name>Migration` in
   `Private/Migrations.ps1`. It converts a journal from the previous version,
   supports `-WhatIf`, and is safe to run again on a journal that is already
   partly migrated.
3. Register the migration in `$script:LedgerSchemaMigrations`, under the version
   it migrates *from*.
4. Add tests that migrate a journal in the old format and read it with the
   current commands.
5. Update this document, including the version table above.
6. Describe the change in the CHANGELOG under **Changed**, and say that
   `Update-LedgerJournal` must be run.

**Additive changes do not bump the version.** A change is additive if every
existing journal stays valid without being touched. Examples:

- a new optional file or directory;
- a new optional key;
- a new optional column after the last existing one.

Readers MUST treat a missing value as the documented default. Additive changes
are documented here and in the CHANGELOG, but need no migration.

**Downgrading PSLedger is not supported.** An older version does not know about
keys added later and drops them when it rewrites a file. Restore a backup
instead of downgrading.

### Contract test

`Tests/FileFormat.Tests.ps1` reads a reference journal written in this format
(`Tests/Fixtures/FileFormat/Exempel.ledger`) and checks the values the
commands return. The reference journal MUST NOT be changed to make a failing
test pass. If a change in PSLedger breaks the test, the change is breaking and
needs a schema bump and a migration, or it has to be undone.
