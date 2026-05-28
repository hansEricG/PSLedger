# Formats SIE records back to text. Strings containing whitespace, quotes or
# braces are quoted with embedded quotes doubled. Bare numeric/identifier
# tokens are written unquoted. Decimal amounts use invariant culture with two
# decimals.

function Format-SieField {
    [CmdletBinding()]
    param (
        [AllowEmptyString()]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) { return '""' }

    if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) {
        return ([decimal]$Value).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    $s = [string]$Value

    if ($s.Length -eq 0) { return '""' }

    $needsQuote = $false
    foreach ($c in $s.ToCharArray()) {
        if ([char]::IsWhiteSpace($c) -or $c -eq '"' -or $c -eq '{' -or $c -eq '}') {
            $needsQuote = $true
            break
        }
    }

    if (-not $needsQuote) { return $s }

    '"' + $s.Replace('"', '""') + '"'
}

function Format-SieRecord {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Tag,

        [object[]]$Fields = @()
    )

    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add('#' + $Tag)
    foreach ($f in $Fields) {
        [void]$parts.Add((Format-SieField -Value $f))
    }
    [string]::Join(' ', $parts)
}

function Format-SieTransRecord {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Account,

        [Parameter(Mandatory)]
        [decimal]$Amount,

        [string]$Date,

        [string]$Description,

        [string]$ObjectList
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('   #TRANS ')
    [void]$sb.Append((Format-SieField -Value $Account))
    if ($ObjectList) {
        [void]$sb.Append(" {$ObjectList} ")
    }
    else {
        [void]$sb.Append(' {} ')
    }
    [void]$sb.Append((Format-SieField -Value $Amount))
    if ($Date) {
        [void]$sb.Append(' ')
        [void]$sb.Append((Format-SieField -Value $Date))
    }
    if ($Description) {
        if (-not $Date) {
            [void]$sb.Append(' ""')
        }
        [void]$sb.Append(' ')
        [void]$sb.Append((Format-SieField -Value $Description))
    }
    $sb.ToString()
}
