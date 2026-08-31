# Leverantörsreskontra i PSLedger

Leverantörsreskontran hanterar ett leverantörsregister och hela livscykeln för
en leverantörsfaktura – registrera, bokföra och betala. Precis som
kundreskontran ligger den som ett lager *ovanpå* bokföringen: både bokföring av
fakturan och registrering av en betalning skapar vanliga verifikationer. Därför
stämmer summan av de öppna leverantörsskulderna alltid mot saldot på
huvudbokskontot (2440 Leverantörsskulder).

En leverantörsfaktura går igenom statusarna **Draft → Booked → Partial → Paid**.

## Datamodell

Leverantörsreskontran lägger till två saker i journalen (bägge additiva – inga
befintliga filer ändras och ingen schemamigrering krävs):

```
MinFirma.ledger/
├── suppliers.txt            # Tab-separerat: Nummer  Namn  Org.nr  E-post  Betalvillkor(dagar)
└── supplierinvoices/        # En fil per leverantörsfaktura
    ├── sup0001.txt
    └── sup0002.txt
```

En leverantörsfakturafil (`sup0001.txt`) innehåller metadata (inkl. leverantörens
eget fakturanummer och en valfri betalningsreferens/OCR), en `Rows:`-sektion (en
kostnadsrad per rad: konto, nettobelopp, momssats, momskonto) och en
`Payments:`-sektion. Belopp lagras med punkt som decimaltecken (invariant kultur)
så att de tab-separerade kolumnerna inte bryts av ett lokalt kommatecken.

Fakturor lagras på journalnivå (inte inuti ett räkenskapsår) eftersom en faktura
kan betalas ett senare räkenskapsår än det den bokfördes i.

## Steg för steg

### 1. Lägg upp en leverantör

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

Add-LedgerSupplier -SupplierNumber '100' -Name 'Kontorsbolaget AB' `
    -OrgNumber '556006-8420' -Email 'faktura@kontorsbolaget.se' -PaymentTermsDays 30
```

`-PaymentTermsDays` (standard 30) styr hur förfallodatumet räknas ut på nya
fakturor. Uppdatera med `Set-LedgerSupplier` (bara de fält du anger ändras) och
lista med `Get-LedgerSupplier`.

```powershell
Set-LedgerSupplier -SupplierNumber '100' -Email 'ny@kontorsbolaget.se' -PaymentTermsDays 20
Get-LedgerSupplier | Format-Table SupplierNumber, Name, PaymentTermsDays
```

### 2. Registrera en leverantörsfaktura

Varje rad är en kostnadsrad med ett **nettobelopp** (exklusive moms), en valfri
momssats och kontot den ingående momsen bokförs på.

```powershell
$rows = @(
    @{ Account = '5010'; Amount = 8000; VatRate = 0.25; VatAccount = '2640' }
)
New-LedgerSupplierInvoice -SupplierNumber '100' -Date '2024-03-10' `
    -Description 'Lokalhyra mars' -SupplierInvoiceNo 'F-99123' -Reference '1234567' -Rows $rows
```

- Förfallodatum sätts automatiskt till fakturadatum + leverantörens
  betalningsvillkor. Ange `-DueDate` för att styra det manuellt.
- `-SupplierInvoiceNo` sparar leverantörens eget fakturanummer och `-Reference`
  leverantörens betalningsreferens/OCR.
- En momsfri rad utelämnar momsen (`VatRate = 0` och inget `VatAccount`).
- `-PayableAccount` styr skuldkontot (standard `2440`).
- Fakturanummer räknas upp automatiskt (`sup0001`, `sup0002`, …).

### 3. Bokför fakturan

Bokföringen skapar en verifikation: kostnadskonton debiteras med netto, ingående
moms debiteras och leverantörsskulden krediteras med bruttobeloppet.

```powershell
Invoke-LedgerSupplierInvoicePosting -InvoiceNumber 1
```

Ger verifikationen:

```
5010 Lokalhyra              +8000
2640 Ingående moms          +2000
2440 Leverantörsskulder    -10000
```

Räkenskapsåret hämtas från fakturadatumet (ange `-FiscalYear` för att styra
det). Fakturan får status `Booked`. Att bokföra en redan bokförd faktura ger ett
fel.

### 4. Registrera betalning

Betalningen skapar en verifikation som debiterar leverantörsskulden och
krediterar bank/kassa.

```powershell
# Full betalning – markerar fakturan som Paid
Add-LedgerSupplierPayment -InvoiceNumber 1 -Date '2024-04-05'
```

Ger verifikationen:

```
2440 Leverantörsskulder  +10000
1930 Företagskonto       -10000
```

- Utan `-Amount` betalas hela det återstående beloppet.
- `-Account` styr utbetalningskontot (standard `1930`).
- Räkenskapsåret hämtas från betalningsdatumet.

Delbetalningar stöds och lämnar fakturan i status `Partial` tills hela beloppet
är betalt:

```powershell
Add-LedgerSupplierPayment -InvoiceNumber 2 -Amount 4000 -Date '2024-04-05'   # Partial
Add-LedgerSupplierPayment -InvoiceNumber 2 -Date '2024-04-20'                # Paid (resten)
```

### 5. Leverantörsreskontra med åldersanalys

`Get-LedgerAccountsPayable` listar öppna leverantörsskulder (bokförda men inte
fullt betalda fakturor) och delar in dem i åldersintervall efter hur många dagar
de är förfallna relativt en referensdag (`-AsOf`, standard idag):

```powershell
# En rad per öppen faktura med DaysOverdue och AgingBucket
Get-LedgerAccountsPayable |
    Format-Table InvoiceNumber, SupplierName, DueDate, RemainingAmount, DaysOverdue, AgingBucket

# En rad per intervall (Current / 1-30 / 31-60 / 61-90 / 90+) med antal och summa
Get-LedgerAccountsPayable -AsOf '2024-05-01' -Summary

# Bara en leverantör
Get-LedgerAccountsPayable -SupplierNumber '100'
```

Summan av `RemainingAmount` stämmer mot saldot på leverantörsskuldkontot (2440).

## Avstämning mot huvudboken

Eftersom både bokföring och betalning skapar verifikationer stämmer reskontran
mot bokföringen. Summan av `RemainingAmount` för öppna leverantörsskulder ska
motsvara saldot på leverantörsskuldkontot (2440):

```powershell
$openAp = (Get-LedgerAccountsPayable | Measure-Object RemainingAmount -Sum).Sum
$saldo2440 = (Get-LedgerBalance | Where-Object AccountNumber -eq '2440').Balance
"Öppna leverantörsskulder: $openAp   Saldo 2440: $saldo2440"
```

## Kommandon

| Kommando | Beskrivning |
|----------|-------------|
| `Add-LedgerSupplier` | Lägg till en leverantör i registret |
| `Get-LedgerSupplier` | Lista eller slå upp leverantörer |
| `Set-LedgerSupplier` | Uppdatera leverantörsuppgifter |
| `New-LedgerSupplierInvoice` | Registrera en leverantörsfaktura (utkast) |
| `Get-LedgerSupplierInvoice` | Lista leverantörsfakturor, `-Unpaid` för öppna skulder |
| `Invoke-LedgerSupplierInvoicePosting` | Bokför en leverantörsfaktura (skapar verifikation) |
| `Add-LedgerSupplierPayment` | Registrera hel eller delbetalning |
| `Get-LedgerAccountsPayable` | Öppna leverantörsskulder med åldersanalys (`-Summary`) |

Se även [Fakturahantering](Fakturahantering.md) för kundreskontra, fakturering
och betalningar.
