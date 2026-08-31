# Inkomstdeklaration (INK2) via SRU-fil

`Export-LedgerIncomeTaxReturn` skapar en färdig **inkomstdeklaration 2** för ett
aktiebolag i Skatteverkets **SRU-format**, så att du kan ladda upp den i
Skatteverkets filöverföringstjänst i stället för att fylla i räkenskapsschemat
för hand.

En SRU-inlämning består alltid av **två filer** som läggs i en målmapp:

| Fil | Innehåll |
|-----|----------|
| `INFO.SRU` | Uppgifter om uppgiftslämnaren (orgnr, namn, postadress) |
| `BLANKETTER.SRU` | Själva deklarationsblanketterna |

För ett aktiebolag skapas tre blankettblock:

| Block | Blankett | Källa i PSLedger |
|-------|----------|------------------|
| **INK2R** | Räkenskapsschema (balans- och resultaträkning) | Härleds automatiskt ur saldobalansen via den officiella BAS→SRU-mappningen |
| **INK2** | Huvudblankett (räkenskapsår + över-/underskott) | Datum ur `year.txt`, överskott ur INK2S |
| **INK2S** | Skattemässiga justeringar | Årets resultat, bokförd skatt och egna justeringar |

## Så härleds beloppen

- **Tillgångar (konto 1xxx)** rapporteras med sitt naturliga tecken (debet = positivt).
- **Eget kapital och skulder (konto 2xxx)** negeras så att ett kreditsaldo blir positivt.
- **Resultaträkningen (konto 3xxx–8xxx)** negeras så att intäkter blir positiva och
  kostnader negativa – samma teckenkonvention som `Get-LedgerIncomeStatement`.
- **Årets resultat** och **totalt eget kapital** beräknas från hela kontointervallet
  och årets resultat vävs in i fritt eget kapital (SRU 7302), så att balansräkningen
  alltid stämmer även om något ovanligt konto inte klassificeras på en egen rad.
  Årets resultat skrivs även ut som resultaträkningens slutrad på INK2R
  (SRU 7450 vinst / 7550 förlust).

Beloppen anges i **hela kronor** (ören avkortas enligt SFL 22:1), organisationsnumret
skrivs i **12-siffrig form** (`556677-8899` → `165566778899`) och filerna skrivs med
**ISO-8859-1**-kodning – allt enligt formatets krav.

Kör exporten på ett räkenskapsår vars resultat **ännu inte** är disponerat mot eget
kapital (det normala arbetsflödet), på samma sätt som resultaträkningen visar det
öppna årets resultat.

## Steg för steg

```powershell
Set-LedgerCurrentJournal -Path .\MinFirma.ledger
Set-LedgerCurrentFiscalYear -FiscalYear '2024-01_2024-12'

# Postnummer och postort krävs i INFO.SRU. Ange dem antingen som parametrar ...
Export-LedgerIncomeTaxReturn -Path .\sru -PostalCode '11122' -City 'Stockholm'

# ... eller lagra dem en gång i journalens metadata så räcker det med -Path:
Set-LedgerJournal -Metadata @{ PostalCode = '11122'; City = 'Stockholm'
                               ContactPerson = 'Anna Andersson'; Email = 'anna@minfirma.se' }
Export-LedgerIncomeTaxReturn -Path .\sru
```

Resultatet blir `.\sru\INFO.SRU` och `.\sru\BLANKETTER.SRU`.

## Skattemässiga justeringar

Utan justeringar sätts överskottet (INK2S 8020 / INK2 7113) till *årets resultat +
bokförd inkomstskatt* (skatten återförs som en ej avdragsgill kostnad, SRU 7651) –
det vanligaste minsta fallet.

Behöver du fler justeringar anger du dem med `-TaxAdjustment` som en hashtabell från
SRU-kod till belopp i hela kronor. Varje post skrivs som en INK2S-rad och räknas
(med sitt tecken) in i överskottet:

```powershell
# Lägg till schablonintäkt på periodiseringsfonder (SRU 7654)
Export-LedgerIncomeTaxReturn -Path .\sru -TaxAdjustment @{ '7654' = 940 }
```

Anger du själv `8020` eller `8021` i hashtabellen används det värdet som
över-/underskott i stället för det beräknade.

## Att tänka på innan du laddar upp

- **Byt inte namn på filerna.** Webbläsare som lägger till `(1)` gör att uppladdningen
  avvisas.
- Räkenskapsschemat följer den officiella BAS→SRU-mappningen, men **INK2S kräver
  bedömning** – kontrollera de skattemässiga justeringarna innan du lämnar in.
- Blanketternas periodsuffix (`P1`/`P2`/`P4`) och inkomstår sätts efter räkenskapsårets
  slutmånad.
