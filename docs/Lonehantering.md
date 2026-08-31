# Lönehantering i PSLedger

Lönehanteringen sköter ett anställningsregister och lönespecifikationer
(lönebesked) för en enkel svensk lönerutin. Precis som kund- och
leverantörsreskontran ligger den som ett lager *ovanpå* bokföringen: att bokföra
en lönespecifikation skapar en vanlig verifikation. Därför stämmer de
lönerelaterade skuldkontona (2710 Personalskatt, 2730 Arbetsgivaravgift skuld)
alltid mot huvudboken.

En lönespecifikation går igenom statusarna **Draft → Booked**.

Fas 1–2 täcker anställningsregister, lönespecifikation, bokföring, lönebesked och
inbetalning av skatt och arbetsgivaravgifter till skattekontot.
Arbetsgivardeklaration (AGI) och semesterlöneskuld hanteras i en senare fas.

## Datamodell

Lönehanteringen lägger till två saker i journalen (bägge additiva – inga
befintliga filer ändras och ingen schemamigrering krävs):

```
MinFirma.ledger/
├── employees.txt        # Tab-separerat: Nr  Namn  Personnr  Lönekonto  Skattesats
└── payslips/            # En fil per lönespecifikation
    ├── pay0001.txt
    └── pay0002.txt
```

En lönefil (`pay0001.txt`) innehåller metadata: bruttolön, preliminär skatt,
arbetsgivaravgiftens sats och de konton lönen bokförs på. Belopp och satser
lagras med punkt som decimaltecken (invariant kultur) så att de tab-separerade
kolumnerna inte bryts av ett lokalt kommatecken.

Lönespecifikationer lagras på journalnivå (inte inuti ett räkenskapsår) eftersom
en löneperiod kan bokföras i ett senare räkenskapsår än det den skapades i.

## Steg för steg

### 1. Lägg upp en anställd

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger

Add-LedgerEmployee -EmployeeNumber '1' -Name 'Anna Andersson' `
    -PersonalNumber '19850101-1234' -SalaryAccount '7210' -TaxRate 0.30
```

- `-SalaryAccount` (standard `7210` Löner till kollektivanställda) styr vilket
  kostnadskonto lönen bokförs på. Använd `7010` för tjänstemän.
- `-TaxRate` (standard 0) är den preliminära skattesatsen som används på nya
  lönespecifikationer när skatten inte anges explicit.

Uppdatera med `Set-LedgerEmployee` (bara de fält du anger ändras) och lista med
`Get-LedgerEmployee`.

```powershell
Set-LedgerEmployee -EmployeeNumber '1' -TaxRate 0.32
Get-LedgerEmployee | Format-Table EmployeeNumber, Name, SalaryAccount, TaxRate
```

### 2. Skapa en lönespecifikation

```powershell
New-LedgerPayslip -EmployeeNumber '1' -GrossSalary 30000 `
    -PeriodStart '2024-03-01' -PeriodEnd '2024-03-31' `
    -PayDate '2024-03-25' -Description 'Lön mars 2024'
```

Skatten räknas ut i den här ordningen: ett explicit `-TaxAmount`, annars
`-TaxRate` gånger bruttolönen, annars den anställdas standardskattesats.
Nettolönen är bruttolön minus skatt. Arbetsgivaravgiften är bruttolönen gånger
`-EmployerContributionRate` (standard `0.3142`, den vanliga arbetsgivaravgiften).

- Ange antingen `-TaxAmount` eller `-TaxRate`, inte båda.
- `-SalaryAccount` styr kostnadskontot (standard = den anställdas konto).
- Kontona för skatteskuld, nettolön och arbetsgivaravgift är konfigurerbara med
  `-TaxLiabilityAccount` (2710), `-NetPayAccount` (1930),
  `-EmployerContributionAccount` (7510) och
  `-EmployerContributionLiabilityAccount` (2730).
- Lönespecifikationsnummer räknas upp automatiskt (`pay0001`, `pay0002`, …).

De uträknade beloppen syns med `-PassThru` eller via `Get-LedgerPayslip`:

```powershell
Get-LedgerPayslip | Format-Table PayslipNumber, EmployeeName, GrossSalary, TaxAmount, NetPay, EmployerContribution
```

### 3. Bokför lönen

Bokföringen skapar en verifikation: kostnadskontot debiteras med bruttolönen,
skatteskulden krediteras med skatten, banken krediteras med nettolönen, och
arbetsgivaravgiften bokförs som både kostnad och skuld.

```powershell
Invoke-LedgerPayrollPosting -PayslipNumber 1
```

Ger verifikationen (bruttolön 30 000, skatt 30 %, avgift 31,42 %):

