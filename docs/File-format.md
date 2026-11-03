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
  `dimensions.txt`, `objects.txt`, `vat.txt`
- [Fiscal years](#fiscal-years): `year.txt`, `closing.txt`, `verNNNN.txt`,
  `verNNNN/`, `ib.txt`, `holdings.txt`, `report.txt`, `documents/`, `integrity.txt`
- [Recurring entries](#recurring-entries): `recurring/`
- [Customers and invoices](#customers-and-invoices): `customers.txt`, `invoices/`
- [Suppliers and supplier invoices](#suppliers-and-supplier-invoices):
  `suppliers.txt`, `supplierinvoices/`
- [Payroll](#payroll): `employees.txt`, `payslips/`
- [Bank](#bank): `bank/stmtNNNN.txt`, `bank/rules.txt`
- [Time reporting](#time-reporting): `time/`
- [Other directories](#other-directories)
- [Archive packages](#archive-packages): `manifest.txt`, `checksums.txt`
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
to zero after rounding to two decimals under the schema 2 compatibility rule.
Current `Add-LedgerEntry` imposes a stricter writing rule: every amount is in
whole öre (at most two decimals) and the decimal sum is exactly zero. Historical
verifications remain readable; exact reversals of them retain their precision
and any difference allowed by the legacy rule (see `verNNNN.txt`).

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
  line, in `vat.txt`, and in all files under `time/` and `bank/`.
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
  none. For verifications, the maximum also includes numbers reserved by
  `invoices/posting/invNNNN.txt`, `supplierinvoices/posting/supNNNN.txt`,
  `invoices/payments/<guid>.txt`, `supplierinvoices/payments/<guid>.txt`,
  `invoices/charges/<guid>.txt`, `invoices/credits/invNNNN.txt`,
  `payslips/posting/payNNNN.txt`, `bank/posting/txnN.txt` and `<year>/closing.txt`. For customer invoices, the maximum also includes the
  credit-note numbers reserved by `invoices/credits/invNNNN.txt`.
  Recovery uses its already reserved number,
  even if later numbers have since been written. Gaps are allowed.
- Verifications are numbered per fiscal year. Every other kind of document is
  numbered across the whole journal.

### Writing

PSLedger writes every journal file atomically: it writes the complete new content
to a temporary file (`.tmp_<guid>`) in the same directory and then renames it over
the target, so a reader sees either the old or the new file, never a half-written
one. Registers such as `customers.txt` are rewritten in full this way when a line
is added. Attachments and documents are copied or moved into place. A leftover
`.tmp_*` file after a crash can be deleted.

The one exception is `integrity.txt`, which is append-only: new records are
appended to the end of the file. An interrupted append can leave an incomplete
last line, which `Test-LedgerIntegrity` reports as `Malformed`.

### Runtime coordination

The journal root MAY contain an empty `.write.lock` file. This is a runtime
coordination file, not bookkeeping data or a new schema version. Participating
writers hold an exclusive open handle while validating and writing a
verification and its integrity records. New verification files are published
without replacing an existing filename. The same journal lock covers attachment
changes, customer-invoice posting and payments, charges, reminders, bank imports and matching,
sealing, year closing and credit-note rollback.

The file remains after the handle is released, including after a crashed
process. Its existence does not indicate ownership. It MUST NOT be deleted or
replaced while writers may be active: doing so can let processes lock different
files at the same path. A competing writer waits up to 30 seconds before
reporting an error. Dry runs do not acquire or create the lock.

The supported storage model is a local filesystem with .NET file locking
enabled and cooperating writers. Other register/metadata writers and readers
are not yet covered by a journal-wide transaction or snapshot. This is not a
distributed lock for synchronised or network directories. An interrupted
operation can still leave a saved but unsealed verification; the integrity
check diagnoses that state. Customer-invoice posting and customer/supplier payments can resume
from their saved plans below; other multi-file recovery remains separate work.

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
├── vat.txt                     VAT box mapping overrides
├── customers.txt               customer register
├── suppliers.txt               supplier register
├── employees.txt               employee register
├── <yyyy-MM>_<yyyy-MM>/        one directory per fiscal year
│   ├── year.txt                required: dates and status
│   ├── closing.txt             unfinished fiscal-year closing plan
│   ├── ib.txt                  opening balance
│   ├── holdings.txt            securities holdings at the balance date
│   ├── report.txt              annual report input
│   ├── ver0001.txt             verifications
│   ├── ver0001/                attachments of verification 1
│   ├── integrity.txt           hash chain sealing verifications and attachments
│   └── documents/              other documents for the year
├── recurring/<name>.txt        recurring entry templates
├── invoices/inv0001.txt        customer invoices and credit notes
├── invoices/{posting,payments,charges,credits}/  customer-invoice recovery plans
├── supplierinvoices/sup0001.txt
├── payslips/pay0001.txt
├── payslips/posting/pay0001.txt  payroll posting plans
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

### `vat.txt`

Overrides how accounts are mapped to the boxes (rutor) of the VAT return by
`Get-LedgerVatReport` and `Export-LedgerVatDeclaration`. Without the file the
default BAS mapping is used.

```
; PSLedger VAT mapping: Account or range, Box
3300<TAB>39
3800-3899<TAB>-
```

Lines starting with `;` are comments. Each record has two tab-separated fields:

| # | Field | Value |
|---|-------|-------|
| 1 | Account or range | An account number, or two account numbers joined by `-` (inclusive). |
| 2 | Box | A box number of the VAT return, with or without a leading zero (`05` or `5`), or `-` for no box. Box 49 is always computed and cannot be mapped. |

- Records are matched in file order and take precedence over the default
  mapping; the first record that covers an account decides its box.
- A record that cannot be read, or names an unknown box, is an error: the VAT
  report fails rather than put amounts in the wrong box.
- `Convert-LedgerChart` rewrites the file in full (keeping its records) when it
  adds records, so comments other than the first line are lost.

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

### `closing.txt` — fiscal-year closing plan

`Close-LedgerFiscalYear` saves this immutable record before booking the result
or changing `Status`. The first line is `; PSLedger fiscal year closing`.

| Key | Value |
|-----|-------|
| `FormatVersion` | `1`. |
| `OperationId` | GUID (`D` form) written as `OperationId:` in the result verification. |
| `FiscalYear` | MUST match the directory name. |
| `ResultVerification` | Reserved result verification number, or `0` when no result is booked. |
| `ResultAmount` | Net result of classes 3–8 (negative for a profit). Absent with `-SkipResultEntry`; `0` when the result is zero. |
| `ResultAccount` | Debited for a profit. Only when `ResultVerification` > 0. |
| `EquityAccount` | Credited for a profit. Only when `ResultVerification` > 0. |
| `VerificationHash` | Lowercase SHA-256 of the planned verification (LF-normalised). Only when `ResultVerification` > 0. |

The file exists only while a close is unfinished. Repeating the command
resumes it: different options, a changed result, a differing saved verification
or other integrity issues stop recovery. A year whose `Status` is `Closed` but
that still has the plan is only sealed. The plan is deleted once the year is
closed and sealed. It is additive and does not change the schema version.

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
| `OperationId` | no | Non-empty GUID in `D` form identifying the customer-invoice posting, customer/supplier payment or bank posting plan. Included in the verification content hash; ordinary entries omit it. |

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
- **Balance.** The schema 2 compatibility rule requires amounts to sum to zero
  after rounding to two decimals. Current `Add-LedgerEntry` accepts only amounts
  in whole öre with an exact zero sum. `Add-LedgerReversal` may instead mirror a
  historical verification exactly under the compatibility rule, warning about
  extra decimals rather than silently rounding. This preserves the meaning of
  existing files and requires no schema migration.
- **Validation.** `Test-LedgerFiscalYear` sums verification rows as decimals.
  `VerificationPrecision` warns about amounts with more than two decimals;
  `VerificationsBalance` warns about a nonzero sum allowed by the compatibility
  rule and fails when the sum is outside that rule. A legacy warning also
  applies to an exact reversal containing the same historical precision.
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

### `integrity.txt` — tamper detection

An append-only hash chain that seals the year's verifications and attachments
(varaktighet). Optional: a year without it is reported as `Unsealed` by
`Test-LedgerIntegrity` until `Protect-LedgerFiscalYear` creates it. Year
documents (`documents/`), `ib.txt`, `holdings.txt` and `report.txt` are not
covered.

```
; PSLedger integrity chain
; Kind<TAB>Key<TAB>Sealed<TAB>Hash<TAB>ChainHash
Verification<TAB>1<TAB>2024-02-01T09:12:44Z<TAB>f323cf28…<TAB>0dd791c3…
Attachment<TAB>1/kvitto.pdf<TAB>2024-02-01T09:12:44Z<TAB>c0d47590…<TAB>b7844674…
AttachmentRemoved<TAB>1/kvitto.pdf<TAB>2024-02-03T15:00:02Z<TAB>c0d47590…<TAB>9a01c2e7…
```

Lines starting with `;` are comments. Each record has five tab-separated fields:

| Field | Description |
|---|---|
| Kind | `Verification`, `Attachment` or `AttachmentRemoved`. |
| Key | The verification number without zero padding (`1`), or `<number>/<file name>` for attachments. |
| Sealed | When the record was written, UTC, `yyyy-MM-ddTHH:mm:ssZ`. |
| Hash | SHA-256 of the item, 64 lowercase hex digits. For `AttachmentRemoved`, the hash of the file when it was removed. |
| ChainHash | SHA-256 of the UTF-8 text `<previous ChainHash><TAB><Kind><TAB><Key><TAB><Sealed><TAB><Hash>`, 64 lowercase hex digits. The first record uses 64 zeros as the previous ChainHash. |

**Content hash.** The hash is taken over the file's bytes, except that a file
without a NUL byte in its first 8000 bytes (the rule Git uses to detect text)
has every CRLF replaced by LF first. A journal checked out by Git on Windows and
on Linux therefore gives the same hashes. Binary files are hashed byte for byte.

**Rules.**

- `Add-LedgerEntry` appends a `Verification` record and `Add-LedgerAttachment`
  an `Attachment` record. When the year has no `integrity.txt` yet, every
  verification and attachment already in the year is sealed first, in
  verification-number order, each verification followed by its attachments.
- A sealed attachment cannot be replaced. `Remove-LedgerAttachment` appends an
  `AttachmentRemoved` record before deleting the file, after which the same name
  can be attached again.
- A verification is sealed once. Records are never changed or removed, except
  that a write that fails and is rolled back removes its own last record.
- `Close-LedgerFiscalYear` seals anything not yet sealed and returns the final
  ChainHash. The final ChainHash is the ChainHash of the last readable record.

The chain detects changes made without rebuilding it. Anyone who can edit the
files can also rebuild the chain, so keep the final ChainHash outside the journal
and check it with `Test-LedgerIntegrity -ExpectedHash`.

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

### `invoices/posting/invNNNN.txt` — customer-invoice posting plans

`Invoke-LedgerInvoicePosting` saves this immutable record before writing its
verification. The number in the filename identifies the customer invoice, not
the reserved verification. It uses `Key:<TAB>value` lines; `;` comments and blank
lines are ignored. All fields below are required, with no duplicates.

| Key | Value |
|-----|-------|
| `FormatVersion` | `1`. Other versions are rejected. |
| `OperationId` | Non-empty GUID in `D` form, matching the verification's optional header. |
| `InvoiceNumber` | Positive integer matching `invNNNN.txt`. |
| `FiscalYear` | Fiscal-year directory containing the reserved verification. |
| `VerificationNumber` | Positive integer reserved in that fiscal year. |
| `InvoiceHash` | Lowercase SHA-256 of the original draft invoice's text. |
| `VerificationHash` | Lowercase SHA-256 of the planned verification's text, including its operation identity. |

Hashes use UTF-8 text with CRLF normalised to LF, as for integrity content
hashes. The planned verification includes a final newline. The plan and the
optional verification header are additive schema changes, not a schema bump.
Existing invoices without plans remain readable and may be posted normally.

There is no mutable progress field: the plan, verification, integrity seal and
invoice posting references together determine progress. Repeating the posting
command for a draft invoice resumes its saved plan without replacing the
verification or appending a duplicate seal. The original invoice hash and any
saved verification's content and operation identity MUST match. Other integrity
issues, including an incomplete append, stop recovery rather than being repaired
automatically. A matching saved verification may complete the invoice status
after year closure; a missing verification MUST NOT be created in a closed year.
An already booked invoice retains the normal "already posted" error.

Plans MUST be retained unchanged after completion, together with backups.
Their reserved numbers are never automatically freed. Malformed records block
new-number allocation rather than allowing unsafe reuse. Archive packages copy
each included invoice's plan and cover it with archive checksums. A SIE export
does not contain these plans and is not a full recovery-state backup.

### `invoices/payments/<guid>.txt` — customer-invoice payment plans

Each payment has an immutable plan using the posting-plan fields above.
`OperationId` is the `PaymentId`, a non-empty GUID unique among payments in the
journal across both customer and supplier payment directories, and matching the
filename (without `.txt`). `InvoiceNumber` identifies
the invoice being paid. `InvoiceHash` covers the invoice immediately before this
payment, not its original draft. Three additional fields are required:

| Key | Value |
|-----|-------|
| `PaymentDate` | Payment date, `yyyy-MM-dd`. |
| `PaymentAmount` | Positive invariant decimal in whole ore, at most two fraction digits. |
| `PaymentAccount` | Cash/bank account number, digits only. |

Customer plans omit `InvoiceType` for backward compatibility; omission means
`Customer` only in `invoices/payments/`. An explicit type MUST agree with the
directory. Supplier plans use `supplierinvoices/payments/` and MUST explicitly
record `InvoiceType:<TAB>Supplier`; see the supplier section below. The type and
invoice number together identify the invoice. Duplicate payment IDs across
either directory are rejected.

Plans use the same hash normalisation, reservation, create-if-absent and retention
rules as posting plans. Payment inputs MUST agree with the saved verification's
date, accounts and amounts as well as its hash and operation identity. Recovery
never replaces an existing verification. In a closed year it may finish a payment
whose matching verification already exists, but cannot create a missing one.
Payment plans are additive; existing four-column invoice payment rows remain
unchanged, with fiscal year and verification number identifying the payment.

On retry, the original invoice hash MUST match unless that payment is already
recorded. A matching payment row, verification and integrity chain identify a
completed operation even if later payments have changed the invoice. Reusing
its ID returns the current invoice without adding a payment. Omitted inputs
use the saved plan; explicit conflicting inputs are rejected.

Without `PaymentId`, the command generates a new ID for each payment. An
unfinished payment prevents further payment, charge, reminder or credit writes
to that invoice and blocks unrelated bank matching until it is resumed with its ID.
Identical dates and amounts alone never deduplicate payments. Plans remain after
completion and are copied with included invoices into archives, with checksums.
A payment plan in the archived year also includes its invoice even if that invoice
belongs to an earlier year and the payment row has not yet been saved.
SIE exports do not retain them.

**Bank-originated customer and supplier payments** additionally require all three fields
below together (all are absent on ordinary payments). These are additive fields
in payment-plan format version 1:

| Key | Value |
|-----|-------|
| `BankTransactionId` | Positive journal-wide bank transaction ID. |
| `BankStatementNumber` | Positive statement number containing that transaction. |
| `BankTransactionHash` | Lowercase SHA-256 of the stable bank input fields below. |

The bank hash covers, in order, the statement number, transaction ID, ledger bank
account, ISO date, amount, bank reference, reference, counterparty and text,
separated by tabs and followed by one LF, encoded as UTF-8. The amount uses an
invariant decimal point without insignificant trailing fractional zeros. It is
positive for customer receipts and negative for supplier payments, while the
plan's `PaymentAmount` is always positive. Empty
fields remain empty. Status and match fields are excluded because they change
on completion or Reset. Other transactions in the statement are not hashed, so
their legitimate changes do not prevent recovery or get overwritten by it.

A bank-originated payment reserves its verification for that bank transaction.
Matching resumes saved plans before using amount/reference heuristics. It first
finishes or verifies the payment, then saves `CustomerInvoice` or `SupplierInvoice`
match type, invoice
number, fiscal year and verification number on the bank transaction. A matching
completed payment is reused even when the invoice has since changed. Bank input
or link conflicts stop recovery, including retries directly through `PaymentId`.
Reset clears only the bank link, never the plan: only the same payment may be
relinked. Duplicate transaction IDs or conflicting plans are rejected.

Existing payment plans without bank fields remain supported and are not
automatically associated with a bank transaction. Rule/account bank plans are
described below.

### `invoices/charges/<guid>.txt` — customer-invoice charge plans

`Add-LedgerInvoiceFee`, `Add-LedgerInvoiceInterest` and
`Add-LedgerInvoiceReminder -BookFee` save this immutable plan before writing the
charge verification. The first line is `; PSLedger customer invoice charge`.
It uses the posting-plan fields above. `OperationId` is the `ChargeId` and
matches the filename. `InvoiceHash` covers the invoice immediately before the
charge. Additional fields:

| Key | Required | Value |
|-----|----------|-------|
| `ChargeType` | yes | `Fee` or `Interest`. |
| `ChargeDate` | yes | Charge date, `yyyy-MM-dd`. |
| `ChargeAmount` | yes | Positive invariant decimal, at most two fraction digits. |
| `ChargeAccount` | yes | Income account credited, digits only. |
| `ReminderCount` | no | `Fee` only: the invoice's reminder count after a booked reminder fee. |

The charge row on the invoice is matched by fiscal year and verification number;
conflicting type, date, amount or account stop recovery. A retry with the same
`ChargeId` resumes the plan, or returns the invoice if the charge is recorded.
Explicit conflicting inputs are rejected. Interest resumes with the planned
amount instead of recalculating it. Without `ChargeId`, each call generates a
new ID. An unfinished charge blocks payments, other charges, reminders and
credits on that invoice and the error names the resume command. Plans follow
the posting-plan reservation, closed-year, retention and archive rules.

### `invoices/credits/invNNNN.txt` — customer credit plans

`Add-LedgerCreditInvoice` saves this immutable plan before writing the reversing
verification. The filename number is the **original** invoice. The first line
is `; PSLedger customer credit invoice`. It uses the posting-plan fields above,
where `InvoiceHash` covers the original invoice before crediting. Additional
required fields:

| Key | Value |
|-----|-------|
| `CreditInvoiceNumber` | Reserved credit-note number, unique among credit plans. |
| `CreditDate` | Credit date, `yyyy-MM-dd`. |

Recovery is forward-only: repeating the command writes or validates the
verification, its seal, the credit note (`Status: Credited`, negated rows,
`Kreditfaktura för faktura N`, total equal to the negated original total) and
finally marks the original `Credited`. A different explicit date or fiscal year
is rejected. Once the original is `Credited`, a repeat validates the result and
returns the existing credit note. An unfinished credit blocks payments and
charges on the invoice. Archives include the plan when either the original or
the credit note is included.

### `invoices/invNNNN.txt` — customer invoices

Customer invoices and credit notes share one number series. Numbers reserved by
credit plans are skipped when allocating new invoice numbers.

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
  rows and the description `Kreditfaktura för faktura N`. Charges on the original
  are reversed too: the credit note has negated charge rows dated on the credit
  date and referencing the credit verification.

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

### `supplierinvoices/payments/<guid>.txt` — supplier payment plans

Supplier payments use the same immutable version-1 plan and bank-origin fields
documented under customer payment plans, with the additional required field
`InvoiceType:<TAB>Supplier`. `InvoiceNumber` refers to `supNNNN.txt`, never
`invoices/invNNNN.txt`. The verification debits the invoice's payable account and
credits `PaymentAccount` by the positive `PaymentAmount`, in that row order.

Retry with `Add-LedgerSupplierPayment -PaymentId <guid>`, or repeat the bank match
using `-SupplierInvoiceNumber` or automatic matching. The same hash, reservation,
integrity, closed-year and completed-payment checks apply. Reset preserves supplier
payment ownership, even if a customer invoice has the same number.
Payment plans MUST remain after completion and in backups; archive packages copy
them with their invoices. These additive files do not change the schema version
or existing supplier payment rows.

### `supplierinvoices/posting/supNNNN.txt` — supplier-invoice posting plans

`Invoke-LedgerSupplierInvoicePosting` saves this immutable record before writing
its verification. It uses exactly the fields and rules of
`invoices/posting/invNNNN.txt`, with the additional required field
`InvoiceType:<TAB>Supplier`. The filename number and `InvoiceNumber` identify
`supNNNN.txt`, never a customer invoice. A customer posting plan MAY omit
`InvoiceType`, but if present it MUST be `Customer`; a plan whose type does not
match its directory is rejected.

Repeating the posting command for a draft supplier invoice resumes the plan with
the same hash, reservation, integrity, closed-year and "already posted" rules as
customer-invoice posting. The planned verification debits the cost and input-VAT
accounts and credits the payable account with the gross total. Plans MUST remain
after completion and in backups; archive packages copy them with their invoices.
They are additive and do not change the schema version.

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

### `payslips/posting/payNNNN.txt` — payroll posting plans

`Invoke-LedgerPayrollPosting` saves this immutable record before writing the
salary verification. The first line is `; PSLedger payslip posting`.

| Key | Value |
|-----|-------|
| `FormatVersion` | `1`. |
| `OperationId` | GUID (`D` form) written as `OperationId:` in the verification. |
| `PayslipNumber` | MUST match the filename. |
| `FiscalYear` | Fiscal-year directory of the verification. |
| `VerificationNumber` | Reserved verification number, greater than 0. |
| `PayslipHash` | Lowercase SHA-256 of the draft payslip file (LF-normalised). |
| `VerificationHash` | Lowercase SHA-256 of the planned verification (LF-normalised). |

Every key is required exactly once. Repeating the command for a draft payslip
resumes the plan: a changed payslip, a different `-FiscalYear`, a differing
saved verification or other integrity issues stop recovery. A saved verification
is sealed and the payslip marked `Booked` even if the year has since been
closed; a missing verification is never created in a closed year. Plans MUST
remain after completion and in backups; archive packages copy them with their
payslips. They are additive and do not change the schema version.

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

### `bank/posting/` — rule/account posting plans and transfer claims

`txn<id>.txt` is an immutable plan for one originating bank transaction.
Its filename uses the positive transaction ID without zero padding. Files are
UTF-8 lines of `Key:<TAB>Value`, with optional `;` comments. Duplicate keys,
malformed records and conflicting transaction ownership are rejected.

| Key | Value |
|-----|-------|
| `FormatVersion` | `1`; additive, no journal schema bump. |
| `OperationId` | Non-empty GUID in `D` form, also recorded in the verification. |
| `TransactionId`, `StatementNumber` | Positive source bank identities. |
| `BankHash` | Lowercase SHA-256 using the same stable bank-input hash as invoice payment plans. |
| `BankAccount`, `Account` | Bank and counter account numbers, digits only. |
| `Date`, `Amount` | ISO booking date and signed invariant decimal, at most two fraction digits. |
| `VatRate`, `VatAccount` | Nonnegative invariant VAT fraction and VAT account; the account may be empty when VAT is unused. |
| `Description` | Sanitised single-line verification description. |
| `MatchType`, `MatchRef` | `Manual` with counter account, or `Rule` with the original rule pattern. |
| `FiscalYear`, `VerificationNumber` | Fiscal-year directory and positive reserved verification number. |
| `VerificationHash` | Lowercase SHA-256 of the planned verification, including its operation ID and final LF. |
| `DateTolerance` | Saved counterpart date tolerance in days, 0–365. |

The plan is validated and published create-if-absent before posting; its
reservation participates in all verification allocation. Current rules are not
reapplied on retry. Saved verification hashes, dates, descriptions and rows MUST
agree with the plan. Recovery seals an existing matching verification once and
finishes bank links; it never replaces the verification or creates one in a
closed year.

For transfers without VAT, `counterpart<id>.txt` immutably claims one transaction
on the counter account. `<id>` is the originating transaction ID, while fields
`OperationId`, `TransactionId`, `StatementNumber` and `BankHash` identify the
operation and the selected counterpart. Its amount MUST be the opposite of the
source amount, within the saved date tolerance. Claims are published before
bank-state updates and retained after completion. A counterpart imported later
can be claimed without changing the original plan.

`ambiguous<id>.txt`, containing `OperationId`, records that nearest eligible
counterparts tied. The original transaction is still booked, but automatic
selection stops permanently for that plan. The user can explicitly select a
counterpart using `Set-LedgerBankTransaction -VerificationNumber -FiscalYear`;
that writes the same immutable counterpart claim. Neither marker nor claim is
removed on Reset. Reset permits only relinking the same posting on either side.

Retain all three record types in backups. Archives copy records for the selected
fiscal year and the referenced source/counterpart statements, including a
counterpart dated outside that year. SIE exports omit these recovery records.

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

## Archive packages

`Export-LedgerArchive` writes a fiscal year as a package outside the journal: a
zip file `<journal>_<fiscal year>_archive.zip` holding one folder with the same
name, or that folder alone with `-AsDirectory`. The package is not read back by
PSLedger, apart from `Test-LedgerArchive`.

```
<journal>_<fiscal year>_archive/
├── README.txt        description in Swedish
├── manifest.txt      see below
├── checksums.txt     see below
├── sie/<journal>_<fiscal year>.se
├── reports/          grundbok, huvudbok, saldobalans, resultatrakning,
│                     balansrakning, momsrapport (.txt, .pdf);
│                     arsredovisning (.md, .docx, .pdf)
└── journal/          a journal in the format of this document with only the
                      fiscal year: the journal-level registers, the whole
                      fiscal-year directory, and the year's invoices/,
                      supplierinvoices/, payslips/ and bank/stmtNNNN.txt
```

Journal files are copied byte for byte, so `integrity.txt` in `journal/` still
verifies. A report that could not be produced is left out and listed in the
manifest.

### `manifest.txt`

`Key<TAB>Value` lines; lines starting with `;` are comments.

| Key | Value |
|---|---|
| ArchiveFormat | `1` |
| Journal, OrgNumber | From `journal.txt`. |
| FiscalYear, StartDate, EndDate, YearStatus | From `year.txt`. |
| Preliminary | `True` if the year was open when it was archived. |
| Created | UTC, `yyyy-MM-ddTHH:mm:ssZ`. |
| PSLedgerVersion, SchemaVersion | The PSLedger version that wrote the package and the journal's schema version. |
| IntegrityStatus, ChainHash | The `Test-LedgerIntegrity` result for the year when it was archived. ChainHash is empty for an unsealed year. |
| Verifications, Attachments, Invoices, SupplierInvoices, Payslips, BankStatements | Counts. |
| Omitted | One line per report left out: `<path>: <reason>`. May repeat. |

### `checksums.txt`

One line per file in the package except `checksums.txt` itself, in the format
of `sha256sum`: the SHA-256 of the file's bytes as 64 lowercase hex digits, two
spaces and the path relative to the package folder with `/` separators. Lines
are sorted by path (ordinal). Unlike `integrity.txt`, line endings are not
normalised, because the package is stored as it was written.

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
