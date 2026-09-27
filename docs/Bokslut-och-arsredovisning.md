# How-to: Bokslut och årsredovisning med PSLedger

Den här guiden går igenom hela årsbokslutet för ett litet aktiebolag i PSLedger —
från löpande år till en färdig årsredovisning enligt K2 (BFNAR 2016:10) i Word,
Markdown eller text.

Guiden förutsätter att du redan har en journal med ett räkenskapsår och bokförda
verifikationer. Se [README.md](../README.md) för grunderna (skapa journal, kontoplan,
verifikationer).

> **Antaganden i den här guiden:** litet aktiebolag (AB), K2-regelverket och en
> BAS-kontoplan. Exemplen använder bolaget *H-E Grönlund AB* med brutet räkenskapsår
> `2024-09-01`–`2025-08-31` (identifieras som `2024-09_2025-08`).

---

## Översikt — bokslutets steg

| Steg | Vad | Kommandon |
|------|-----|-----------|
| 1 | Kontrollera att böckerna balanserar | `Get-LedgerBalance` |
| 2 | Bokför bokslutstransaktioner (avskrivningar, nedskrivningar, skatt, bokslutsdispositioner) | `Add-LedgerDepreciation`, `Add-LedgerImpairment`, `Get-LedgerTaxEstimate`, `Add-LedgerTaxEntry`, `Add-LedgerAppropriation` |
| 3 | Registrera bolagsuppgifter (en gång) | `Set-LedgerJournal -Metadata` |
| 4 | Registrera årets berättelse och beslut | `Set-LedgerReportInput`, `Set-LedgerHolding` |
| 5 | Granska rapporterna | `Get-LedgerIncomeStatement`, `Get-LedgerBalanceSheet -Detailed`, `Get-LedgerAnnualReport` |
| 6 | Exportera årsredovisningen | `Export-LedgerAnnualReport` |
| 7 | Stäng räkenskapsåret | `Close-LedgerFiscalYear` |
| 8 | Öppna nästa år och rulla ingående balanser och innehav | `New-LedgerFiscalYear`, `Copy-LedgerOpeningBalance`, `Copy-LedgerHolding` |
| 9 | Bokför resultatdispositionen efter årsstämman | `Add-LedgerProfitDisposition` |

> **Tips:** Kör alltid en `Backup-LedgerJournal` innan du börjar med bokslutet, så du
> enkelt kan rulla tillbaka.
>
> ```powershell
> Backup-LedgerJournal -JournalPath .\HEG.ledger
> ```

---

## Steg 1 — Kontrollera saldobalansen

Innan bokslutstransaktionerna, bekräfta att allt är bokfört och att böckerna
balanserar.

```powershell
$fy = '2024-09_2025-08'
Get-LedgerBalance -JournalPath .\HEG.ledger -FiscalYear $fy |
    Format-Table AccountNumber, AccountName, OpeningBalance, Debit, Credit, Balance
```

Summan av alla `Balance` ska vara 0. Är den inte det saknas en verifikation eller så
är någon obalanserad (vilket PSLedger normalt förhindrar redan vid `Add-LedgerEntry`).

---

## Steg 2 — Bokför bokslutstransaktioner

### 2a. Avskrivningar

`Add-LedgerDepreciation` bokför en avskrivning (debiterar en kostnad, krediterar
ackumulerade avskrivningar). Ange antingen `-Amount` direkt eller låt funktionen räkna
linjärt utifrån `-AcquisitionCost` och `-UsefulLifeYears`.

```powershell
# Explicit belopp
Add-LedgerDepreciation -JournalPath .\HEG.ledger -FiscalYear $fy -Date '2025-08-31' `
    -ExpenseAccount 7832 -AccumulatedDepreciationAccount 1229 -Amount 5000 `
    -Description 'Avskrivning inventarier'

# Linjär avskrivning: 50 000 kr över 5 år => 10 000 kr/år
Add-LedgerDepreciation -JournalPath .\HEG.ledger -FiscalYear $fy -Date '2025-08-31' `
    -ExpenseAccount 7832 -AccumulatedDepreciationAccount 1229 `
    -AcquisitionCost 50000 -UsefulLifeYears 5
```

### 2b. Nedskrivningar

