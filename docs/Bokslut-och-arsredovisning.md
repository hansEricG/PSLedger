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
| 2 | Bokför bokslutstransaktioner (avskrivningar, skatt, bokslutsdispositioner) | `Add-LedgerDepreciation`, `Get-LedgerTaxEstimate`, `Add-LedgerTaxEntry`, `Add-LedgerAppropriation` |
| 3 | Registrera bolagsuppgifter (en gång) | `Set-LedgerJournal -Metadata` |
| 4 | Registrera årets berättelse och beslut | `Set-LedgerReportInput` |
| 5 | Granska rapporterna | `Get-LedgerIncomeStatement`, `Get-LedgerBalanceSheet -Detailed`, `Get-LedgerAnnualReport` |
| 6 | Exportera årsredovisningen | `Export-LedgerAnnualReport` |
| 7 | Stäng räkenskapsåret | `Close-LedgerFiscalYear` |
| 8 | Öppna nästa år och rulla ingående balanser | `New-LedgerFiscalYear`, `Copy-LedgerOpeningBalance` |

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

### 2b. Bokslutsdispositioner (periodiseringsfond, överavskrivningar)

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

### 2c. Skatt

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
| `SecuritiesMarketValue` | Not för aktier och andelar (marknadsvärde). Om satt tas noten med automatiskt |
| `SigningPlace` / `SigningDate` | Ort och datum vid underskrifterna |

Läs tillbaka värdena:

```powershell
Get-LedgerReportInput -JournalPath .\HEG.ledger -FiscalYear $fy
```

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

**Kontrollpunkt:** i eget kapital-noten ska `Utgående balans` för raden
`Summa eget kapital` stämma med eget kapital + årets resultat i balansräkningen.

---

## Steg 6 — Exportera årsredovisningen

`Export-LedgerAnnualReport` sätter ihop hela K2-årsredovisningen:
försättsblad, förvaltningsberättelse (verksamhet, väsentliga händelser,
flerårsöversikt, förslag till vinstdisposition), resultaträkning och balansräkning
med Not-kolumn och jämförelseår, noter (redovisningsprinciper, medelantal anställda,
samt de auto-detekterade noterna för anläggningstillgångar, aktier och andelar och
eget kapital) samt underskrifter med fastställelseintyg.

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
| Aktier och andelar (bokfört + marknadsvärde) | tas med om `SecuritiesMarketValue` är satt |
| Förändring av eget kapital | alltid (AB) |

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
som ingående balans. Föregående års resultat ligger kvar i 2099:s ingående balans.

---

## Att tänka på

- **Omföring 2099 → 2091:** eget kapital-noten och vinstdispositionen förutsätter att
  du **inte** bokför en manuell omföring av föregående års resultat (2099 → 2091) mitt
  i året. Föregående års resultat behandlas som ingående balanserat resultat via 2099:s
  ingående balans. Bokför du en manuell omföring dubbelräknas beloppet.
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
| `Add-LedgerAppropriation` | Bokför/återför periodiseringsfond eller överavskrivning |
| `Get-LedgerTaxEstimate` | Beräkna bolagsskatt (skattemässigt resultat) |
| `Add-LedgerTaxEntry` | Bokför årets skatt |
| `Set-LedgerJournal -Metadata` | Registrera stabila bolagsuppgifter |
| `Get-LedgerCompanyProfile` | Läs bolagsprofil för årsredovisningen |
| `Set-LedgerReportInput` / `Get-LedgerReportInput` | Årsspecifik text och beslut (report.txt) |
| `Get-LedgerIncomeStatement` | Resultaträkning |
| `Get-LedgerBalanceSheet -Detailed` | Balansräkning med uppdelat eget kapital |
| `Get-LedgerMultiYearOverview` | Flerårsöversikt |
| `Get-LedgerProfitDisposition` | Förslag till vinstdisposition |
| `Get-LedgerEquityReconciliation` | Förändring av eget kapital |
| `Get-LedgerFixedAssetNote` | Anläggningsnot (rörelse) |
| `Get-LedgerShareholdingNote` | Not för aktier och andelar |
| `Get-LedgerEmployeeNote` | Not för medelantal anställda |
| `Get-LedgerAccountingPrinciples` | K2 redovisnings- och värderingsprinciper |
| `Get-LedgerAnnualReport` | Kombinerad resultat + balans med jämförelseår |
| `Export-LedgerAnnualReport` | Exportera hela årsredovisningen (Text/Markdown/Word) |
| `Close-LedgerFiscalYear` | Stäng och lås räkenskapsåret |
| `New-LedgerFiscalYear` | Skapa nästa räkenskapsår |
| `Copy-LedgerOpeningBalance` | Rulla ingående balanser till nästa år |
