<#
    Private helpers: render an annual report expressed as an ordered list of layout
    "blocks" into plain text, Markdown or a Word (.docx) document. Keeping a single
    block model means every output format shows the same sections, headings and
    tables. A block is a hashtable with a Type key:

      @{ Type = 'Title';     Text = '...' }
      @{ Type = 'Heading';   Level = 1|2; Text = '...' }
      @{ Type = 'Paragraph'; Text = '...' }
      @{ Type = 'Table';     Header = @('Post','2024','2023');
                             Align  = @('left','right','right');
                             Rows   = @( @('...','..','..'), ... ) }
      @{ Type = 'Spacer' }
#>

function ConvertTo-LedgerReportText {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Block
    )

    $nl = "`r`n"
    $sb = New-Object System.Text.StringBuilder
    $append = { param($line) [void]$sb.Append($line); [void]$sb.Append($nl) }

    foreach ($b in $Block) {
        switch ($b.Type) {
            'Title' {
                & $append $b.Text
                & $append ('=' * [Math]::Max(4, $b.Text.Length))
                & $append ''
            }
            'Heading' {
                & $append $b.Text
                if ($b.Level -eq 1) { & $append ('-' * [Math]::Max(4, $b.Text.Length)) }
                & $append ''
            }
            'Paragraph' {
                & $append $b.Text
                & $append ''
            }
            'Spacer' { & $append '' }
            'Table' {
                $cols = $b.Header.Count
                $widths = New-Object 'int[]' $cols
                for ($c = 0; $c -lt $cols; $c++) { $widths[$c] = ([string]$b.Header[$c]).Length }
                foreach ($row in $b.Rows) {
                    for ($c = 0; $c -lt $cols; $c++) {
                        $len = ([string]$row[$c]).Length
                        if ($len -gt $widths[$c]) { $widths[$c] = $len }
                    }
                }
                $formatCell = {
                    param($text, $width, $align)
                    $text = [string]$text
                    if ($align -eq 'right') { $text.PadLeft($width) } else { $text.PadRight($width) }
                }
                $headerLine = ''
                for ($c = 0; $c -lt $cols; $c++) {
                    $align = if ($b.Align) { $b.Align[$c] } else { 'left' }
                    $headerLine += (& $formatCell $b.Header[$c] $widths[$c] $align)
                    if ($c -lt $cols - 1) { $headerLine += '  ' }
                }
                & $append $headerLine
                foreach ($row in $b.Rows) {
                    $line = ''
                    for ($c = 0; $c -lt $cols; $c++) {
                        $align = if ($b.Align) { $b.Align[$c] } else { 'left' }
                        $line += (& $formatCell $row[$c] $widths[$c] $align)
                        if ($c -lt $cols - 1) { $line += '  ' }
                    }
                    & $append $line
                }
                & $append ''
            }
        }
    }

    $sb.ToString()
}

function ConvertTo-LedgerReportMarkdown {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Block
    )

    $nl = "`r`n"
    $sb = New-Object System.Text.StringBuilder
    $append = { param($line) [void]$sb.Append($line); [void]$sb.Append($nl) }

    foreach ($b in $Block) {
        switch ($b.Type) {
            'Title' { & $append "# $($b.Text)"; & $append '' }
            'Heading' {
                $prefix = if ($b.Level -eq 1) { '## ' } else { '### ' }
                & $append "$prefix$($b.Text)"; & $append ''
            }
            'Paragraph' { & $append $b.Text; & $append '' }
            'Spacer' { & $append '' }
            'Table' {
                $cols = $b.Header.Count
                & $append ('| ' + ($b.Header -join ' | ') + ' |')
                $divider = @()
                for ($c = 0; $c -lt $cols; $c++) {
                    $align = if ($b.Align) { $b.Align[$c] } else { 'left' }
                    $divider += if ($align -eq 'right') { '---:' } else { '---' }
                }
                & $append ('| ' + ($divider -join ' | ') + ' |')
                foreach ($row in $b.Rows) {
                    $cells = @()
                    foreach ($cell in $row) { $cells += [string]$cell }
                    & $append ('| ' + ($cells -join ' | ') + ' |')
                }
                & $append ''
            }
        }
    }

    $sb.ToString()
}