```
7210 Löner                    +30000
2710 Personalskatt             -9000
1930 Företagskonto            -21000
7510 Arbetsgivaravgifter       +9426
2730 Arbetsgivaravgift skuld   -9426
```

Räkenskapsåret hämtas från utbetalningsdatumet (ange `-FiscalYear` för att styra
det). Lönespecifikationen får status `Booked` och sparar `BookedVerification`
och `BookedFiscalYear`. Att bokföra en redan bokförd lönespecifikation ger ett
fel.

### 4. Skriv ut ett lönebesked

`Export-LedgerPayslip` skriver ut ett enskilt lönebesked som ett dokument – PDF
(standard), Word, Markdown eller ren text. PDF:en skapas av den inbyggda,
beroendefria PDF-generatorn (inga externa moduler).

```powershell
Export-LedgerPayslip -PayslipNumber 1 -Path .\lonebesked-1.pdf
Export-LedgerPayslip -PayslipNumber 1 -Path .\lonebesked-1.docx -Format Word -Force
```

Dokumentet innehåller arbetsgivaren (från journalen), den anställda, löneperiod
och utbetalningsdatum, bruttolön, preliminär skatt, nettolön att utbetala samt
arbetsgivaravgiften.

### 5. Betala skatt och arbetsgivaravgifter till skattekontot

När lönen är bokförd ligger den avdragna skatten på 2710 (Personalskatt) och
arbetsgivaravgiften på 2730 (Arbetsgivaravgift skuld) som skulder. Nästa månad
betalas de in till Skatteverkets skattekonto. `Add-LedgerPayrollTaxPayment`
skapar den verifikationen: skuldkontona debiteras och betalkontot (1930)
krediteras.

```powershell
# Betala hela den utestående skatten och avgiften (nollar 2710 och 2730)
Add-LedgerPayrollTaxPayment -Date '2024-04-12'
```

Ger verifikationen:

```
2710 Personalskatt            +9000
2730 Arbetsgivaravgift skuld  +9426
1930 Företagskonto           -18426
```

- Utan belopp betalas de utestående saldona på skuldkontona i räkenskapsåret, så
  att de nollställs och lönehanteringen stämmer mot huvudboken.
- Ange `-TaxAmount` och/eller `-EmployerContributionAmount` för att betala exakta
  belopp.
- `-Account` styr betalkontot (standard `1930`) och räkenskapsåret hämtas från
  betalningsdatumet.

### 6. Anställda och personalkostnader i årsredovisningen

`Get-LedgerEmployeeNote` bygger noten *Anställda och personalkostnader*. Den
härleder nu medelantalet anställda från antalet distinkta anställda med en
bokförd lönespecifikation under året (om det inte anges explicit eller via
`Set-LedgerReportInput`), och summerar personalkostnaderna på konton 7000–7699:

```powershell
Get-LedgerEmployeeNote | Format-List AverageEmployees, PersonnelCosts, Statement
```

## Avstämning mot huvudboken

Eftersom bokföringen skapar en verifikation stämmer lönehanteringen mot
bokföringen. Efter bokförda men ännu inte inbetalda löner motsvarar saldot på
skuldkontona den skatt och de avgifter som ska betalas till skattekontot, och
`Add-LedgerPayrollTaxPayment` nollställer dem vid inbetalningen:

```powershell
$b = Get-LedgerBalance
"Personalskatt (2710): $(($b | Where-Object AccountNumber -eq '2710').Balance)"
"Arbetsgivaravgift skuld (2730): $(($b | Where-Object AccountNumber -eq '2730').Balance)"
```

## Kommandon

| Kommando | Beskrivning |
|----------|-------------|
| `Add-LedgerEmployee` | Lägg till en anställd i registret |
| `Get-LedgerEmployee` | Lista eller slå upp anställda |
| `Set-LedgerEmployee` | Uppdatera anställningsuppgifter |
| `New-LedgerPayslip` | Skapa en lönespecifikation (utkast) |
| `Get-LedgerPayslip` | Lista lönespecifikationer, filtrera på status/anställd |
| `Invoke-LedgerPayrollPosting` | Bokför en lönespecifikation (skapar verifikation) |
| `Add-LedgerPayrollTaxPayment` | Bokför inbetalning av skatt och avgifter till skattekontot |
| `Export-LedgerPayslip` | Exportera ett lönebesked till PDF, Word, Markdown eller text |

## Kommande faser

- **Fas 3** – Arbetsgivardeklaration på individnivå (AGI) och semesterlöneskuld.

Se även [Fakturahantering](Fakturahantering.md) och
[Leverantörsreskontra](Leverantorsreskontra.md) för kund- och
leverantörsreskontra.
