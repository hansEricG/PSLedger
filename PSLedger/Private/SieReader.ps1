# Tokenizer and record parser for SIE 4 files.
#
# A SIE line is a series of whitespace-separated tokens. The first token on a
# data line is a label starting with '#' (e.g. #VER, #TRANS, #KONTO). Strings
# containing spaces are enclosed in double quotes ("..."). The tokens '{' and
# '}' are structural and may appear standalone or inline (e.g. an object list
# after the account number in a #TRANS row).
#
# This reader returns an array of record objects:
#   [PSCustomObject]@{ Tag = 'VER'; Fields = @('A','1','20240315','Desc'); Transactions = @(...) }
# Header records have an empty Transactions array. Standalone tokens '{' and
# '}' are consumed by the VER parser and are not returned as records.

function ConvertFrom-SieLine {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line
    )

    $tokens = New-Object System.Collections.Generic.List[string]
    $i = 0
    $n = $Line.Length

    while ($i -lt $n) {
        $c = $Line[$i]

        if ([char]::IsWhiteSpace($c)) {
            $i++
            continue
        }

        if ($c -eq '"') {
            $i++
            $sb = New-Object System.Text.StringBuilder
            while ($i -lt $n) {
                $c = $Line[$i]
                if ($c -eq '"') {
                    if ($i + 1 -lt $n -and $Line[$i + 1] -eq '"') {
                        [void]$sb.Append('"')
                        $i += 2
                        continue
                    }
                    $i++
                    break
                }
                [void]$sb.Append($c)
                $i++
            }
            [void]$tokens.Add($sb.ToString())
            continue
        }

        if ($c -eq '{' -or $c -eq '}') {
            [void]$tokens.Add([string]$c)
            $i++
            continue
        }

        $sb = New-Object System.Text.StringBuilder
        while ($i -lt $n) {
            $c = $Line[$i]
            if ([char]::IsWhiteSpace($c) -or $c -eq '{' -or $c -eq '}' -or $c -eq '"') {
                break
            }
            [void]$sb.Append($c)
            $i++
        }
        [void]$tokens.Add($sb.ToString())
    }

    , $tokens.ToArray()
}

function ConvertFrom-SieText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $lines = $Text -split "`r?`n"
    $records = New-Object System.Collections.Generic.List[object]

    $currentVer = $null
    $inVerBlock = $false

    foreach ($line in $lines) {
        $tokens = ConvertFrom-SieLine -Line $line
        if ($tokens.Count -eq 0) { continue }

        $first = $tokens[0]

        if ($first -eq '{') {
            if ($null -ne $currentVer) {
                $inVerBlock = $true
            }
            continue
        }

        if ($first -eq '}') {
            if ($null -ne $currentVer) {
                $records.Add($currentVer) | Out-Null
                $currentVer = $null
                $inVerBlock = $false
            }
            continue
        }

        if (-not $first.StartsWith('#')) {
            continue
        }

        $tag = $first.Substring(1)
        $fields = if ($tokens.Count -gt 1) { $tokens[1..($tokens.Count - 1)] } else { @() }

        if ($tag -eq 'VER') {
            if ($null -ne $currentVer) {
                $records.Add($currentVer) | Out-Null
            }
            $currentVer = [PSCustomObject]@{
                Tag          = 'VER'
                Fields       = $fields
                Transactions = New-Object System.Collections.Generic.List[object]
            }
            continue
        }

        if ($tag -eq 'TRANS' -and $inVerBlock -and $null -ne $currentVer) {
            $transFields = New-Object System.Collections.Generic.List[string]
            $objectFields = New-Object System.Collections.Generic.List[string]
            $skipObject = $false
            for ($k = 0; $k -lt $fields.Count; $k++) {
                $f = $fields[$k]
                if (-not $skipObject -and $f -eq '{') {
                    $skipObject = $true
                    continue
                }
                if ($skipObject) {
                    if ($f -eq '}') { $skipObject = $false }
                    else { [void]$objectFields.Add($f) }
                    continue
                }
                [void]$transFields.Add($f)
            }
            $currentVer.Transactions.Add([PSCustomObject]@{
                Tag     = 'TRANS'
                Fields  = $transFields.ToArray()
                Objects = $objectFields.ToArray()
            }) | Out-Null
            continue
        }

        $records.Add([PSCustomObject]@{
            Tag          = $tag
            Fields       = $fields
            Transactions = @()
        }) | Out-Null
    }

    if ($null -ne $currentVer) {
        $records.Add($currentVer) | Out-Null
    }

    , $records.ToArray()
}
