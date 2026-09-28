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
- **Resultaträkningen (konto 3xxx–8xxx)** anges **som på blanketten**: radens
  förtryckta tecken (+/−) anger riktningen, så kostnader, avdrag och förlust skrivs
  som positiva belopp (t.ex. 3.7 Övriga externa kostnader = 1 400). Ett negativt
  belopp förekommer bara när värdet går mot det förtryckta tecknet, t.ex. en bokförd
  skatteintäkt på 3.25. Rader som är delade i ett (+)- och ett (−)-fält (3.2,
  3.12–3.15, 3.23, 3.24) får det fält som motsvarar radens nettobelopp.
- Fältkoder, rader och tecken följer Skatteverkets fältnamnstabeller för
  INK2/INK2R/INK2S och kontointervallen BAS officiella kopplingstabell.
- **Årets resultat** (INK2R 3.26/3.27, SRU 7450 vinst / 7550 förlust, och INK2S
  4.1/4.2) är summan av resultaträkningens avkortade rader, och **fritt eget kapital**
  (SRU 7302) är balansräkningens balanserande post. Blanketten går därför alltid
  ihop på kronan, även om något ovanligt konto inte klassificeras på en egen rad.
- **Skattekontot och skatteskulder** redovisas efter saldots tecken: ett debetsaldo
  på 25xx blir en fordran (2.21, SRU 7261) och ett kreditsaldo på 163x blir en
  skatteskuld (2.49, SRU 7368).

Beloppen anges i **hela kronor** (ören avkortas enligt SFL 22:1), organisationsnumret
skrivs i **12-siffrig form** (`556677-8899` → `165566778899`) och filerna skrivs med
**ISO-8859-1**-kodning – allt enligt formatets krav.

Exporten fungerar både före och efter att årets resultat har förts mot eget kapital
(8999/2099) – resultatet är detsamma.

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

Fyller du i blanketten för hand (eller vill kontrollera filen) listar egenskapen
`Fields` varje ifyllt fält med blankett, ruta, SRU-kod och belopp:

```powershell
(Export-LedgerIncomeTaxReturn -Path .\sru -Force).Fields | Format-Table

# Form  Box   SruCode Amount Description
# ----  ---   ------- ------ -----------
# INK2  1.1      7104  22960 Överskott av näringsverksamhet
# INK2R 3.7      7513   1400 Övriga externa kostnader
# INK2S 4.3a     7651 -17740 Bokförda kostnader som inte ska dras av: skatt på årets resultat
# ...
```

## Skattemässiga justeringar

Överskottet (INK2S 4.15 / INK2 1.1, SRU 7670 / 7104) beräknas som *årets resultat +
bokförd inkomstskatt* (skatten återförs som en ej avdragsgill kostnad, 4.3a / SRU
7651) plus de skattemässiga justeringarna med sitt förtryckta tecken. Ett underskott
hamnar på 4.16 / 1.2 (SRU 7770 / 7114). Upplysningsrutorna 4.17–4.22 påverkar inte
överskottet.

### Automatiska justeringar

Justeringar som följer av själva BAS-kontot räknas fram ur saldobalansen:

| Ruta (SRU) | Konton | Behandling |
|------------|--------|------------|
| 4.3c (7653) | 6072, 6982, 6992, 7622, 7632, 8423 | Ej avdragsgilla kostnader (representation, föreningsavgifter, kostnadsränta på skattekontot m.m.) läggs tillbaka |
| 4.5c (7754) | 8314 | Skattefria ränteintäkter dras av |
| 4.3b (7652) | 8270–8289 | Nettonedskrivning av andelar i andra företag läggs tillbaka; en nettoåterföring dras av på 4.5c (7754) |

Regeln för 827x/828x bygger på ett **antagande**: att aktierna är
kapitalplaceringsaktier, vars nedskrivningar inte är avdragsgilla och vars
återföringar inte är skattepliktiga. Exporten skriver därför en varning när regeln
används. Gäller nedskrivningen lageraktier eller något annat avdragsgillt ersätter
du beloppet med `-TaxAdjustment` (t.ex. `@{ '4.3b' = 0 }`), eller stänger av alla
automatiska justeringar med `-NoAutomaticAdjustment`.

### Egna justeringar

Behöver du fler justeringar anger du dem med `-TaxAdjustment` som en hashtabell från
**ruta på blanketten** (t.ex. `'4.6a'`) eller SRU-kod (t.ex. `'7654'`) till belopp i
hela kronor. Rader med både ett (+)- och ett (−)-fält kräver suffix: `'4.13+'` eller
`'4.13-'`. Ange beloppen som på blanketten (positiva). Varje post skrivs som en
INK2S-rad, ersätter ett automatiskt framräknat belopp för samma fält och räknas med
radens tecken in i överskottet:

```powershell
# Schablonintäkt på periodiseringsfonder (4.6a) och en övrig avdragspost (4.13 −)
Export-LedgerIncomeTaxReturn -Path .\sru -TaxAdjustment @{ '4.6a' = 940; '4.13-' = 500 }
```

Fält som Skatteverket bara godtar som positiva (t.ex. 4.13+, 4.15) ger ett fel om
beloppet blir negativt. Årets resultat (4.1/4.2) hämtas alltid ur bokföringen.

Justeringarna som användes finns i resultatobjektets egenskap `TaxAdjustments`.

Anger du själv `'4.15'` eller `'4.16'` (SRU 7670/7770) används det värdet som
över-/underskott i stället för det beräknade.

### Upplysningar längst ner på INK2S

De två Ja/Nej-frågorna besvaras med `-ConsultantAssisted` (uppdragstagare, t.ex.
redovisningskonsult, har biträtt vid upprättandet av årsredovisningen, SRU
8040/8041) och `-Audited` (årsredovisningen har varit föremål för revision, SRU
8044/8045). Utelämnas parametern lämnas frågan obesvarad.

```powershell
# Bolaget har upprättat årsredovisningen själv och har ingen revisor
Export-LedgerIncomeTaxReturn -Path .\sru -ConsultantAssisted $false -Audited $false
```

## Att tänka på innan du laddar upp

- **Filerna ska laddas upp i e-tjänsten Filöverföring och deklarationen måste
  sedan skrivas under** av firmatecknare eller deklarationsombud. En uppladdad men
  osignerad deklaration räknas inte som inlämnad.
- Filöverföringen öppnar för **testfiler** ungefär en månad innan
  produktionsingången öppnar – ett bra sätt att kontrollera filerna i förväg.
- **Byt inte namn på filerna.** Webbläsare som lägger till `(1)` gör att uppladdningen
  avvisas.
- Räkenskapsschemat följer den officiella BAS→SRU-mappningen, men **INK2S kräver
  bedömning** – kontrollera de skattemässiga justeringarna innan du lämnar in.
- Blanketternas periodsuffix och inkomstår sätts efter räkenskapsårets slutmånad:
  `P1` januari–april, `P2` maj–juni, `P3` juli–augusti, `P4` september–december.
