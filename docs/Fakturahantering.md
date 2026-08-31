# Fakturahantering i PSLedger

PSLedger kan hantera en kundlista och hela livscykeln för en kundfaktura –
skapa, bokföra och registrera betalningar. Fakturahanteringen ligger som ett
lager *ovanpå* bokföringen: både bokföring av fakturan och registrering av en
betalning skapar vanliga verifikationer. Därför stämmer summan av de öppna
kundfordringarna alltid mot saldot på huvudbokskontot (1510).

En faktura går igenom statusarna **Draft → Booked → Partial → Paid**. En bokförd
faktura kan även **krediteras**, vilket sätter status **Credited** på både
originalet och kreditfakturan.

## Datamodell

Fakturahanteringen lägger till två saker i journalen (bägge additiva – inga
befintliga filer ändras och ingen schemamigrering krävs):

```
MinFirma.ledger/
├── customers.txt        # Tab-separerat: Nummer  Namn  Org.nr  E-post  Betalvillkor(dagar)
└── invoices/            # En fil per faktura
    ├── inv0001.txt
    └── inv0002.txt
```

En fakturafil (`inv0001.txt`) innehåller metadata, en `Rows:`-sektion (en
intäktsrad per rad: konto, nettobelopp, momssats, momskonto) och en
`Payments:`-sektion (en betalning per rad: datum, belopp, verifikationsnummer,
räkenskapsår). Belopp lagras med punkt som decimaltecken (invariant kultur) så
att de tab-separerade kolumnerna inte bryts av ett lokalt kommatecken.

Fakturor lagras på journalnivå (inte inuti ett räkenskapsår) eftersom en faktura
kan betalas ett senare räkenskapsår än det den ställdes ut i.

## Steg för steg

### 1. Lägg upp en kund

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

Add-LedgerCustomer -CustomerNumber '10' -Name 'Volvo AB' `
    -OrgNumber '556012-5790' -Email 'faktura@volvo.se' -PaymentTermsDays 30
```

`-PaymentTermsDays` (standard 30) styr hur förfallodatumet räknas ut på nya
fakturor. Uppdatera en kund med `Set-LedgerCustomer` (bara de fält du anger
ändras) och lista med `Get-LedgerCustomer`.

```powershell
Set-LedgerCustomer -CustomerNumber '10' -Email 'ny@volvo.se' -PaymentTermsDays 20
Get-LedgerCustomer | Format-Table CustomerNumber, Name, PaymentTermsDays
```

### 2. Skapa en fakturautkast

Varje rad är en intäktsrad med ett **nettobelopp** (exklusive moms), en valfri
momssats och kontot momsen bokförs på.

```powershell
$rows = @(
    @{ Account = '3010'; Amount = 10000; VatRate = 0.25; VatAccount = '2610' }
)
New-LedgerInvoice -CustomerNumber '10' -Date '2024-03-15' `
    -Description 'Konsultarvode mars' -Rows $rows
```

- Förfallodatum sätts automatiskt till fakturadatum + kundens betalningsvillkor.
  Ange `-DueDate` för att styra det manuellt.
- En momsfri rad utelämnar momsen (`VatRate = 0` och inget `VatAccount`).
- `-ReceivableAccount` styr kundfordringskontot (standard `1510`).
- Fakturanummer räknas upp automatiskt (`inv0001`, `inv0002`, …).

Flera rader, t.ex. tjänst med moms plus ett momsfritt utlägg:

```powershell
$rows = @(
    @{ Account = '3010'; Amount = 8000; VatRate = 0.25; VatAccount = '2610' }
    @{ Account = '3590'; Amount = 500;  VatRate = 0 }
)
New-LedgerInvoice -CustomerNumber '10' -Description 'Arvode och utlägg' -Rows $rows -PassThru
```

### 3. Bokför fakturan

Bokföringen skapar en verifikation: kundfordran debiteras med bruttobeloppet,
intäktskonton krediteras med netto och momskonton med momsen.

```powershell
Invoke-LedgerInvoicePosting -InvoiceNumber 1
```

Ger verifikationen:

```
1510 Kundfordringar  +12500
3010 Försäljning      -10000
2610 Utgående moms     -2500
```

Räkenskapsåret hämtas från fakturadatumet (ange `-FiscalYear` för att styra
det). Fakturan får status `Booked` och sparar `BookedVerification` och
`BookedFiscalYear`. Att bokföra en redan bokförd faktura ger ett fel.

### 4. Registrera betalning

Betalningen skapar en verifikation som debiterar bank/kassa och krediterar
kundfordran.

```powershell
# Full betalning – markerar fakturan som Paid
Add-LedgerInvoicePayment -InvoiceNumber 1 -Date '2024-04-10'
```

Ger verifikationen:

```
1930 Bank            +12500
1510 Kundfordringar  -12500
```

- Utan `-Amount` betalas hela det återstående beloppet.
- `-Account` styr in­betalningskontot (standard `1930`).
- Räkenskapsåret hämtas från betalningsdatumet.

Delbetalningar stöds och lämnar fakturan i status `Partial` tills hela beloppet
är betalt:

```powershell
Add-LedgerInvoicePayment -InvoiceNumber 2 -Amount 5000 -Date '2024-04-10'   # Partial
Add-LedgerInvoicePayment -InvoiceNumber 2 -Date '2024-04-20'                # Paid (resten)
```

### 5. Följ upp öppna fordringar

```powershell
# Alla fakturor med beräknade summor
Get-LedgerInvoice | Format-Table InvoiceNumber, CustomerName, Total, PaidAmount, Status

