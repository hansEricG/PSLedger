# Bankimport och bankavstämning i PSLedger

Bankmodulen läser in kontoutdrag från banken, matchar transaktionerna mot
kundfakturor, leverantörsfakturor och redan bokförda verifikationer och bokför
det som går att bokföra automatiskt. Till sist stäms bankkontot i bokföringen
(t.ex. 1930) av mot bankens saldo.

Arbetsflödet är:

1. **Importera** kontoutdraget (camt.053 eller CSV) med `Import-LedgerBankStatement`.
2. **Matcha och bokför** med `Invoke-LedgerBankMatching`.
3. **Hantera resten** för hand med `Set-LedgerBankTransaction`.
4. **Stäm av** med `Get-LedgerBankReconciliation`.

## Datamodell

Bankmodulen lägger till en katalog i journalen (additivt – inga befintliga filer
ändras och ingen schemamigrering krävs):

```
MinFirma.ledger/
└── bank/
    ├── rules.txt        # Konteringsregler: Mönster  Konto  Beskrivning  Momssats  Momskonto
    ├── stmt0001.txt     # Ett kontoutdrag per import
    └── stmt0002.txt
```

En kontoutdragsfil innehåller metadata (bankkonto i bokföringen, period,
ingående och utgående saldo) och en `Transactions:`-sektion med en transaktion
per rad: id, datum, belopp, bankens referens, betalningsreferens (OCR), motpart,
text, status, matchningstyp, matchningsreferens, räkenskapsår och
verifikationsnummer. Belopp lagras med punkt som decimaltecken.

Varje transaktion har ett id som är unikt i hela journalen och en status:

| Status | Betydelse |
|--------|-----------|
| `Unmatched` | Inte bokförd eller kopplad ännu |
| `Matched` | Kopplad till en verifikation (ny eller befintlig) |
| `Ignored` | Hanteras utanför PSLedger |

## 1. Importera kontoutdrag

### camt.053 (rekommenderas)

De flesta svenska banker, även Swedbank, kan leverera kontoutdrag som ISO 20022
camt.053 (XML). Formatet innehåller ingående och utgående saldo, strukturerade
OCR-referenser och motpartens namn, vilket ger bäst matchning.

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

Import-LedgerBankStatement -Path .\kontoutdrag-2024-03.xml
```

- Bara bokförda poster (`BOOK`) importeras.
- En post med flera betalningar, t.ex. en samlad bankgiroinsättning med flera
  OCR-betalningar, delas upp i en transaktion per betalning.
- `-Account` anger bankkontot i bokföringen (standard `1930`). Ett
  bokföringskonto kan bara höra ihop med ett bankkonto (IBAN). Ett utdrag för
  ett annat bankkonto till samma bokföringskonto avvisas.
- Innehåller filen utdrag för flera bankkonton väljer du ett i taget med
  `-AccountId`, t.ex.
  `Import-LedgerBankStatement -Path .\alla.xml -AccountId 'SE45 5000 0000 0583 9825 7466' -Account 1930`.

### CSV från internetbanken

```powershell
Import-LedgerBankStatement -Path .\Swedbank-transaktioner.csv
```

Rubrikraden hittas automatiskt och rader före den (t.ex. Swedbanks rad
`* Transaktioner Period ...`) hoppas över. Kolumnerna känns igen på vanliga
namn:

| Fält | Kolumnnamn som känns igen |
|------|---------------------------|
| Datum | Bokföringsdag, Bokföringsdatum, Datum, Transaktionsdag |
| Belopp | Belopp |
| Text | Beskrivning, Text, Rubrik, Transaktion, Meddelande |
| Referens | Referens, OCR |
| Motpart | Motpart, Mottagare, Avsändare, Namn |
| Saldo | Bokfört saldo, Saldo |

Avgränsare (`;`, `,` eller tabb), decimaltecken och teckenkodning (UTF-8 eller
ISO-8859-1) känns också igen automatiskt. Med en saldokolumn räknas ingående och
utgående saldo fram, oavsett om filen listar nyaste eller äldsta transaktionen
först. Om banken använder andra kolumnnamn anges de explicit:

```powershell
Import-LedgerBankStatement -Path .\export.csv -Delimiter ';' -Encoding 'iso-8859-1' `
    -DateColumn 'Datum' -AmountColumn 'Belopp' -TextColumn 'Transaktion' -BalanceColumn 'Saldo'
```

### Dubbletter

