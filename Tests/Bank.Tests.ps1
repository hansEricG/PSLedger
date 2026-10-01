BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
    . (Join-Path $PSScriptRoot '_LedgerTestHelpers.ps1')

    $script:FY = '2024-01_2024-12'

    function New-BankTestJournal {
        param([string]$Root)
        return New-TestLedger -Root $Root `
            -Customers @(@{ Number = '10'; Name = 'Volvo AB' }) `
            -Suppliers @(@{ Number = '100'; Name = 'Kontorsbolaget AB' })
    }

    # Builds a camt.053 statement. Each entry is a hashtable with Date, Amount
    # (signed), Ref (AcctSvcrRef) and optional Ocr, Ustrd, Info, Party, Status
    # and Details (array of @{ Amount; Ocr; Party } for batch entries).
    function New-CamtFile {
        param(
            [string]$Path,
            [decimal]$Opening,
            [hashtable[]]$Entries,
            [string]$From = '2024-03-01',
            [string]$To = '2024-03-31',
            [string]$Id = 'STMT-2024-03',
            [string]$Iban = 'SE4550000000058398257466'
        )
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $fmt = { param($a) ([Math]::Abs([decimal]$a)).ToString('0.00', $inv) }
        $ind = { param($a) if ($a -lt 0) { 'DBIT' } else { 'CRDT' } }
        $closing = $Opening
        foreach ($e in $Entries) { if (-not $e.Status -or $e.Status -eq 'BOOK') { $closing += $e.Amount } }

        $txXml = {
            param($d, $sign)
            $party = if ($d.Party) {
                if ($sign -lt 0) { "<RltdPties><Cdtr><Nm>$($d.Party)</Nm></Cdtr></RltdPties>" } else { "<RltdPties><Dbtr><Nm>$($d.Party)</Nm></Dbtr></RltdPties>" }
            } else { '' }
            $rmt = ''
            if ($d.Ocr) { $rmt = "<RmtInf><Strd><CdtrRefInf><Ref>$($d.Ocr)</Ref></CdtrRefInf></Strd></RmtInf>" }
            elseif ($d.Ustrd) { $rmt = "<RmtInf><Ustrd>$($d.Ustrd)</Ustrd></RmtInf>" }
            $amt = if ($d.ContainsKey('Amount') -and $d.IsDetail) { "<AmtDtls><TxAmt><Amt Ccy=`"SEK`">$(& $fmt $d.Amount)</Amt></TxAmt></AmtDtls>" } else { '' }
            "<TxDtls>$amt$party$rmt</TxDtls>"
        }

        $ntries = foreach ($e in $Entries) {
            $status = if ($e.Status) { $e.Status } else { 'BOOK' }
            $details = if ($e.Details) {
                ($e.Details | ForEach-Object { $h = $_.Clone(); $h.IsDetail = $true; & $txXml $h $e.Amount }) -join ''
            } else { & $txXml $e $e.Amount }
            $info = if ($e.Info) { "<AddtlNtryInf>$($e.Info)</AddtlNtryInf>" } else { '' }
@"
      <Ntry>
        <Amt Ccy="SEK">$(& $fmt $e.Amount)</Amt>
        <CdtDbtInd>$(& $ind $e.Amount)</CdtDbtInd>
        <Sts>$status</Sts>
        <BookgDt><Dt>$($e.Date)</Dt></BookgDt>
        <ValDt><Dt>$($e.Date)</Dt></ValDt>
        <AcctSvcrRef>$($e.Ref)</AcctSvcrRef>
        <NtryDtls>$details</NtryDtls>
        $info
      </Ntry>
"@
        }

        $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">
  <BkToCstmrStmt>
    <GrpHdr><MsgId>MSG1</MsgId><CreDtTm>2024-04-01T06:00:00</CreDtTm></GrpHdr>
    <Stmt>
      <Id>$Id</Id>
      <CreDtTm>2024-04-01T06:00:00</CreDtTm>
      <FrToDt><FrDtTm>$($From)T00:00:00</FrDtTm><ToDtTm>$($To)T23:59:59</ToDtTm></FrToDt>
      <Acct><Id><IBAN>$Iban</IBAN></Id><Ccy>SEK</Ccy></Acct>
      <Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="SEK">$(& $fmt $Opening)</Amt><CdtDbtInd>$(& $ind $Opening)</CdtDbtInd><Dt><Dt>$From</Dt></Dt></Bal>
      <Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy="SEK">$(& $fmt $closing)</Amt><CdtDbtInd>$(& $ind $closing)</CdtDbtInd><Dt><Dt>$To</Dt></Dt></Bal>
$($ntries -join "`n")
    </Stmt>
  </BkToCstmrStmt>
</Document>
"@
        Set-Content -Path $Path -Value $xml -Encoding UTF8
        return $Path
    }
}

Describe 'Bank commands metadata' {
    It '<_> is an advanced function' -ForEach @(
        'Import-LedgerBankStatement', 'Get-LedgerBankStatement', 'Get-LedgerBankTransaction',
        'Invoke-LedgerBankMatching', 'Set-LedgerBankTransaction', 'Get-LedgerBankReconciliation',
        'Add-LedgerBankRule', 'Get-LedgerBankRule', 'Remove-LedgerBankRule'
    ) {
        Test-TDDCmdletBinding (Get-Command -Name $_) | Should -BeTrue
    }

    It 'Import-LedgerBankStatement has a mandatory Path parameter' {
        (Get-Command Import-LedgerBankStatement).Parameters['Path'].Attributes.Mandatory | Should -Contain $true
    }

    It 'Set-LedgerBankTransaction has a mandatory TransactionId parameter' {
        (Get-Command Set-LedgerBankTransaction).Parameters['TransactionId'].Attributes.Mandatory | Should -Contain $true
    }

    It 'Add-LedgerBankRule has mandatory Pattern and Account parameters' {
        foreach ($p in 'Pattern', 'Account') {
            (Get-Command Add-LedgerBankRule).Parameters[$p].Attributes.Mandatory | Should -Contain $true
        }
    }
}

Describe 'Import-LedgerBankStatement (camt.053)' {
    BeforeEach {
        $JournalPath = New-BankTestJournal -Root $TestDrive
        $camt = New-CamtFile -Path (Join-Path $TestDrive 'stmt.xml') -Opening 50000 -Entries @(
            @{ Date = '2024-03-20'; Amount = 12500; Ref = 'A1'; Ocr = '133'; Party = 'Volvo AB' }
            @{ Date = '2024-03-25'; Amount = -10000; Ref = 'A2'; Ustrd = 'Faktura F-99123'; Party = 'Kontorsbolaget AB' }
            @{ Date = '2024-03-31'; Amount = -45; Ref = 'A3'; Info = 'Bankavgift mars' }
            @{ Date = '2024-03-29'; Amount = 3000; Ref = 'A4'; Details = @(@{ Amount = 1000; Ocr = '1111' }, @{ Amount = 2000; Ocr = '2222'; Party = 'Scania AB' }) }
            @{ Date = '2024-03-30'; Amount = 999; Ref = 'P1'; Status = 'PDNG'; Ustrd = 'Pending' }
        )
    }

    It 'Creates bank/stmt0001.txt' {
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
        Test-Path (Join-Path $JournalPath 'bank\stmt0001.txt') | Should -BeTrue
    }

    It 'Returns a summary with imported count and balances' {
        $r = Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt
        $r.StatementNumber | Should -Be 1
        $r.Imported | Should -Be 5
        $r.Skipped | Should -Be 0
        $r.OpeningBalance | Should -Be 50000
        $r.ClosingBalance | Should -Be 55455
        $r.FromDate | Should -Be ([datetime]'2024-03-01')
        $r.ToDate | Should -Be ([datetime]'2024-03-31')
    }

    It 'Skips entries that are not booked' {
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
        Get-LedgerBankTransaction -JournalPath $JournalPath | Where-Object Amount -eq 999 | Should -BeNullOrEmpty
    }

    It 'Signs amounts from CdtDbtInd and reads reference, counterparty and text' {
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
        $tx = @(Get-LedgerBankTransaction -JournalPath $JournalPath)
        $in = $tx | Where-Object BankReference -eq 'A1'
        $in.Amount | Should -Be 12500
        $in.Reference | Should -Be '133'
        $in.Counterparty | Should -Be 'Volvo AB'
        $in.Date | Should -Be ([datetime]'2024-03-20')
        $out = $tx | Where-Object BankReference -eq 'A2'
        $out.Amount | Should -Be (-10000)
        $out.Counterparty | Should -Be 'Kontorsbolaget AB'
        $out.Text | Should -Be 'Faktura F-99123'
        ($tx | Where-Object BankReference -eq 'A3').Text | Should -Be 'Bankavgift mars'
    }

    It 'Splits a batch entry into one transaction per detail' {
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
        $batch = @(Get-LedgerBankTransaction -JournalPath $JournalPath | Where-Object { $_.BankReference -like 'A4/*' })
        $batch.Count | Should -Be 2
        ($batch | Where-Object Reference -eq '2222').Amount | Should -Be 2000
        ($batch | Where-Object Reference -eq '2222').Counterparty | Should -Be 'Scania AB'
    }

    It 'Starts every transaction as Unmatched with unique ids' {
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
        $tx = @(Get-LedgerBankTransaction -JournalPath $JournalPath)
        $tx | ForEach-Object { $_.Status | Should -Be 'Unmatched' }
        ($tx.TransactionId | Select-Object -Unique).Count | Should -Be $tx.Count
    }

    It 'Skips transactions already imported' {
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
        $r = Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt -WarningAction SilentlyContinue
        $r.Imported | Should -Be 0
        $r.Skipped | Should -Be 5
        @(Get-LedgerBankStatement -JournalPath $JournalPath).Count | Should -Be 1
    }

    It 'Stores the transactions under the given bank account' {
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt -Account '1940' | Out-Null
        (Get-LedgerBankStatement -JournalPath $JournalPath).BankAccount | Should -Be '1940'
        @(Get-LedgerBankTransaction -JournalPath $JournalPath -Account '1930').Count | Should -Be 0
    }

    It 'Does not write anything with -WhatIf' {
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt -WhatIf | Out-Null
        Test-Path (Join-Path $JournalPath 'bank\stmt0001.txt') | Should -BeFalse
    }

    It 'Throws for a missing file' {
        { Import-LedgerBankStatement -JournalPath $JournalPath -Path (Join-Path $TestDrive 'nope.xml') } | Should -Throw '*not found*'
    }

    It 'Refuses a file with several bank accounts unless -AccountId selects one' {
        $a = New-CamtFile -Path (Join-Path $TestDrive 'a.xml') -Opening 0 -Iban 'SE0100000000000000000001' -Entries @(@{ Date = '2024-03-05'; Amount = 100; Ref = 'X1' })
        $b = New-CamtFile -Path (Join-Path $TestDrive 'b.xml') -Opening 0 -Iban 'SE0200000000000000000002' -Entries @(@{ Date = '2024-03-06'; Amount = 200; Ref = 'X2' })
        [xml]$docA = Get-Content $a -Raw
        [xml]$docB = Get-Content $b -Raw
        $stmtB = $docA.ImportNode($docB.Document.BkToCstmrStmt.Stmt, $true)
        [void]$docA.Document.BkToCstmrStmt.AppendChild($stmtB)
        $multi = Join-Path $TestDrive 'multi.xml'
        $docA.Save($multi)

        { Import-LedgerBankStatement -JournalPath $JournalPath -Path $multi } | Should -Throw '*several bank accounts*'
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $multi -AccountId 'SE02 0000 0000 0000 0000 0002' -Account '1940' | Out-Null
        (Get-LedgerBankTransaction -JournalPath $JournalPath).Amount | Should -Be 200
    }

    It 'Refuses a statement for another bank account in the same ledger account' {
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
        $other = New-CamtFile -Path (Join-Path $TestDrive 'other.xml') -Opening 0 -Iban 'SE0900000000000000000009' -Entries @(@{ Date = '2024-03-05'; Amount = 100; Ref = 'Y1' })
        { Import-LedgerBankStatement -JournalPath $JournalPath -Path $other } | Should -Throw '*already holds statements*'
    }
}

Describe 'Import-LedgerBankStatement (CSV)' {
    BeforeEach {
        $JournalPath = New-BankTestJournal -Root $TestDrive
    }

    It 'Detects the header after a preamble and reads Swedish amounts' {
        $csv = Join-Path $TestDrive 'bank.csv'
        @(
            '* Transaktioner Period 2024-03-01 – 2024-03-31 Skapad 2024-04-01'
            'Radnummer,Clearingnummer,Kontonummer,Produkt,Valuta,Bokföringsdag,Transaktionsdag,Valutadag,Referens,Beskrivning,Belopp,Bokfört saldo'
            '2,8327,1234567,Företagskonto,SEK,2024-03-31,2024-03-31,2024-03-31,"","Bankavgift","-45.00","62455.00"'
            '1,8327,1234567,Företagskonto,SEK,2024-03-20,2024-03-20,2024-03-20,"133","Volvo AB","12500.00","62500.00"'
        ) | Set-Content -Path $csv -Encoding UTF8

        $r = Import-LedgerBankStatement -JournalPath $JournalPath -Path $csv
        $r.Imported | Should -Be 2
        $r.OpeningBalance | Should -Be 50000
        $r.ClosingBalance | Should -Be 62455
        $tx = @(Get-LedgerBankTransaction -JournalPath $JournalPath)
        $tx[0].Date | Should -Be ([datetime]'2024-03-20')
        $tx[0].Amount | Should -Be 12500
        $tx[0].Reference | Should -Be '133'
        $tx[1].Amount | Should -Be (-45)
        $tx[1].Text | Should -Be 'Bankavgift'
    }

    It 'Uses an explicit column mapping, semicolons, decimal comma and ISO-8859-1' {
        $csv = Join-Path $TestDrive 'bank2.csv'
        $content = "Datum;Transaktion;Kategori;Belopp;Saldo`r`n2024-03-05;Månadsavgift;Avgift;-1 234,50;8 765,50`r`n"
        [System.IO.File]::WriteAllBytes($csv, [System.Text.Encoding]::GetEncoding(28591).GetBytes($content))

        Import-LedgerBankStatement -JournalPath $JournalPath -Path $csv -DateColumn 'Datum' -AmountColumn 'Belopp' -TextColumn 'Transaktion' -BalanceColumn 'Saldo' | Out-Null
        $t = Get-LedgerBankTransaction -JournalPath $JournalPath
        $t.Amount | Should -Be (-1234.50)
        $t.Text | Should -Be 'Månadsavgift'
        (Get-LedgerBankStatement -JournalPath $JournalPath).ClosingBalance | Should -Be 8765.50
    }

    It 'Keeps identical transactions in the same file but skips them on re-import' {
        $csv = Join-Path $TestDrive 'bank3.csv'
        @(
            'Datum;Text;Belopp'
            '2024-03-05;Kortköp Pressbyrån;-35,00'
            '2024-03-05;Kortköp Pressbyrån;-35,00'
        ) | Set-Content -Path $csv -Encoding UTF8
        (Import-LedgerBankStatement -JournalPath $JournalPath -Path $csv).Imported | Should -Be 2
        $again = Import-LedgerBankStatement -JournalPath $JournalPath -Path $csv -WarningAction SilentlyContinue
        $again.Imported | Should -Be 0
        @(Get-LedgerBankTransaction -JournalPath $JournalPath).Count | Should -Be 2
    }

    It 'Throws when no header row can be found' {
        $csv = Join-Path $TestDrive 'bad.csv'
        @('a;b;c', '1;2;3') | Set-Content -Path $csv -Encoding UTF8
        { Import-LedgerBankStatement -JournalPath $JournalPath -Path $csv } | Should -Throw '*header row*'
    }
}

Describe 'Bank rules' {
    BeforeEach {
        $JournalPath = New-BankTestJournal -Root $TestDrive
    }

    It 'Adds and lists rules in priority order' {
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Bankavgift' -Account '6570' -Description 'Bankavgift'
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Ränta*' -Account '8310'
        $rules = @(Get-LedgerBankRule -JournalPath $JournalPath)
        $rules.Count | Should -Be 2
        $rules[0].Pattern | Should -Be 'Bankavgift'
        $rules[0].Priority | Should -Be 1
        $rules[1].Account | Should -Be '8310'
    }

    It 'Rejects a duplicate pattern' {
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Bankavgift' -Account '6570'
        { Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Bankavgift' -Account '6570' } | Should -Throw '*already exists*'
    }

    It 'Rejects an unknown account' {
        { Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'X' -Account '9999' } | Should -Throw '*does not exist*'
    }

    It 'Requires a VAT account with a VAT rate' {
        { Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'X' -Account '5410' -VatRate 0.25 } | Should -Throw '*VatAccount*'
    }

    It 'Removes a rule' {
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Bankavgift' -Account '6570'
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Ränta' -Account '8310'
        Remove-LedgerBankRule -JournalPath $JournalPath -Pattern 'Bankavgift'
        @(Get-LedgerBankRule -JournalPath $JournalPath).Pattern | Should -Be @('Ränta')
    }

    It 'Throws when removing a rule that does not exist' {
        { Remove-LedgerBankRule -JournalPath $JournalPath -Pattern 'Nope' } | Should -Throw '*does not exist*'
    }
}

Describe 'Invoke-LedgerBankMatching' {
    BeforeEach {
        $JournalPath = New-BankTestJournal -Root $TestDrive
        $invNo = New-TestPostedInvoice -JournalPath $JournalPath -Date '2024-03-01'
        $ocr = (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber $invNo).OcrReference
        New-LedgerSupplierInvoice -JournalPath $JournalPath -SupplierNumber '100' -Date '2024-03-10' -Description 'Hyra' `
            -SupplierReference 'F-99123' -Reference '1234567' `
            -Rows @(@{ Account = '5010'; Amount = 8000; VatRate = 0.25; VatAccount = '2640' }) | Out-Null
        Invoke-LedgerSupplierInvoicePosting -JournalPath $JournalPath -InvoiceNumber 1
        # A salary payment already booked by hand, two days before the bank date.
        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY -Date '2024-03-26' -Description 'Lön mars' `
            -Rows @(@{ Account = '2890'; Amount = 21000 }, @{ Account = '1930'; Amount = -21000 })
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Bankavgift' -Account '6570' -Description 'Bankavgift'

        $camt = New-CamtFile -Path (Join-Path $TestDrive 'match.xml') -Opening 50000 -Entries @(
            @{ Date = '2024-03-20'; Amount = 12500; Ref = 'A1'; Ocr = $ocr; Party = 'Volvo AB' }
            @{ Date = '2024-03-25'; Amount = -10000; Ref = 'A2'; Ocr = '1234567'; Party = 'Kontorsbolaget AB' }
            @{ Date = '2024-03-28'; Amount = -21000; Ref = 'A3'; Ustrd = 'Lön' }
            @{ Date = '2024-03-31'; Amount = -45; Ref = 'A4'; Info = 'Bankavgift mars' }
            @{ Date = '2024-03-31'; Amount = 777; Ref = 'A5'; Ustrd = 'Okänd insättning' }
        )
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
    }

    It 'Registers an OCR payment on the customer invoice' {
        Invoke-LedgerBankMatching -JournalPath $JournalPath | Out-Null
        $inv = Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1
        $inv.Status | Should -Be 'Paid'
        $t = Get-LedgerBankTransaction -JournalPath $JournalPath | Where-Object BankReference -eq 'A1'
        $t.Status | Should -Be 'Matched'
        $t.MatchType | Should -Be 'CustomerInvoice'
        $t.MatchRef | Should -Be '1'
        $t.VerificationNumber | Should -Be $inv.Payments[0].VerificationNumber
    }

    It 'Registers the supplier payment by reference' {
        Invoke-LedgerBankMatching -JournalPath $JournalPath | Out-Null
        (Get-LedgerSupplierInvoice -JournalPath $JournalPath -InvoiceNumber 1).Status | Should -Be 'Paid'
        (Get-LedgerBankTransaction -JournalPath $JournalPath | Where-Object BankReference -eq 'A2').MatchType | Should -Be 'SupplierInvoice'
    }

    It 'Links to an existing verification instead of posting a new one' {
        $before = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count
        Invoke-LedgerBankMatching -JournalPath $JournalPath | Out-Null
        $t = Get-LedgerBankTransaction -JournalPath $JournalPath | Where-Object BankReference -eq 'A3'
        $t.MatchType | Should -Be 'Entry'
        $t.VerificationNumber | Should -Be 3
        # Customer payment, supplier payment and bank fee are new; the salary is not.
        @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count | Should -Be ($before + 3)
    }

    It 'Posts a rule match against the rule account' {
        Invoke-LedgerBankMatching -JournalPath $JournalPath | Out-Null
        $t = Get-LedgerBankTransaction -JournalPath $JournalPath | Where-Object BankReference -eq 'A4'
        $t.MatchType | Should -Be 'Rule'
        $e = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY -VerificationNumber $t.VerificationNumber
        $e.Description | Should -Be 'Bankavgift'
        ($e.Rows | Where-Object Account -eq '6570').Amount | Should -Be 45
        ($e.Rows | Where-Object Account -eq '1930').Amount | Should -Be (-45)
    }

    It 'Leaves transactions it cannot match unmatched' {
        $matched = @(Invoke-LedgerBankMatching -JournalPath $JournalPath)
        $matched.Count | Should -Be 4
        $open = @(Get-LedgerBankTransaction -JournalPath $JournalPath -Status Unmatched)
        $open.Count | Should -Be 1
        $open[0].Amount | Should -Be 777
    }

    It 'Is idempotent' {
        Invoke-LedgerBankMatching -JournalPath $JournalPath | Out-Null
        $count = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count
        @(Invoke-LedgerBankMatching -JournalPath $JournalPath).Count | Should -Be 0
        @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count | Should -Be $count
    }

    It 'Does not post or link anything with -WhatIf' {
        $count = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count
        Invoke-LedgerBankMatching -JournalPath $JournalPath -WhatIf | Out-Null
        @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count | Should -Be $count
        @(Get-LedgerBankTransaction -JournalPath $JournalPath -Status Unmatched).Count | Should -Be 5
    }

    It 'Skips rules with -NoRules' {
        Invoke-LedgerBankMatching -JournalPath $JournalPath -NoRules | Out-Null
        (Get-LedgerBankTransaction -JournalPath $JournalPath | Where-Object BankReference -eq 'A4').Status | Should -Be 'Unmatched'
    }

    It 'Splits VAT when the rule has a VAT rate' {
        Remove-LedgerBankRule -JournalPath $JournalPath -Pattern 'Bankavgift'
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Okänd*' -Account '5410' -VatRate 0.25 -VatAccount '2640'
        Invoke-LedgerBankMatching -JournalPath $JournalPath | Out-Null
        $t = Get-LedgerBankTransaction -JournalPath $JournalPath | Where-Object BankReference -eq 'A5'
        $e = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY -VerificationNumber $t.VerificationNumber
        ($e.Rows | Where-Object Account -eq '1930').Amount | Should -Be 777
        ($e.Rows | Where-Object Account -eq '5410').Amount | Should -Be (-621.60)
        ($e.Rows | Where-Object Account -eq '2640').Amount | Should -Be (-155.40)
    }
}

Describe 'Invoke-LedgerBankMatching (transfers between own accounts)' {
    BeforeEach {
        $JournalPath = New-BankTestJournal -Root $TestDrive
        Add-LedgerAccount -JournalPath $JournalPath -AccountNumber '1630' -AccountName 'Skattekonto'
        $from = New-CamtFile -Path (Join-Path $TestDrive 'from.xml') -Opening 50000 -Id 'S-1930' -Entries @(
            @{ Date = '2024-03-10'; Amount = -5000; Ref = 'T1'; Ustrd = 'Överföring sparkonto' }
        )
        $to = New-CamtFile -Path (Join-Path $TestDrive 'to.xml') -Opening 0 -Id 'S-1940' -Iban 'SE1100000000000000001940' -Entries @(
            @{ Date = '2024-03-11'; Amount = 5000; Ref = 'T1'; Ustrd = 'Överföring företagskonto' }
        )
        # The receiving account is imported first so it is processed first.
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $to -Account '1940' | Out-Null
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $from | Out-Null
    }

    It 'Links both sides of a transfer already booked by hand to the same verification' {
        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY -Date '2024-03-10' -Description 'Överföring' `
            -Rows @(@{ Account = '1940'; Amount = 5000 }, @{ Account = '1930'; Amount = -5000 })
        $count = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count
        @(Invoke-LedgerBankMatching -JournalPath $JournalPath).Count | Should -Be 2
        $t = @(Get-LedgerBankTransaction -JournalPath $JournalPath)
        $t.MatchType | Should -Be @('Entry', 'Entry')
        @($t.VerificationNumber | Select-Object -Unique).Count | Should -Be 1
        @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count | Should -Be $count
    }

    It 'Books a transfer posted by a rule only once and links the other side' {
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Överföring' -Account '1940' -Description 'Överföring sparkonto'
        $count = @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count
        @(Invoke-LedgerBankMatching -JournalPath $JournalPath).Count | Should -Be 2
        @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY).Count | Should -Be ($count + 1)
        $out = Get-LedgerBankTransaction -JournalPath $JournalPath -Account '1930'
        $in = Get-LedgerBankTransaction -JournalPath $JournalPath -Account '1940'
        $out.MatchType | Should -Be 'Rule'
        $in.MatchType | Should -Be 'Entry'
        $in.VerificationNumber | Should -Be $out.VerificationNumber
        (Get-LedgerBankReconciliation -JournalPath $JournalPath -Account '1940' -AsOf '2024-03-31').Status | Should -Be 'Reconciled'
    }

    It 'Links a payment to the tax account' {
        $tax = Join-Path $TestDrive 'skattekonto.csv'
        @(
            'Datum;Text;Belopp'
            '2024-03-12;Inbetalning bokförd;5000,00'
        ) | Set-Content -Path $tax -Encoding UTF8
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $tax -Account '1630' | Out-Null
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Överföring sparkonto' -Account '1630' -Description 'Inbetalning skattekonto'
        Invoke-LedgerBankMatching -JournalPath $JournalPath -Account '1930' | Out-Null
        $out = Get-LedgerBankTransaction -JournalPath $JournalPath -Account '1930'
        $taxT = Get-LedgerBankTransaction -JournalPath $JournalPath -Account '1630'
        $taxT.Status | Should -Be 'Matched'
        $taxT.VerificationNumber | Should -Be $out.VerificationNumber
        # The 1940 deposit was not part of the transfer and stays open.
        (Get-LedgerBankTransaction -JournalPath $JournalPath -Account '1940').Status | Should -Be 'Unmatched'
    }
}

Describe 'Set-LedgerBankTransaction' {
    BeforeEach {
        $JournalPath = New-BankTestJournal -Root $TestDrive
        New-TestPostedInvoice -JournalPath $JournalPath -Date '2024-03-01' | Out-Null
        New-TestPostedSupplierInvoice -JournalPath $JournalPath -Date '2024-03-10' | Out-Null
        $camt = New-CamtFile -Path (Join-Path $TestDrive 'manual.xml') -Opening 0 -Entries @(
            @{ Date = '2024-03-20'; Amount = 12500; Ref = 'B1'; Ustrd = 'Betalning' }
            @{ Date = '2024-03-21'; Amount = -10000; Ref = 'B2'; Ustrd = 'Betalning' }
            @{ Date = '2024-03-22'; Amount = -125; Ref = 'B3'; Ustrd = 'Kontorsmaterial' }
            @{ Date = '2024-03-23'; Amount = -500; Ref = 'B4'; Ustrd = 'Överföring' }
        )
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
    }

    It 'Registers a customer payment with -InvoiceNumber' {
        Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 1 -InvoiceNumber 1
        (Get-LedgerInvoice -JournalPath $JournalPath -InvoiceNumber 1).Status | Should -Be 'Paid'
        (Get-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 1).MatchType | Should -Be 'CustomerInvoice'
    }

    It 'Registers a supplier payment with -SupplierInvoiceNumber' {
        $t = Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 2 -SupplierInvoiceNumber 1 -PassThru
        $t.Status | Should -Be 'Matched'
        (Get-LedgerSupplierInvoice -JournalPath $JournalPath -InvoiceNumber 1).Status | Should -Be 'Paid'
    }

    It 'Refuses to pay a customer invoice with an outgoing transaction' {
        { Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 2 -InvoiceNumber 1 } | Should -Throw '*outgoing*'
    }

    It 'Posts against an account with VAT split out' {
        $t = Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 3 -Account '5410' -VatRate 0.25 -VatAccount '2640' -Description 'Kontorsmaterial' -PassThru
        $t.MatchType | Should -Be 'Manual'
        $e = Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY -VerificationNumber $t.VerificationNumber
        $e.Description | Should -Be 'Kontorsmaterial'
        ($e.Rows | Where-Object Account -eq '5410').Amount | Should -Be 100
        ($e.Rows | Where-Object Account -eq '2640').Amount | Should -Be 25
        ($e.Rows | Where-Object Account -eq '1930').Amount | Should -Be (-125)
    }

    It 'Accepts transactions from the pipeline' {
        Get-LedgerBankTransaction -JournalPath $JournalPath -Status Unmatched | Where-Object Amount -lt -100 | Where-Object Amount -gt -1000 |
            Set-LedgerBankTransaction -JournalPath $JournalPath -Account '6570'
        @(Get-LedgerBankTransaction -JournalPath $JournalPath -Status Matched).TransactionId | Should -Be @(3, 4)
    }

    It 'Links to an existing verification' {
        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY -Date '2024-03-23' -Description 'Överföring' `
            -Rows @(@{ Account = '1910'; Amount = 500 }, @{ Account = '1930'; Amount = -500 })
        $ver = (Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY)[-1].VerificationNumber
        Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 4 -VerificationNumber $ver
        $t = Get-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 4
        $t.MatchType | Should -Be 'Entry'
        $t.VerificationNumber | Should -Be $ver
        $t.FiscalYear | Should -Be $FY
    }

    It 'Refuses to link a verification without a row on the bank account' {
        { Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 4 -VerificationNumber 1 } | Should -Throw '*no row on account 1930*'
    }

    It 'Ignores and resets a transaction' {
        Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 4 -Ignore
        (Get-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 4).Status | Should -Be 'Ignored'
        { Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 4 -Account '6570' } | Should -Throw '*already ignored*'
        Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 4 -Reset
        (Get-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 4).Status | Should -Be 'Unmatched'
    }

    It 'Throws for an unknown transaction' {
        { Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 99 -Ignore } | Should -Throw '*does not exist*'
    }
}

Describe 'Get-LedgerBankReconciliation' {
    BeforeEach {
        $JournalPath = New-BankTestJournal -Root $TestDrive
        Set-Content -Path (Join-Path $JournalPath "$FY\ib.txt") -Value "1930`t50000" -Encoding UTF8
        Add-LedgerBankRule -JournalPath $JournalPath -Pattern 'Bankavgift' -Account '6570'
        $camt = New-CamtFile -Path (Join-Path $TestDrive 'rec.xml') -Opening 50000 -Entries @(
            @{ Date = '2024-03-10'; Amount = -45; Ref = 'R1'; Info = 'Bankavgift' }
            @{ Date = '2024-03-20'; Amount = 1000; Ref = 'R2'; Ustrd = 'Okänd' }
        )
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $camt | Out-Null
        Invoke-LedgerBankMatching -JournalPath $JournalPath | Out-Null
    }

    It 'Reports the ledger and bank balances on the last statement date' {
        $r = Get-LedgerBankReconciliation -JournalPath $JournalPath
        $r.AsOf | Should -Be ([datetime]'2024-03-31')
        $r.FiscalYear | Should -Be $FY
        $r.LedgerBalance | Should -Be 49955
        $r.BankBalance | Should -Be 50955
        $r.Difference | Should -Be (-1000)
        $r.Status | Should -Be 'Differences'
    }

    It 'Explains the difference with unmatched bank transactions' {
        $r = Get-LedgerBankReconciliation -JournalPath $JournalPath
        @($r.UnmatchedBankTransactions).Count | Should -Be 1
        $r.UnmatchedBankAmount | Should -Be 1000
        $r.UnexplainedDifference | Should -Be 0
    }

    It 'Lists ledger entries the bank has not seen' {
        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY -Date '2024-03-30' -Description 'Utbetalning' `
            -Rows @(@{ Account = '6570'; Amount = 200 }, @{ Account = '1930'; Amount = -200 })
        $r = Get-LedgerBankReconciliation -JournalPath $JournalPath
        @($r.UnmatchedLedgerEntries).Count | Should -Be 1
        $r.UnmatchedLedgerAmount | Should -Be (-200)
        $r.UnexplainedDifference | Should -Be 0
    }

    It 'Is reconciled when everything is matched' {
        Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 2 -Account '3010'
        $r = Get-LedgerBankReconciliation -JournalPath $JournalPath
        $r.Difference | Should -Be 0
        $r.Status | Should -Be 'Reconciled'
    }

    It 'Computes the bank balance within a statement period' {
        $r = Get-LedgerBankReconciliation -JournalPath $JournalPath -AsOf '2024-03-15'
        $r.BankBalance | Should -Be 49955
        $r.LedgerBalance | Should -Be 49955
        $r.Status | Should -Be 'Reconciled'
    }

    It 'Uses -BankBalance when given' {
        $r = Get-LedgerBankReconciliation -JournalPath $JournalPath -BankBalance 49955
        $r.BankBalanceSource | Should -Be 'Parameter'
        $r.Difference | Should -Be 0
    }

    It 'Reports NoBankBalance without statements' {
        $other = New-BankTestJournal -Root $TestDrive
        $r = Get-LedgerBankReconciliation -JournalPath $other -AsOf '2024-06-30'
        $r.Status | Should -Be 'NoBankBalance'
        $r.BankBalance | Should -BeNullOrEmpty
    }

    It 'Computes the bank balance correctly across overlapping statements' {
        $csvA = Join-Path $TestDrive 'a.csv'
        @(
            'Datum;Text;Belopp;Saldo'
            '2024-04-02;Insättning A;100,00;51055,00'
            '2024-04-16;Insättning B;10,00;51065,00'
            '2024-04-30;Insättning C;20,00;51085,00'
        ) | Set-Content -Path $csvA -Encoding UTF8
        $csvB = Join-Path $TestDrive 'b.csv'
        @(
            'Datum;Text;Belopp;Saldo'
            '2024-04-16;Insättning B;10,00;51065,00'
            '2024-04-30;Insättning C;20,00;51085,00'
            '2024-05-05;Insättning D;300,00;51385,00'
        ) | Set-Content -Path $csvB -Encoding UTF8
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $csvA | Out-Null
        (Import-LedgerBankStatement -JournalPath $JournalPath -Path $csvB).Imported | Should -Be 1

        (Get-LedgerBankReconciliation -JournalPath $JournalPath -AsOf '2024-05-10').BankBalance | Should -Be 51385
        (Get-LedgerBankReconciliation -JournalPath $JournalPath -AsOf '2024-04-20').BankBalance | Should -Be 51065
    }

    It 'Treats a pair split by the reconciliation date as an open item' {
        Set-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 2 -Account '3010'
        Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FY -Date '2024-03-29' -Description 'Inbetalning' `
            -Rows @(@{ Account = '1930'; Amount = 500 }, @{ Account = '3010'; Amount = -500 })
        $next = New-CamtFile -Path (Join-Path $TestDrive 'apr.xml') -Opening 50955 -From '2024-04-01' -To '2024-04-30' -Id 'STMT-2024-04' -Entries @(
            @{ Date = '2024-04-01'; Amount = 500; Ref = 'R3'; Ustrd = 'Inbetalning' }
        )
        Import-LedgerBankStatement -JournalPath $JournalPath -Path $next | Out-Null
        Invoke-LedgerBankMatching -JournalPath $JournalPath | Out-Null
        (Get-LedgerBankTransaction -JournalPath $JournalPath -TransactionId 3).MatchType | Should -Be 'Entry'

        $march = Get-LedgerBankReconciliation -JournalPath $JournalPath -AsOf '2024-03-31'
        $march.Difference | Should -Be 500
        @($march.UnmatchedLedgerEntries).Count | Should -Be 1
        $march.UnexplainedDifference | Should -Be 0

        $april = Get-LedgerBankReconciliation -JournalPath $JournalPath -AsOf '2024-04-30'
        $april.Status | Should -Be 'Reconciled'
    }
}