`Add-LedgerImpairment` bokför en nedskrivning (debiterar en nedskrivningskostnad,
krediterar ett värderegleringskonto). Ange beloppet med `-Amount`, eller ange ett
innehav (`-Account` och `-Name`, se [Innehav och marknadsvärde](#innehav-och-marknadsvärde))
så skrivs det ned till sitt marknadsvärde. Datum är som standard balansdagen.

```powershell
# Explicit belopp
Add-LedgerImpairment -JournalPath .\HEG.ledger -FiscalYear $fy `
    -ExpenseAccount 8271 -AdjustmentAccount 1359 -Amount 24348 `
    -Description 'Nedskrivning Knowit (bestående värdenedgång)'

# Skriv ned ett registrerat innehav till marknadsvärdet
Add-LedgerImpairment -JournalPath .\HEG.ledger -FiscalYear $fy `
    -Account 1350 -Name 'Knowit' -ExpenseAccount 8271 -AdjustmentAccount 1359
```

- För ett innehav är beloppet `BookValue − MarketValue`. Saknar innehavet `BookValue`
  används kontots bokförda värde (inklusive t.ex. 1359) minus marknadsvärdet, men bara
  om innehavet är ensamt på kontot.
- Efter bokningen sätts innehavets `BookValue` till marknadsvärdet.
- Vanliga konton: 8271/1359 för andelar och värdepapper (13xx), 7710/1098 för
  kryptotillgångar som redovisas som immateriell anläggningstillgång (K3).
- Registrera gärna innehavets anskaffningsvärde (`-Cost`) med `Set-LedgerHolding`,
  så att en senare återföring kan beräknas.

#### Återföring av nedskrivning

Om marknadsvärdet senare återhämtar sig ska en nedskrivning enligt K3 återföras när
skälen till den inte längre finns (utom för goodwill). `Test-LedgerFiscalYear` flaggar
detta i kontrollen `HoldingsReversal`. Bokför återföringen med `-Reverse`; för ett
innehav blir beloppet det lägsta av marknadsvärde och anskaffningsvärde, minus
bokfört värde, så att tillgången aldrig tas upp över anskaffningsvärdet.

```powershell
Add-LedgerImpairment -JournalPath .\HEG.ledger -FiscalYear $fy `
    -Account 1350 -Name 'Knowit' -ExpenseAccount 8281 -AdjustmentAccount 1359 -Reverse
```

- Vanliga konton: 8281/1359 för andelar och värdepapper, 7760/1098 för
  kryptotillgångar.
- Återföringen kan aldrig bli större än de nedskrivningar som finns på
  värderegleringskontot. Efter bokningen ökas innehavets `BookValue` med beloppet.
- Skattemässigt: är nedskrivningen inte avdragsgill (t.ex. kapitalplaceringsaktier)
  är återföringen normalt inte heller skattepliktig — justera med
  `Get-LedgerTaxEstimate -NonTaxableIncome`.

### 2c. Bokslutsdispositioner (periodiseringsfond, överavskrivningar)

`Add-LedgerAppropriation` hanterar `Periodiseringsfond` och `Overavskrivning`. Använd
`-Reverse` för att återföra en tidigare avsättning.

```powershell
# Avsätt till periodiseringsfond
Add-LedgerAppropriation -JournalPath .\HEG.ledger -FiscalYear $fy -Date '2025-08-31' `
    -Type Periodiseringsfond -Amount 30000

# Återför en tidigare periodiseringsfond
Add-LedgerAppropriation -JournalPath .\HEG.ledger -FiscalYear $fy -Date '2025-08-31' `
    -Type Periodiseringsfond -Amount 12000 -Reverse
```

### 2d. Skatt

Beräkna först skatten, bokför den sedan. `Get-LedgerTaxEstimate` utgår från resultatet
före skatt (konton t.o.m. 8999) och justerar för ej avdragsgilla kostnader och ej
skattepliktiga intäkter. Standardskattesats är 20,6 %.

```powershell
$tax = Get-LedgerTaxEstimate -JournalPath .\HEG.ledger -FiscalYear $fy `
    -NonDeductibleExpenses 2000 -NonTaxableIncome 0
$tax | Format-List ResultBeforeTax, TaxableResult, TaxRate, EstimatedTax

# Bokför den beräknade skatten (skattekostnad mot skatteskuld)
Add-LedgerTaxEntry -JournalPath .\HEG.ledger -FiscalYear $fy -Date '2025-08-31' `
    -Amount $tax.EstimatedTax -Description 'Årets skatt'
```

> Kör om `Get-LedgerTaxEstimate` efter avskrivningar och dispositioner, eftersom de
> påverkar det skattemässiga resultatet.

---

## Steg 3 — Registrera bolagsuppgifter (en gång)

De uppgifter som är stabila mellan åren lagras som metadata på journalen och läses av
`Get-LedgerCompanyProfile`. Detta behöver du bara göra en gång (uppdatera vid ändring).

```powershell
Set-LedgerJournal -JournalPath .\HEG.ledger -Metadata @{
    RegisteredOffice = 'Gävle'                       # säte
    BusinessObject   = 'Konsultverksamhet inom IT.'  # verksamhetsföremål
    NumberOfShares   = '1000'                         # antal aktier
    ShareCapital     = '100000'                       # aktiekapital
    BoardMembers     = 'Hans-Erik Grönlund'           # flera: separera med ';'
}
```

| Metadatanyckel | Används till |
|----------------|--------------|
| `RegisteredOffice` | "Företaget har sitt säte i …" |
| `BusinessObject` | "Allmänt om verksamheten: …" |
| `NumberOfShares` | Utdelning per aktie i vinstdispositionen |
| `ShareCapital` | Registrerat aktiekapital |
| `BoardMembers` | Underskriftsraderna (separera flera med `;`) |

Kontrollera resultatet:

```powershell
Get-LedgerCompanyProfile -JournalPath .\HEG.ledger
```

---

## Steg 4 — Registrera årets berättelse och beslut

Årsspecifik text och stämmobeslut lagras i en valfri `report.txt` per räkenskapsår
(på samma sätt som `ib.txt`). Sätt dem med `Set-LedgerReportInput`.

```powershell
Set-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear $fy `
    -SignificantEvents 'Inga väsentliga händelser har inträffat under året.' `
    -ProposedDividend 50000 `
    -AverageEmployees 1 `
    -SecuritiesMarketValue 95000 `
    -SigningPlace 'Gävle' `
    -SigningDate '2025-11-15'
```

| Parameter | Används till |
|-----------|--------------|
| `SignificantEvents` | Rubriken "Väsentliga händelser under räkenskapsåret" |
| `ProposedDividend` | Föreslagen utdelning i vinstdispositionen |
| `AverageEmployees` | Personalnoten (medelantal anställda) |
| `SecuritiesMarketValue` | Not för aktier och andelar (marknadsvärde). Om satt tas noten med automatiskt. Används bara om inga innehav är registrerade, se [Innehav och marknadsvärde](#innehav-och-marknadsvärde) |
| `SigningPlace` / `SigningDate` | Ort och datum vid underskrifterna |
| `AnnualMeetingDate` | Årsstämmans datum i fastställelseintyget på försättsbladet (tom linje om det saknas) |
| `CertificatePlace` | Ort i fastställelseintyget. Standard är bolagets säte (`RegisteredOffice`) |
| `CertificateSigner` | Styrelseledamot som skriver under fastställelseintyget. Standard är den första i `BoardMembers` |
| `ComparativeFiguresNote` | Upplysning under rubriken Jämförelsetal i noterna, t.ex. när jämförelsetalen har rättats |
| `Framework` | Regelverk: `K2` (standard) eller `K3`. Se [K3](#k3-bfnar-20121) nedan |
| `Ownership` | Rubriken "Ägarförhållanden" i förvaltningsberättelsen, t.ex. ägare med mer än 10 % av aktierna |
| `EventsAfterBalanceDate` | Not om väsentliga händelser efter räkenskapsårets slut (ÅRL 5 kap. 22 §) |
| `PledgedAssets` / `ContingentLiabilities` | Ställda säkerheter och eventualförpliktelser. Under K3 skrivs "Inga" om de saknas |
| `TransitionNote` | Extra text i K3-övergångsnoten, t.ex. omklassificeringar eller tillämpade lättnadsregler i K3 kap. 35 |
| `DeferredTaxStatement` | Extra text om uppskjuten skatt i K3-principerna, t.ex. varför ingen skattefordran på underskott redovisas |

Läs tillbaka värdena:

```powershell
Get-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear $fy
```

### Innehav och marknadsvärde

I stället för ett manuellt beräknat `SecuritiesMarketValue` kan du registrera varje
värdepappersinnehav per balansdag i en valfri `holdings.txt` (UTF-8, tabbseparerad)
per räkenskapsår. Ett innehav identifieras av konto + namn; ISIN, kursdatum,
kurskälla och bokfört värde är valfria. Marknadsvärdet i SEK räknas ut som
antal × kurs × växelkurs.

```powershell
Set-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear $fy `
    -Account 1350 -Name 'Investor B' -Isin 'SE0015811963' `
    -Quantity 500 -Price 265.40 -PriceDate '2025-08-29' -Source 'Nasdaq Stockholm' -BookValue 98000

# Utländsk valuta: ange kurs i valutan och växelkurs (SEK per enhet) på balansdagen
Set-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear $fy `
    -Account 1350 -Name 'Vanguard FTSE All-World' -Isin 'IE00BK5BQT80' `
    -Quantity 120 -Price 118.20 -Currency USD -FxRate 9.5312 -PriceDate '2025-08-29'

# Underlag per innehav
Get-LedgerHolding -JournalPath .\HEG.ledger -FiscalYear $fy |
    Format-Table Account, Name, Quantity, Price, Currency, MarketValue, BookValue, Difference
```

- När innehav finns används **summan av innehaven** på kontona i notens intervall
  (1300–1399) som marknadsvärde i noten för aktier och andelar. `SecuritiesMarketValue`
  används då inte; skiljer de sig åt visas en varning.
- `BookValue` är innehavets redovisade värde (anskaffningsvärde minus ev.
  nedskrivningar). Det behövs bara om flera innehav ligger på samma konto och du vill
  jämföra per innehav — annars jämförs kontots saldo mot summan av innehavens
  marknadsvärde.
- `Cost` är innehavets anskaffningsvärde. Det används som tak när en nedskrivning
  återförs (se steg 2b) och stäms av mot kontots eget saldo (t.ex. 1350 utan 1359).
- Om marknadsvärdet understiger bokfört värde visas en varning. För finansiella
  anläggningstillgångar (13xx) ska du bedöma om värdenedgången är bestående
  (nedskrivning enligt K2); för kortfristiga placeringar (18xx) gäller lägsta värdets
  princip. Bokför nedskrivningen med `Add-LedgerImpairment` (se steg 2b).
- Kontots bokförda värde inkluderar värderegleringskonton i samma tiotal som inte
  själva har innehav (t.ex. 1359 för 1350). Nedskrivningar som bokförts på ett konto
  i ett annat tiotal (t.ex. 1890 för 1810) räknas inte in i jämförelsen per konto —
  ange då `BookValue` per innehav.
- `Test-LedgerFiscalYear` innehåller kontrollerna `HoldingsValuation`,
  `HoldingsReconcile` (summan av `BookValue` mot kontosaldot, summan av `Cost` mot
  kontots eget saldo och kursdatum mot balansdagen) och `HoldingsReversal`
  (nedskrivningar som kan återföras).
- Innehav kan inte ändras i ett stängt räkenskapsår. Ta bort ett innehav med
  `Remove-LedgerHolding`.

---

## Steg 5 — Granska rapporterna innan export

Titta på delarna var för sig innan du genererar hela dokumentet.

```powershell
# Resultat- och balansräkning (använd -Detailed för uppdelat eget kapital)
Get-LedgerIncomeStatement -JournalPath .\HEG.ledger -FiscalYear $fy
Get-LedgerBalanceSheet    -JournalPath .\HEG.ledger -FiscalYear $fy -Detailed

# Flerårsöversikt, vinstdisposition och eget kapital-noten
Get-LedgerMultiYearOverview    -JournalPath .\HEG.ledger -FiscalYear $fy
Get-LedgerProfitDisposition    -JournalPath .\HEG.ledger -FiscalYear $fy
Get-LedgerEquityReconciliation -JournalPath .\HEG.ledger -FiscalYear $fy

# Kombinerad rapport med jämförelseår (data för resultat + balans)
Get-LedgerAnnualReport -JournalPath .\HEG.ledger -FiscalYear $fy |
    Format-Table Statement, Label, Amount, ComparisonAmount
```

**Kontrollpunkt:** i tabellen Förändringar i eget kapital ska `Utgående balans` för raden
`Summa eget kapital` stämma med eget kapital + årets resultat i balansräkningen.

---

## Steg 6 — Exportera årsredovisningen

`Export-LedgerAnnualReport` sätter ihop hela K2-årsredovisningen:
försättsblad, förvaltningsberättelse (verksamhet, väsentliga händelser,
flerårsöversikt, förändringar i eget kapital, förslag till vinstdisposition),
resultaträkning och balansräkning med Not-kolumn och jämförelseår, noter
(redovisningsprinciper, medelantal anställda samt de auto-detekterade noterna för
anläggningstillgångar och aktier och andelar) samt underskrifter med
fastställelseintyg. Med `Framework = K3` i `report.txt` blir det i stället en
K3-årsredovisning (se nedan).

Förändringar i eget kapital redovisas i förvaltningsberättelsen, inte som en not,
eftersom ÅRL 6 kap. 2 § kräver att de anges i förvaltningsberättelsen eller i en egen
räkning.

```powershell
# Word-dokument (.docx)
Export-LedgerAnnualReport -JournalPath .\HEG.ledger -FiscalYear $fy `
    -Path .\arsredovisning-2024-2025.docx -Format Word

# Markdown
Export-LedgerAnnualReport -JournalPath .\HEG.ledger -FiscalYear $fy `
    -Path .\arsredovisning-2024-2025.md -Format Markdown

# Ren text (standardformat)
Export-LedgerAnnualReport -JournalPath .\HEG.ledger -FiscalYear $fy `
    -Path .\arsredovisning-2024-2025.txt
```

Användbara flaggor:

- `-Format Text | Markdown | Word` — utdataformat (`.docx` kräver **inte** att Word är
  installerat; filen byggs som ett Open XML-paket).
- `-NoComparison` — utelämnar jämförelsekolumnen i resultat- och balansräkningen.
- `-Force` — skriver över en befintlig fil.

### Om noterna

Anläggnings- och värdepappersnoterna **auto-detekteras** från standardintervall i
BAS-kontoplanen. En not tas bara med när relevanta konton har saldo:

| Not | Konton (BAS) |
|-----|--------------|
| Immateriella anläggningstillgångar | 1000–1099 |
| Byggnader och mark | 1100–1119 |
| Maskiner och andra tekniska anläggningar | 1210–1219 |
| Inventarier, verktyg och installationer | 1220–1229 |
| Andra långfristiga värdepappersinnehav | 1350–1359 |
| Aktier och andelar (bokfört + marknadsvärde) | tas med om `SecuritiesMarketValue` är satt eller innehav på 1300–1399 finns i `holdings.txt` |

### K3 (BFNAR 2012:1)

Ett företag som inte får eller vill tillämpa K2 (t.ex. vid direkta innehav av
kryptotillgångar från räkenskapsår som börjar efter 2025-12-31, BFNAR 2025:2) sätter
regelverket per räkenskapsår:

```powershell
Set-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear '2026-09_2027-08' -Framework K3 `
    -Ownership 'Anna Andersson äger samtliga aktier.' `
    -TransitionNote 'Innehavet av kryptotillgångar har omklassificerats från andra långfristiga värdepappersinnehav till kryptotillgångar.'
```

Med K3 ändras årsredovisningen så här:

- **Principer:** K3-texten från `Get-LedgerAccountingPrinciples -Framework K3` samt
  principer för de poster bolaget har: kryptotillgångar (anskaffningsvärde, ingen
  avskrivning, nedskrivningsprövning), övriga immateriella och materiella
  anläggningstillgångar, finansiella anläggningstillgångar och inkomstskatter
  (aktuell och uppskjuten skatt, plus `DeferredTaxStatement`).
- **Övergång till K3:** första K3-året (föregående år är inte K3) får en not med
  övergångstidpunkt (årets första dag) och upplysning om att jämförelsetalen inte
  räknats om (ÅRL 3 kap. 5 § fjärde stycket), plus `TransitionNote`.
- **Resultaträkning:** ÅRL bilaga 2:s rubriker för finansiella poster, med
  "Nedskrivningar av finansiella anläggningstillgångar och kortfristiga placeringar"
  (8070–8089, 8170–8189, 8270–8289, 8370–8389) på egen rad.
- **Balansräkning:** immateriella anläggningstillgångar uppdelade enligt ÅRL bilaga 1.
  1090–1099 får namnet på det första kontot i intervallet (t.ex. `1090
  Kryptotillgångar`). Kontonamn som innehåller "krypto" eller "bitcoin" ger
  kryptoprincipen. Maskiner (1200–1219) och inventarier (1220–1279, 1290–1299) redovisas separat,
  liksom uppskjuten skattefordran (1370–1379), aktuella skattefordringar (1640–1649 och
  debetsaldo på 2500–2599) och avsättningar för skatter (2240–2259).
- **Noter:** en anläggningsnot per BAS-kontogrupp (x0–x7 anskaffning, x8–x9 av- och
  nedskrivningar), och alltid ställda säkerheter och eventualförpliktelser.

Övergången bokförs genom att flytta tillgången till rätt konto i det nya årets
ingående balans eller med en verifikation på årets första dag. Jämförelsetalen
redovisas oförändrade.

---

## Steg 7 — Stäng räkenskapsåret

När årsredovisningen är fastställd stänger du året. `Close-LedgerFiscalYear` bokför
årets resultat (för AB: via resultatkonto 8999 mot eget kapital 2099) och låser året
mot fler verifikationer.

```powershell
Close-LedgerFiscalYear -JournalPath .\HEG.ledger -FiscalYear $fy
```

> **Notera:** kontona 8999 och 2099 måste finnas i kontoplanen (`accounts.txt`),
> annars kastar bokföringen av resultatet ett fel. Lägg vid behov till dem med
> `Add-LedgerAccount`.

Standardkonton kan ändras med `-ResultAccount` och `-EquityAccount`, och
`-SkipResultEntry` hoppar över resultatbokföringen om du redan gjort den manuellt.

---

## Steg 8 — Öppna nästa år och rulla ingående balanser

```powershell
# Skapa nästa räkenskapsår
New-LedgerFiscalYear -JournalPath .\HEG.ledger -StartDate '2025-09-01' -EndDate '2026-08-31'

# Rulla över utgående balanser (1xxx/2xxx) som ingående balans (ib.txt)
Copy-LedgerOpeningBalance -JournalPath .\HEG.ledger `
    -FromFiscalYear '2024-09_2025-08' -ToFiscalYear '2025-09_2026-08'
```

`Copy-LedgerOpeningBalance` för över alla tillgångs- och skuldsaldon (inklusive 2099)
som ingående balans. Föregående års resultat ligger kvar i 2099:s ingående balans tills
resultatdispositionen bokförs (steg 9).

Har du registrerat värdepappersinnehav rullar du dem vidare med `Copy-LedgerHolding`.
Alla fält kopieras, även kurs och kursdatum, så uppdatera kurserna med
`Set-LedgerHolding` vid nästa balansdag (`Test-LedgerFiscalYear` påminner om kursdatum
som inte stämmer med balansdagen).

```powershell
Copy-LedgerHolding -JournalPath .\HEG.ledger `
    -FromFiscalYear '2024-09_2025-08' -ToFiscalYear '2025-09_2026-08'
```

Målåret får inte redan ha innehav (använd `-Force` för att ersätta dem), och en
varning visas för innehav vars konto saknar ingående balans i målåret.

---

## Steg 9 — Bokför resultatdispositionen efter årsstämman

När årsstämman har fastställt årsredovisningen och beslutat om vinstdispositionen
bokför du beslutet i det nya året med `Add-LedgerProfitDisposition`. Föregående års
resultat förs från 2099 till 2091 (Balanserad vinst eller förlust), och en beslutad
utdelning bokförs som skuld på 2898 (Outtagen vinstutdelning).

```powershell
# Använder AnnualMeetingDate och ProposedDividend från föregående års report.txt
Add-LedgerProfitDisposition -JournalPath .\HEG.ledger -FiscalYear '2025-09_2026-08'

# Ange datum och utdelning explicit
Add-LedgerProfitDisposition -JournalPath .\HEG.ledger -FiscalYear '2025-09_2026-08' `
    -Date '2025-10-15' -Dividend 50000
```

- Året som disponeras är som standard året före `-FiscalYear` (`-FromFiscalYear`).
- Kommandot vägrar om 2099 saknar saldo (dispositionen är troligen redan bokförd) eller
  om utdelningen överstiger det fria egna kapitalet.
- Kontona kan ändras med `-ResultAccount`, `-RetainedEarningsAccount` och
  `-DividendAccount`. Utbetalningen av utdelningen bokförs sedan som vanligt
  (2898 mot bank).

---

## Att tänka på

- **Omföring 2099 → 2091:** eget kapital-tabellen och vinstdispositionen hanterar en
  resultatdisposition som bokförts under året (med `Add-LedgerProfitDisposition` eller
  manuellt). Föregående års resultat räknas som ingående balanserat resultat, och
  omföringen dubbelräknas inte.
- **Ordning:** bokför avskrivningar och bokslutsdispositioner **före** du beräknar och
  bokför skatten, eftersom de påverkar det skattemässiga resultatet.
- **Kör alltid en backup** (`Backup-LedgerJournal`) innan du stänger året.
- **Granska alltid** det genererade dokumentet mot föregående års årsredovisning innan
  du lämnar in det — auto-detekteringen bygger på standardintervall i BAS och täcker de
  vanligaste fallen, men ovanliga kontoval kan behöva justeras manuellt.

---

## Kommandoreferens (bokslut & årsredovisning)

| Kommando | Beskrivning |
|----------|-------------|
| `Backup-LedgerJournal` | Skapa en tidsstämplad zip-backup |
| `Get-LedgerBalance` | Saldobalans (kontroll före bokslut) |
| `Add-LedgerDepreciation` | Bokför avskrivning |
| `Add-LedgerImpairment` | Bokför nedskrivning eller återföring (`-Reverse`), belopp eller innehav mot marknadsvärde |
| `Add-LedgerAppropriation` | Bokför/återför periodiseringsfond eller överavskrivning |
| `Get-LedgerTaxEstimate` | Beräkna bolagsskatt (skattemässigt resultat) |
| `Add-LedgerTaxEntry` | Bokför årets skatt |
| `Set-LedgerJournal -Metadata` | Registrera stabila bolagsuppgifter |
| `Get-LedgerCompanyProfile` | Läs bolagsprofil för årsredovisningen |
| `Set-LedgerReportInput` / `Get-LedgerReportInput` | Årsspecifik text och beslut (report.txt) |
| `Set-LedgerHolding` / `Get-LedgerHolding` / `Remove-LedgerHolding` | Värdepappersinnehav och marknadsvärde per balansdag (holdings.txt) |
| `Get-LedgerIncomeStatement` | Resultaträkning |
| `Get-LedgerBalanceSheet -Detailed` | Balansräkning med uppdelat eget kapital |
| `Get-LedgerMultiYearOverview` | Flerårsöversikt, inklusive soliditet |
| `Get-LedgerProfitDisposition` | Förslag till vinstdisposition |
| `Get-LedgerEquityReconciliation` | Förändring av eget kapital |
| `Get-LedgerFixedAssetNote` | Anläggningsnot (rörelse) |
| `Get-LedgerShareholdingNote` | Not för aktier och andelar |
| `Get-LedgerEmployeeNote` | Not för medelantal anställda |
| `Get-LedgerAccountingPrinciples` | K2- eller K3-redovisningsprinciper (`-Framework`) |
| `Get-LedgerAnnualReport` | Kombinerad resultat + balans med jämförelseår |
| `Export-LedgerAnnualReport` | Exportera hela årsredovisningen (Text/Markdown/Word) |
| `Close-LedgerFiscalYear` | Stäng och lås räkenskapsåret |
| `New-LedgerFiscalYear` | Skapa nästa räkenskapsår |
| `Copy-LedgerOpeningBalance` | Rulla ingående balanser till nästa år |
| `Copy-LedgerHolding` | Rulla värdepappersinnehav till nästa år |
| `Add-LedgerProfitDisposition` | Bokför resultatdisposition och utdelning efter årsstämman |
