<#
.SYNOPSIS
Collects the stable company information used in an årsredovisning from the journal
metadata.

.DESCRIPTION
Reads the journal and returns a single object with the company details that stay the
same from year to year and are needed to produce an annual report: name, organisation
number, registered office (säte), the object of the business (verksamhetsföremål),
number of shares, share capital and the board members. These are stored as free-form
metadata on the journal (journal.txt) using the conventional keys below and are set
with Set-LedgerJournal -Metadata.

Conventional metadata keys:
  RegisteredOffice      The town where the company has its registered office (säte).
  BusinessObject        A short description of the object of the business.
  NumberOfShares        The number of shares (used for dividend per share).
  ShareCapital          The registered share capital.
  BoardMembers          The board members, separated by semicolons.
  FinancialYearNumber   The company's sequential financial year number, if tracked.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal set
via Set-LedgerCurrentJournal.

.EXAMPLE
Get-LedgerCompanyProfile -JournalPath .\HEG.ledger

Returns the company profile with Name, OrgNumber, RegisteredOffice, BusinessObject,
NumberOfShares, ShareCapital and BoardMembers.

.EXAMPLE
$profile = Get-LedgerCompanyProfile -JournalPath .\HEG.ledger
"Styrelse: {0}" -f ($profile.BoardMembers -join ', ')

Captures the profile and lists the board members.
#>
function Get-LedgerCompanyProfile {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath
    )
    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $Journal = Get-LedgerJournal -Path $JournalPath

        function Get-MetaValue {
            param ([string]$Key)
            if ($Journal.Metadata.Contains($Key) -and $Journal.Metadata[$Key]) {
                return $Journal.Metadata[$Key]
            }
            return $null
        }

        $shares = Get-MetaValue 'NumberOfShares'
        $shareCapital = Get-MetaValue 'ShareCapital'
        $boardRaw = Get-MetaValue 'BoardMembers'
        $board = if ($boardRaw) {
            @($boardRaw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        }
        else {
            @()
        }

        [PSCustomObject]@{
            JournalPath         = $JournalPath
            Name                = $Journal.Name
            OrgNumber           = $Journal.OrgNumber
            CompanyType         = $Journal.CompanyType
            RegisteredOffice    = Get-MetaValue 'RegisteredOffice'
            BusinessObject      = Get-MetaValue 'BusinessObject'
            NumberOfShares      = if ($null -ne $shares) { [int]$shares } else { $null }
            ShareCapital        = if ($null -ne $shareCapital) { [decimal]$shareCapital } else { $null }
            BoardMembers        = $board
            FinancialYearNumber = Get-MetaValue 'FinancialYearNumber'
        }
    }
}