function ConvertTo-LedgerReportDocx {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Block,

        [Parameter(Mandatory)]
        [string]$Path
    )

    function Escape-Xml {
        param ([string]$Text)
        if ($null -eq $Text) { return '' }
        $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
    }

    # Build a single <w:p> paragraph run. Size is in half-points.
    function New-Paragraph {
        param ([string]$Text, [switch]$Bold, [int]$Size = 20, [string]$Align = 'left')
        $pPr = ''
        if ($Align -eq 'right') { $pPr = '<w:pPr><w:jc w:val="right"/></w:pPr>' }
        $rPr = '<w:rPr>'
        if ($Bold) { $rPr += '<w:b/>' }
        $rPr += "<w:sz w:val=""$Size""/><w:szCs w:val=""$Size""/></w:rPr>"
        $t = Escape-Xml $Text
        "<w:p>$pPr<w:r>$rPr<w:t xml:space=""preserve"">$t</w:t></w:r></w:p>"
    }

    $body = New-Object System.Text.StringBuilder
    foreach ($b in $Block) {
        switch ($b.Type) {
            'Title' { [void]$body.Append((New-Paragraph -Text $b.Text -Bold -Size 32)) }
            'Heading' {
                $size = if ($b.Level -eq 1) { 26 } else { 24 }
                [void]$body.Append((New-Paragraph -Text $b.Text -Bold -Size $size))
            }
            'Paragraph' { [void]$body.Append((New-Paragraph -Text $b.Text -Size 20)) }
            'Spacer' { [void]$body.Append('<w:p/>') }
            'Table' {
                $cols = $b.Header.Count
                $tbl = New-Object System.Text.StringBuilder
                [void]$tbl.Append('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>')
                [void]$tbl.Append('<w:tblBorders>')
                foreach ($edge in 'top', 'left', 'bottom', 'right', 'insideH', 'insideV') {
                    [void]$tbl.Append("<w:$edge w:val=""single"" w:sz=""4"" w:space=""0"" w:color=""auto""/>")
                }
                [void]$tbl.Append('</w:tblBorders></w:tblPr>')

                $makeRow = {
                    param($cells, [switch]$HeaderRow)
                    $tr = '<w:tr>'
                    for ($c = 0; $c -lt $cols; $c++) {
                        $align = if ($b.Align) { $b.Align[$c] } else { 'left' }
                        $para = New-Paragraph -Text ([string]$cells[$c]) -Bold:$HeaderRow -Size 20 -Align $align
                        $tr += "<w:tc><w:tcPr><w:tcW w:w=""0"" w:type=""auto""/></w:tcPr>$para</w:tc>"
                    }
                    $tr + '</w:tr>'
                }

                [void]$tbl.Append((& $makeRow $b.Header -HeaderRow))
                foreach ($row in $b.Rows) { [void]$tbl.Append((& $makeRow $row)) }
                [void]$tbl.Append('</w:tbl>')
                # A table must be followed by a paragraph in Word.
                [void]$tbl.Append('<w:p/>')
                [void]$body.Append($tbl.ToString())
            }
        }
    }

    $documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
        '<w:body>' + $body.ToString() +
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>' +
        '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" w:header="708" w:footer="708" w:gutter="0"/>' +
        '</w:sectPr></w:body></w:document>'

    $contentTypesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
        '</Types>'

    $relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
        '</Relationships>'

    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (Test-Path $fullPath) { Remove-Item $fullPath -Force }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $stream = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Create)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $writeEntry = {
                param($name, $content)
                $entry = $archive.CreateEntry($name)
                $es = $entry.Open()
                try {
                    $bytes = $utf8.GetBytes($content)
                    $es.Write($bytes, 0, $bytes.Length)
                }
                finally { $es.Dispose() }
            }
            & $writeEntry '[Content_Types].xml' $contentTypesXml
            & $writeEntry '_rels/.rels' $relsXml
            & $writeEntry 'word/document.xml' $documentXml
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}
