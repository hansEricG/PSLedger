# Tidrapportering i PSLedger

Tidmodulen håller reda på nedlagd tid – din egen, anställdas och
underkonsulters – och gör fakturor av den debiterbara tiden. Tiden prissätts med
ett timpris per kund eller per projekt och blir fakturarader med antal timmar,
à-pris och text.

Arbetsflödet är:

1. **Lägg upp** resurser (vem som rapporterar tid), timpriser och projekt.
2. **Registrera** tid med `Add-LedgerTimeEntry` eller importera en CSV-fil med
   `Import-LedgerTimeEntry`.
3. **Följ upp** med `Get-LedgerTimeReport`.
4. **Fakturera** den öppna tiden med `New-LedgerTimeInvoice`.

Tidrapporteringen är till för fakturering. Lön beräknas inte ur tiden.

## Datamodell

Tidmodulen lägger till en katalog i journalen (additivt – inga befintliga filer
ändras och ingen schemamigrering krävs):

```
MinFirma.ledger/
└── time/
    ├── resources.txt    # Id  Namn  Anställningsnr  Leverantörsnr  Kostnad/h  Standard
    ├── projects.txt     # Projektnr  Namn  Kundnr  Timpris  Status
    ├── 2024-03.txt      # Tidrader för mars 2024
    └── 2024-04.txt
```

En tidrad innehåller id, datum, resurs, projekt, kund, timmar, debiterbar
(1/0), timpris, text och – när den fakturerats – fakturanumret. Kundens timpris
ligger som en extra kolumn i `customers.txt`.

## 1. Resurser, timpriser och projekt

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

# Du själv – den första resursen blir standard för nya tidrader
Add-LedgerTimeResource -ResourceId 'HEG' -Name 'Hans-Eric'

# En anställd och en underkonsult, med kostnad per timme för marginalen
Add-LedgerTimeResource -ResourceId 'ANNA' -Name 'Anna Andersson' -EmployeeNumber 1 -CostRate 520
Add-LedgerTimeResource -ResourceId 'KON' -Name 'Kalle Konsult' -SupplierNumber 200 -CostRate 750

# Timpris per kund ...
Set-LedgerCustomer -CustomerNumber 10 -HourlyRate 1050