# Bara bokförda men inte fullt betalda fakturor (öppna kundfordringar)
Get-LedgerInvoice -Unpaid |
    Format-Table InvoiceNumber, CustomerName, DueDate, Total, RemainingAmount

# Filtrera på status eller kund
Get-LedgerInvoice -Status Paid
Get-LedgerInvoice -CustomerNumber '10'
```

Varje fakturaobjekt innehåller `NetTotal`, `VatTotal`, `Total`, `PaidAmount`,
`RemainingAmount`, raderna (`Rows`) och betalningarna (`Payments`) med de
verifikationsnummer de skapade – så en faktura alltid kan spåras till huvudboken.

### 6. Kundreskontra med åldersanalys

`Get-LedgerAccountsReceivable` listar öppna fordringar (bokförda men inte fullt
betalda fakturor) och delar in dem i åldersintervall efter hur många dagar de är
förfallna relativt en referensdag (`-AsOf`, standard idag):

```powershell
# En rad per öppen faktura med DaysOverdue och AgingBucket
Get-LedgerAccountsReceivable |
    Format-Table InvoiceNumber, CustomerName, DueDate, RemainingAmount, DaysOverdue, AgingBucket

# En rad per intervall (Current / 1-30 / 31-60 / 61-90 / 90+) med antal och summa
Get-LedgerAccountsReceivable -AsOf '2024-05-01' -Summary

# Bara en kund
Get-LedgerAccountsReceivable -CustomerNumber '10'
```

Summan av `RemainingAmount` stämmer mot saldot på kundfordringskontot (1510).

### 7. Exportera en faktura

`Export-LedgerInvoice` skriver ut en enskild faktura som ett dokument – PDF
(standard), Word, Markdown eller ren text. PDF:en skapas av en inbyggd,
beroendefri PDF-generator (inga externa moduler).

```powershell
Export-LedgerInvoice -InvoiceNumber 1 -Path .\faktura-1.pdf
Export-LedgerInvoice -InvoiceNumber 1 -Path .\faktura-1.docx -Format Word -Force
```

Dokumentet innehåller säljaren (från journalen), kunden, fakturauppgifter,
raderna med moms, summor och betalningsinformation. Bankgiro, plusgiro och
IBAN/BIC hämtas från journalens metadata om de finns:

```powershell
Set-LedgerJournal -Metadata @{ Bankgiro = '123-4567'; VatNumber = 'SE556012579001' }
```

### 8. Kreditera en faktura

`Add-LedgerCreditInvoice` krediterar (återför) en bokförd, obetald faktura. Den
skapar en kreditfaktura med negerade rader och bokför en återförande verifikation
som speglar den ursprungliga bokföringen:

```powershell
Add-LedgerCreditInvoice -InvoiceNumber 1
```

Ger verifikationen:

```
1510 Kundfordringar  -12500
3010 Försäljning      +10000
2610 Utgående moms     +2500
```

Både originalfakturan och kreditfakturan får status `Credited`, så att
kundreskontran nettar till noll för paret. Bara en faktura med status `Booked`
kan krediteras – ett utkast måste bokföras först (eller raderas), och en faktura
med betalningar måste hanteras via betalningarna.

## Avstämning mot huvudboken

Eftersom både bokföring och betalning skapar verifikationer stämmer reskontran
mot bokföringen. Summan av `RemainingAmount` för `-Unpaid`-fakturor ska motsvara
saldot på kundfordringskontot (1510):

```powershell
$openApAr = (Get-LedgerInvoice -Unpaid | Measure-Object RemainingAmount -Sum).Sum
$saldo1510 = (Get-LedgerBalance | Where-Object AccountNumber -eq '1510').Balance
"Öppna fakturor: $openApAr   Saldo 1510: $saldo1510"
```

## Kommandon

| Kommando | Beskrivning |
|----------|-------------|
| `Add-LedgerCustomer` | Lägg till en kund i kundregistret |
| `Get-LedgerCustomer` | Lista eller slå upp kunder |
| `Set-LedgerCustomer` | Uppdatera kunduppgifter |
| `New-LedgerInvoice` | Skapa en kundfaktura (utkast) |
| `Get-LedgerInvoice` | Lista fakturor, `-Unpaid` för öppna fordringar |
| `Invoke-LedgerInvoicePosting` | Bokför en faktura (skapar verifikation) |
| `Add-LedgerInvoicePayment` | Registrera hel eller delbetalning |
| `Get-LedgerAccountsReceivable` | Öppna fordringar med åldersanalys (`-Summary`) |
| `Export-LedgerInvoice` | Exportera en faktura till PDF, Word, Markdown eller text |
| `Add-LedgerCreditInvoice` | Kreditera (återför) en bokförd faktura |