Transaktioner som redan har importerats för samma bankkonto hoppas över, så
överlappande filer kan importeras utan risk. En transaktion känns igen på
bankens egen referens (camt.053) eller på datum, belopp, referens och text
(CSV). Två identiska kortköp samma dag i samma fil behålls båda.

```powershell
Get-LedgerBankStatement | Format-Table StatementNumber, FromDate, ToDate, OpeningBalance, ClosingBalance, Unmatched
```

## 2. Matcha och bokför automatiskt

```powershell
Invoke-LedgerBankMatching -WhatIf   # förhandsgranska
Invoke-LedgerBankMatching           # matcha och bokför
```

För varje omatchad transaktion prövas i tur och ordning:

| Steg | Matchning | Resultat |
|------|-----------|----------|
| 1. `Entry` | En befintlig verifikation med samma belopp på bankkontot inom `-DateTolerance` dagar (standard 3) som inte redan är kopplad | Kopplas – **ingen ny verifikation** |
| 2. `CustomerInvoice` | Inbetalning där kundfakturans OCR-nummer finns i referensen eller texten (eller fakturanumret och exakt restbelopp) | Registreras med `Add-LedgerInvoicePayment` |
| 3. `SupplierInvoice` | Utbetalning där leverantörsfakturans betalningsreferens eller leverantörens fakturanummer finns i betalningen (eller leverantörens namn och exakt restbelopp) | Registreras med `Add-LedgerSupplierPayment` |
| 4. `Rule` | Första konteringsregel vars mönster finns i motpart, text eller referens | Bokförs mot regelns konto |

Steg 1 gör att betalningar som redan bokförts för hand, t.ex. en lön via
`Invoke-LedgerPayrollPosting`, aldrig bokförs två gånger. En faktura matchas bara
när exakt en faktura passar. Delbetalningar hanteras, men en betalning som är
större än restbeloppet matchas inte automatiskt.

Kommandot returnerar ett objekt per matchad transaktion. Det som inte kunde
matchas ligger kvar som `Unmatched`:

```powershell
Get-LedgerBankTransaction -Status Unmatched | Format-Table TransactionId, Date, Amount, Counterparty, Text
```

### Konteringsregler

Återkommande transaktioner som inte är fakturabetalningar – bankavgifter,
räntor, överföringar till skattekontot, abonnemang – bokförs med
konteringsregler:

```powershell
Add-LedgerBankRule -Pattern 'Bankavgift' -Account 6570 -Description 'Bankavgift'
Add-LedgerBankRule -Pattern 'Skatteverket' -Account 1630 -Description 'Skattekonto'
Add-LedgerBankRule -Pattern 'Telia*' -Account 6212 -Description 'Mobiltelefon' -VatRate 0.25 -VatAccount 2640

Get-LedgerBankRule | Format-Table Priority, Pattern, Account, Description, VatRate
Remove-LedgerBankRule -Pattern 'Telia*'
```

- Ett mönster utan `*`/`?` matchar om motpart, text eller referens *innehåller*
  texten; med `*`/`?` är det ett wildcard-mönster mot hela värdet. Skiftläget
  spelar ingen roll.
- Reglerna prövas i den ordning de lades till och den första som matchar gäller.
- Med `-VatRate` räknas beloppet som inklusive moms och delas upp i netto på
  regelns konto och moms på `-VatAccount`. En Telia-räkning på 625 kr ger:

```
1930 Företagskonto   -625
6212 Mobiltelefon    +500
2640 Ingående moms   +125
```

### Flera bankkonton och skattekontot

Importera ett utdrag per konto, var och en till sitt eget bokföringskonto, och
kör sedan matchningen en gång. Den går igenom alla konton.

```powershell
Import-LedgerBankStatement -Path .\foretagskonto.csv -Account 1930
Import-LedgerBankStatement -Path .\sparkonto.csv     -Account 1940
Import-LedgerBankStatement -Path .\skattekonto.csv   -Account 1630
Invoke-LedgerBankMatching
```

En överföring mellan egna konton syns på båda utdragen men bokförs bara en gång:

- Är överföringen redan bokförd (t.ex. 1930 → 1940) kopplas båda sidorna till
  samma verifikation.
- Annars räcker det med en regel som pekar på det andra kontot, t.ex.
  `Add-LedgerBankRule -Pattern 'Skatteverket' -Account 1630`. Regeln bokför
  utbetalningen från 1930 och kopplar insättningen på skattekontot (motsatt
  belopp inom `-DateTolerance` dagar) till samma verifikation.
