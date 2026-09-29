<#
.SYNOPSIS
Adds a bank rule (konteringsregel) for posting recurring bank transactions.

.DESCRIPTION
A bank rule tells Invoke-LedgerBankMatching how to post bank transactions that
are not invoice payments, such as bank fees, interest, tax account transfers
or card subscriptions. A rule matches when its pattern is found in the
transaction's counterparty, text or reference. A pattern containing * or ? is
a wildcard pattern matched against the whole value; any other pattern matches
when the value contains it. Matching is case-insensitive.

The matched transaction is posted against the rule's account: the bank account
receives the transaction amount and the rule account the opposite amount. With
-VatRate the amount is treated as including VAT and split into a net amount on
the rule account and VAT on -VatAccount.

Rules are tried in the order they were added; the first matching rule wins.
Rules are stored in the journal's bank/rules.txt.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER Pattern
The text to look for, e.g. 'Bankavgift' or 'Skatteverket*'.

.PARAMETER Account
The counter account to post against, e.g. '6570' (Bankkostnader).

.PARAMETER Description
Optional. The verification description. Defaults to the transaction's
counterparty, text and reference.

.PARAMETER VatRate
Optional. The VAT rate included in the amount, e.g. 0.25.

.PARAMETER VatAccount
Required with -VatRate. The VAT account, e.g. '2640' (Ingående moms).

.PARAMETER PassThru
If specified, returns the created rule. By default the command produces no
output.

.EXAMPLE
Add-LedgerBankRule -JournalPath .\MinFirma.ledger -Pattern 'Bankavgift' -Account 6570 -Description 'Bankavgift'

Posts every bank fee to 6570 (Bankkostnader).

.EXAMPLE
Add-LedgerBankRule -Pattern 'Skatteverket' -Account 1630 -Description 'Skattekonto'
Add-LedgerBankRule -Pattern 'Telia*' -Account 6212 -Description 'Mobiltelefon' -VatRate 0.25 -VatAccount 2640

Posts transfers to the tax account to 1630 (Skattekonto) and Telia's monthly
bill to 6212 (Mobiltelefon) with 25 % input VAT split out.
#>
function Add-LedgerBankRule {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Account,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateRange(0, 1)]
        [decimal]$VatRate = 0,

        [Parameter()]
        [string]$VatAccount,

        [Parameter()]
        [switch]$PassThru
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath -SchemaCheck Write

    $Pattern = ConvertTo-LedgerBankField $Pattern
    if (-not $Pattern) { throw "Pattern must not be empty." }
    if ($VatRate -gt 0 -and -not $VatAccount) { throw "A VatAccount is required when VatRate is set." }

    $accounts = @(Get-LedgerAccount -JournalPath $JournalPath | ForEach-Object { $_.AccountNumber })
    if ($accounts) {
        foreach ($a in @($Account) + @($VatAccount | Where-Object { $_ })) {
            if ($a -notin $accounts) { throw "Account $a does not exist in chart of accounts." }
        }
    }

    $rules = @(Read-LedgerBankRules -JournalPath $JournalPath)
    if ($rules | Where-Object { $_.Pattern -eq $Pattern }) {
        throw "A bank rule with pattern '$Pattern' already exists."
    }

    $rule = [PSCustomObject]@{
        Priority    = $rules.Count + 1
        Pattern     = $Pattern
        Account     = $Account
        Description = ConvertTo-LedgerBankField $Description
        VatRate     = $VatRate
        VatAccount  = if ($VatRate -gt 0) { $VatAccount } else { '' }
    }

    if (-not $PSCmdlet.ShouldProcess("Bank rule '$Pattern'", "Add (account $Account)")) { return }

    Save-LedgerBankRules -JournalPath $JournalPath -Rules (@($rules) + $rule)
    if ($PassThru) { $rule }
}
