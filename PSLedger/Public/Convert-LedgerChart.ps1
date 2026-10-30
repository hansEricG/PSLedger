<#
.SYNOPSIS
Converts accounts from PSLedger's earlier chart templates to standard BAS accounts.

.DESCRIPTION
Earlier versions of PSLedger shipped chart templates (BAS-Komplett and
BAS-Smaforetag) that used some account numbers that do not follow the BAS chart of accounts, for
example 3300 'Försäljning tjänster inom EU' instead of 3308 and 4020 'Inköp varor
och material EU' instead of 4515. Because the VAT report maps accounts to boxes
by their BAS numbers, amounts on these accounts end up in the wrong box of the
VAT return.

Convert-LedgerChart finds these legacy accounts, recognised by both number and
the name the template gave them, and:

- adds the matching standard BAS account to the chart of accounts;
- writes rules to the journal's vat.txt so that amounts already booked on the
  legacy account are reported in the right VAT box (existing vat.txt rules are
  kept and take precedence);
- with -Date, books one transfer verification (omföring) that moves the balance
  of each legacy account at that date to the new account, so the rest of the
  year is booked on the BAS account.

Posted verifications are never changed and the legacy accounts are not removed
or renamed. Accounts whose correct BAS account depends on what was booked on
them ('Försäljning tjänster utrikes', 'Försäljning utrikes', 'Inköp varor och
material utland') are not converted; a warning explains what to decide.

With -Date, the year must be open and the date must be within its range.
Source and target accounts must have the same effective VAT box after the
planned mapping changes. Conflicting overrides cause an error before any files
are changed; resolve the conflict in vat.txt or omit -Date to map accounts only.

One object is returned per legacy account found.

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER FiscalYear
The fiscal year of the transfer verification. Defaults to the current fiscal
year. Only used with -Date.

.PARAMETER Date
Books a transfer verification on this date that moves the balance of each
converted legacy account to its new BAS account. Without -Date no verification
is booked.

.EXAMPLE
Convert-LedgerChart -JournalPath .\Konsultbyrån.ledger -WhatIf

Shows which legacy accounts would be converted without changing anything.

.EXAMPLE
Convert-LedgerChart -JournalPath .\Hantverkarna.ledger -FiscalYear '2025-01_2025-12' -Date '2025-07-01' |
    Format-Table Account, NewAccount, Box, Transferred

Adds the BAS accounts, maps the legacy accounts to the right VAT boxes and moves
their balances on 1 July 2025 to the new accounts, e.g. 3300 to 3308 (box 39).
#>
function Convert-LedgerChart {
    [OutputType([pscustomobject])]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$FiscalYear,

        [Parameter()]
        [datetime]$Date
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

        # Box $null means "not in any box"; Ambiguous accounts are only reported.
        $legacy = @(
            @{ Account = '2660'; Name = 'Moms omvänd skattskyldighet'; NewAccount = '2614'; NewName = 'Utgående moms omvänd skattskyldighet 25%'; Box = 30 }
            @{ Account = '3050'; Name = 'Försäljning tjänster momsfri'; NewAccount = '3004'; NewName = 'Försäljning inom Sverige, momsfri'; Box = 42 }
            @{ Account = '3060'; Name = 'Försäljning tjänster utrikes'; Ambiguous = 'Book EU services on 3308 (box 39) and other services abroad on 3305 (box 40), and map 3060 in vat.txt.' }
            @{ Account = '3100'; Name = 'Försäljning varor inom EU'; NewAccount = '3108'; NewName = 'Försäljning varor till annat EU-land, momsfri'; Box = 35 }
            @{ Account = '3200'; Name = 'Försäljning varor utanför EU'; NewAccount = '3105'; NewName = 'Försäljning varor till land utanför EU'; Box = 36 }
            @{ Account = '3200'; Name = 'Försäljning utrikes'; Ambiguous = 'Use 3105/3108 for goods and 3305/3308 for services (boxes 36/35 and 40/39), and map 3200 in vat.txt.' }
            @{ Account = '3300'; Name = 'Försäljning tjänster inom EU'; NewAccount = '3308'; NewName = 'Försäljning tjänster till annat EU-land'; Box = 39 }
            @{ Account = '3400'; Name = 'Försäljning tjänster utanför EU'; NewAccount = '3305'; NewName = 'Försäljning tjänster till land utanför EU'; Box = 40 }
            @{ Account = '4020'; Name = 'Inköp varor och material EU'; NewAccount = '4515'; NewName = 'Inköp av varor från annat EU-land, 25%'; Box = 20 }
            @{ Account = '4030'; Name = 'Inköp varor och material utland'; Ambiguous = 'Use 4545 for imported goods (box 50) and 4531 for services from outside the EU (box 22), and map 4030 in vat.txt.' }
            @{ Account = '4530'; Name = 'Importkostnader'; NewAccount = '5720'; NewName = 'Tull- och speditionskostnader m.m.'; Box = $null }
            @{ Account = '4531'; Name = 'Tull'; NewAccount = '5720'; NewName = 'Tull- och speditionskostnader m.m.'; Box = $null }
            @{ Account = '4532'; Name = 'Spedition'; NewAccount = '5720'; NewName = 'Tull- och speditionskostnader m.m.'; Box = $null }
        )

        $accounts = @{}
        foreach ($a in @(Get-LedgerAccount -JournalPath $JournalPath)) { $accounts[[string]$a.AccountNumber] = $a.AccountName }

        $found = @($legacy | Where-Object {
                $accounts.ContainsKey($_.Account) -and $accounts[$_.Account].Trim() -eq $_.Name
            })
        if (-not $found) { return }

        $existingRules = @(Read-LedgerVatMapping -JournalPath $JournalPath)
        $defaultRules = @(Get-VatDefaultRule)

        $balances = @{}
        if ($PSBoundParameters.ContainsKey('Date')) {
            $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath
            $yearDir = Join-Path $JournalPath $FiscalYear
            Assert-LedgerEntryDate -YearDir $yearDir -FiscalYear $FiscalYear -Date $Date
            $openingRows = Read-LedgerOpeningBalance -YearDir $yearDir
            foreach ($row in $openingRows) {
                $balances[[string]$row.Account] = [decimal]$balances[[string]$row.Account] + [decimal]$row.Amount
            }
            foreach ($entry in @(Get-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -ToDate $Date)) {
                foreach ($row in $entry.Rows) {
                    $balances[[string]$row.Account] = [decimal]$balances[[string]$row.Account] + [decimal]$row.Amount
                }
            }
        }

        $newRules = [System.Collections.Generic.List[object]]::new()
        $newAccounts = [ordered]@{}
        $transferRows = [System.Collections.Generic.List[hashtable]]::new()
        $results = foreach ($item in $found) {
            if ($item.Ambiguous) {
                Write-Warning "Account $($item.Account) '$($item.Name)' was not converted: $($item.Ambiguous)"
                [PSCustomObject]@{
                    Account = $item.Account; Name = $item.Name; NewAccount = $null; Box = $null
                    VatRule = $false; Transferred = [decimal]0; Status = 'Ambiguous'
                }
                continue
            }

            $number = [long]$item.Account
            $covered = @($existingRules | Where-Object { $number -ge $_.From -and $number -le $_.To }).Count -gt 0
            $default = Resolve-VatBoxRule -Account $item.Account -Rules $defaultRules
            $defaultBox = if ($default) { $default.Box } else { $null }
            $needsRule = -not $covered -and $defaultBox -ne $item.Box
            if ($needsRule) {
                $newRules.Add([PSCustomObject]@{ From = $number; To = $number; Box = $item.Box })
            }

            if (-not $accounts.ContainsKey($item.NewAccount)) {
                $newAccounts[$item.NewAccount] = $item.NewName
            }

            $amount = if ($balances.ContainsKey($item.Account)) { [decimal]$balances[$item.Account] } else { [decimal]0 }
            if ($amount -ne 0) {
                $transferRows.Add(@{ Account = $item.Account; Amount = -$amount })
                $transferRows.Add(@{ Account = $item.NewAccount; Amount = $amount })
            }

            [PSCustomObject]@{
                Account = $item.Account; Name = $item.Name; NewAccount = $item.NewAccount
                Box = $item.Box; VatRule = $needsRule; Transferred = $amount; Status = 'Converted'
            }
        }

        $effectiveRules = @($existingRules) + @($newRules) + @($defaultRules)
        foreach ($item in $results | Where-Object Status -eq 'Converted') {
            $sourceRule = Resolve-VatBoxRule -Account $item.Account -Rules $effectiveRules
            $sourceBox = if ($sourceRule) { $sourceRule.Box } else { $null }
            $item.Box = $sourceBox
            if ($item.Transferred -ne 0) {
                $targetRule = Resolve-VatBoxRule -Account $item.NewAccount -Rules $effectiveRules
                $targetBox = if ($targetRule) { $targetRule.Box } else { $null }
                if ($sourceBox -ne $targetBox) {
                    $sourceLabel = if ($null -eq $sourceBox) { '-' } else { "$sourceBox" }
                    $targetLabel = if ($null -eq $targetBox) { '-' } else { "$targetBox" }
                    throw "Cannot transfer account $($item.Account) (VAT box $sourceLabel) to $($item.NewAccount) (VAT box $targetLabel): conflicting VAT rules. Resolve the conflict in vat.txt or omit -Date."
                }
            }
        }
        if ($transferRows.Count -gt 0) {
            Assert-LedgerEntryAmounts -Rows $transferRows.ToArray()
        }

        if ($PSCmdlet.ShouldProcess($JournalPath, 'Convert legacy template accounts to BAS')) {
            foreach ($number in $newAccounts.Keys) {
                Add-LedgerAccount -JournalPath $JournalPath -AccountNumber $number -AccountName $newAccounts[$number] -Confirm:$false
            }
            if ($newRules.Count -gt 0) {
                Save-LedgerVatMapping -JournalPath $JournalPath -Rules (@($existingRules) + @($newRules))
            }
            if ($transferRows.Count -gt 0) {
                Add-LedgerEntry -JournalPath $JournalPath -FiscalYear $FiscalYear -Date $Date `
                    -Description 'Omföring till BAS-konton' -Rows $transferRows.ToArray() -Confirm:$false
            }
        }

        $results
    }
}
