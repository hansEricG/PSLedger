<#
    Private helper: note numbering / note register for the annual report.

    In a K2 årsredovisning the notes that are referenced from the resultaträkning
    and balansräkning are numbered in the order they first appear in those
    statements (Not-kolumnen). Unnumbered informational sections such as
    "Redovisningsprinciper" and "Medelantal anställda" are rendered without a
    number and are not part of this register.

    New-LedgerNoteRegister takes an ordered list of note keys (in statement
    appearance order) and returns an ordered hashtable mapping each key to its
    assigned note number (1, 2, 3, ...). Duplicate keys keep their first number.

    Get-LedgerNoteNumber looks up the number for a given key, returning $null when
    the key is not registered (so a statement row can omit the Not reference).
#>

function New-LedgerNoteRegister {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string[]]$NoteKey = @()
    )

    $register = [ordered]@{}
    $number = 1
    foreach ($key in $NoteKey) {
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if (-not $register.Contains($key)) {
            $register[$key] = $number
            $number++
        }
    }
    return $register
}

function Get-LedgerNoteNumber {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $Register,

        [Parameter(Mandatory)]
        [string]$Key
    )

    if ($null -ne $Register -and $Register.Contains($Key)) {
        return $Register[$Key]
    }
    return $null
}