# ... och/eller per projekt
Add-LedgerProject -ProjectNumber 'P100' -Name 'Webbshop' -CustomerNumber 10 -HourlyRate 1200
Add-LedgerProject -ProjectNumber 'INT' -Name 'Intern administration'
```

Ett projekt utan kund är internt – tid på det är aldrig debiterbar. Stäng ett
projekt när det är klart så går det inte att registrera mer tid på det:

```powershell
Set-LedgerProject -ProjectNumber 'P100' -Status Closed
```

## 2. Registrera tid

```powershell
Add-LedgerTimeEntry -Hours '7:30' -ProjectNumber P100 -Date '2024-03-04' -Text 'Design av kassan'
Add-LedgerTimeEntry -Hours 2,5 -ProjectNumber P100 -ResourceId KON -Date '2024-03-05'
Add-LedgerTimeEntry -Hours 3 -CustomerNumber 20 -Date '2024-03-06' -Text 'Support'
Add-LedgerTimeEntry -Hours 1 -ProjectNumber P100 -NonBillable -Text 'Garantiärende'
```

Timmar kan anges som `7.5`, `7,5`, `7:30` eller `7h`.

Timpriset väljs i den här ordningen:

1. `-Rate` på tidraden,
2. projektets timpris,
3. kundens timpris.

Debiterbar tid utan något timpris ger ett fel. Priset sparas på tidraden när
den registreras, så en senare prishöjning påverkar inte redan registrerad tid.

Ändra eller ta bort tid med `Set-LedgerTimeEntry` och `Remove-LedgerTimeEntry`.
Byter du projekt eller kund hämtas timpriset på nytt (om du inte anger `-Rate`).

## Importera tid från CSV

Tid som förs i Excel eller i en tidapp (Toggl, Harvest, Clockify ...) importeras
från en CSV-fil:

```
Datum;Projekt;Person;Timmar;Beskrivning;Debiterbar
2024-03-07;Webbshop;Kalle Konsult;4;Kodning;ja
2024-03-08;P100;;1:15;Möte;nej
```

```powershell
Import-LedgerTimeEntry -Path .\tid-mars.csv -WhatIf   # förhandsgranska
Import-LedgerTimeEntry -Path .\tid-mars.csv
```

- Rubrikraden, avgränsaren (`;`, `,` eller tab) och teckenkodningen känns igen
  automatiskt, liksom vanliga svenska och engelska kolumnnamn (Datum/Date,
  Timmar/Hours/Duration, Projekt/Project, Kund/Client, Person/User,
  Beskrivning/Description, Debiterbar/Billable). Andra namn anges med
  `-DateColumn`, `-HoursColumn`, `-ProjectColumn` osv.
- Projekt, kund och resurs matchas på nummer/id eller namn. Rader utan resurs
  får `-ResourceId` eller standardresursen; rader utan projekt och kund får
  `-ProjectNumber`.
- Importen är allt eller inget: finns det fel på någon rad importeras ingenting
  och alla fel listas med radnummer.
- Rader som redan har importerats hoppas över, så en export som överlappar en
  tidigare kan importeras igen.

## 3. Följa upp

```powershell
Get-LedgerTimeReport -GroupBy Customer
Get-LedgerTimeReport -GroupBy Project, Resource -FromDate '2024-03-01' -ToDate '2024-03-31'
Get-LedgerTimeReport -GroupBy Week -ResourceId HEG
```

Rapporten visar per grupp:

- totala, debiterbara och icke debiterbara timmar;
- debiterbart belopp, uppdelat på fakturerat och öppet;
- kostnad (timmar × resursens kostnad per timme) och marginal.

`Get-LedgerTimeEntry -Status Open` listar de enskilda tidraderna som inte är
fakturerade ännu.

## 4. Fakturera

```powershell
# All öppen debiterbar tid för kunden till och med 31 mars
New-LedgerTimeInvoice -CustomerNumber 10 -Through '2024-03-31' -Date '2024-04-01'

# Bara ett projekt, en rad per tidrad
New-LedgerTimeInvoice -CustomerNumber 10 -ProjectNumber P100 -PerEntry
```

Fakturan får en rad per projekt, resurs och timpris, till exempel
*"Webbshop – Hans-Eric, mars 2024 · 7,5 h · 1 200,00"*. Med `-PerEntry` blir
det en rad per tidrad med datum och text. Intäktskontot är 3010 och momsen 25 %
om du inte anger `-Account` och `-VatRate`.

Fakturan skapas som ett utkast och hanteras sedan som vilken kundfaktura som
helst: `Export-LedgerInvoice`, `Invoke-LedgerInvoicePosting`, betalning via
bankmatchningen osv. (se [Fakturahantering.md](Fakturahantering.md)).

Tidraderna kopplas till fakturan och blir **låsta** – de kan inte ändras eller
tas bort och faktureras aldrig två gånger. Krediteras fakturan
(`Add-LedgerCreditInvoice`) blir tiden öppen igen och
kan faktureras på nytt.

## Upparbetad men ej fakturerad intäkt vid bokslut

Tid som är utförd men inte fakturerad vid årets slut är en upparbetad intäkt.
Ta fram beloppet och boka upp det på 1620 med automatisk återföring nästa år:

```powershell
$open = Get-LedgerTimeReport -ToDate '2024-12-31' -GroupBy Customer |
    Measure-Object -Property OpenAmount -Sum

Add-LedgerAccrual -FiscalYear '2024-01_2024-12' -Date '2024-12-31' `
    -Description 'Upparbetad ej fakturerad intäkt' `
    -ExpenseAccount '3010' -AccrualAccount '1620' -Amount $open.Sum `
    -ReversalFiscalYear '2025-01_2025-12' -ReversalDate '2025-01-01'
```

Lägg till konto 1620 med `Add-LedgerAccount` om det saknas i kontoplanen.