- En regel som pekar på transaktionens eget konto används inte.

Stäm sedan av varje konto för sig med `Get-LedgerBankReconciliation -Account`.

## 3. Hantera resten för hand

`Set-LedgerBankTransaction` löser en transaktion som inte kunde matchas:

```powershell
# Bokför mot ett motkonto (t.ex. ränteintäkt)
Set-LedgerBankTransaction -TransactionId 12 -Account 8310

# Bokför ett kortköp med moms
Set-LedgerBankTransaction -TransactionId 15 -Account 5410 -VatRate 0.25 -VatAccount 2640 -Description 'Kontorsmaterial'

# En kund betalade utan OCR – registrera på faktura 7
Set-LedgerBankTransaction -TransactionId 18 -InvoiceNumber 7

# Betalning av leverantörsfaktura 3
Set-LedgerBankTransaction -TransactionId 19 -SupplierInvoiceNumber 3

# Koppla till en verifikation som redan finns
Set-LedgerBankTransaction -TransactionId 20 -VerificationNumber 42

# Ignorera (t.ex. en transaktion före första räkenskapsåret)
Set-LedgerBankTransaction -TransactionId 21 -Ignore

# Ångra en matchning (verifikationen ligger kvar – vänd den med Add-LedgerReversal vid behov)
Set-LedgerBankTransaction -TransactionId 12 -Reset
```

Flera transaktioner kan hanteras via pipelinen:

```powershell
Get-LedgerBankTransaction -Status Unmatched | Where-Object Text -like '*Ränta*' |
    Set-LedgerBankTransaction -Account 8310
```

## 4. Bankavstämning

```powershell
$r = Get-LedgerBankReconciliation -Account 1930 -AsOf '2024-12-31'
$r | Format-List LedgerBalance, BankBalance, Difference, UnexplainedDifference, Status
$r.UnmatchedBankTransactions | Format-Table TransactionId, Date, Amount, Text
$r.UnmatchedLedgerEntries | Format-Table VerificationNumber, Date, Amount, Description
```

| Egenskap | Beskrivning |
|----------|-------------|
| `LedgerBalance` | Saldo på bankkontot i bokföringen: ingående balans + verifikationer t.o.m. datumet |
| `BankBalance` | Bankens saldo enligt importerade kontoutdrag (eller `-BankBalance`) |
| `Difference` | `LedgerBalance - BankBalance` |
| `UnmatchedBankTransactions` | Banktransaktioner som ännu inte finns i bokföringen |
| `UnmatchedLedgerEntries` | Verifikationer på bankkontot som inte är kopplade till någon banktransaktion |
| `UnexplainedDifference` | Differens som inte förklaras av de omatchade posterna – ska vara 0 |
| `Status` | `Reconciled`, `Differences` eller `NoBankBalance` |

Utan `-AsOf` används sista dagen som de importerade kontoutdragen täcker.
Bankens saldo hämtas från utgående saldo i det senaste kontoutdraget som slutar
senast på datumet, eller räknas fram från ingående saldo när datumet ligger
inom ett kontoutdrag. Om kontoutdragen saknar saldo (t.ex. en CSV utan
saldokolumn) anges saldot från internetbanken med `-BankBalance`.

Vid bokslutet bör `Status` vara `Reconciled` på balansdagen. Avstämningen
dokumenterar att posten Kassa och bank i balansräkningen stämmer.

## Kommandon

| Kommando | Beskrivning |
|----------|-------------|
| `Import-LedgerBankStatement` | Importera kontoutdrag (camt.053 eller CSV) |
| `Get-LedgerBankStatement` | Lista importerade kontoutdrag med saldon |
| `Get-LedgerBankTransaction` | Lista banktransaktioner, filtrera på status, period m.m. |
| `Invoke-LedgerBankMatching` | Matcha och bokför omatchade transaktioner automatiskt |
| `Set-LedgerBankTransaction` | Bokför, koppla, ignorera eller återställ en transaktion för hand |
| `Get-LedgerBankReconciliation` | Bankavstämning mot bokföringen |
| `Add-LedgerBankRule` | Lägg till en konteringsregel |
| `Get-LedgerBankRule` | Lista konteringsregler |
| `Remove-LedgerBankRule` | Ta bort en konteringsregel |

Se även [Fakturahantering](Fakturahantering.md) och
[Leverantörsreskontra](Leverantorsreskontra.md).
