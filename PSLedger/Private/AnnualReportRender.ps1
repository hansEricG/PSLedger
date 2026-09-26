<#
    Private helpers: render an annual report expressed as an ordered list of layout
    "blocks" into plain text, Markdown or a Word (.docx) document. Keeping a single
    block model means every output format shows the same sections, headings and
    tables. A block is a hashtable with a Type key:

      @{ Type = 'Title';     Text = '...'; Cover = $true }
      @{ Type = 'Heading';   Level = 1|2; Text = '...' }
      @{ Type = 'Paragraph'; Text = '...'; Cover = $true }
      @{ Type = 'Table';     Header = @('Post','2024','2023'); KeepNext = $true (optional);
                             Align  = @('left','right','right');
                             Rows   = @( @('...','..','..'), ... );
                             RowStyles = @('Normal'|'Sum'|'Section', ...) }
      @{ Type = 'Signatures'; Names = @('...', ...) }
      @{ Type = 'Certificate'; Heading = '...'; Text = '...'; Place = '...'; Signer = '...' }
      @{ Type = 'PageBreak' }
      @{ Type = 'Spacer' }

    Cover marks the title-page blocks. RowStyles is optional and parallel to Rows:
    'Sum' rows are summary lines (bold with a rule above) and 'Section' rows are
    captions without amounts.
#>

function Get-LedgerReportRowStyle {
    param ($Block, [int]$Index)
    if ($Block.RowStyles -and $Index -lt $Block.RowStyles.Count -and $Block.RowStyles[$Index]) {
        return [string]$Block.RowStyles[$Index]
    }
    'Normal'
}

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
            'PageBreak' { & $append '' }
            'Signatures' {
                foreach ($name in $b.Names) {
                    & $append ''
                    & $append ('_' * [Math]::Max(30, $name.Length))
                    & $append $name
                }
                & $append ''
            }
            'Certificate' {
                & $append $b.Heading
                & $append ''
                & $append $b.Text
                & $append ''
                & $append $b.Place
                & $append ''
                & $append ''
                & $append ('_' * [Math]::Max(30, ([string]$b.Signer).Length))
                & $append $b.Signer
                & $append ''
            }
            'Table' {
                $cols = $b.Header.Count
                $headerCells = @($b.Header | ForEach-Object { ([string]$_) -replace "`n", ' ' })
                $widths = New-Object 'int[]' $cols
                for ($c = 0; $c -lt $cols; $c++) { $widths[$c] = $headerCells[$c].Length }
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
                $formatLine = {
                    param($cells)
                    $line = ''
                    for ($c = 0; $c -lt $cols; $c++) {
                        $align = if ($b.Align) { $b.Align[$c] } else { 'left' }
                        $line += (& $formatCell $cells[$c] $widths[$c] $align)
                        if ($c -lt $cols - 1) { $line += '  ' }
                    }
                    $line.TrimEnd()
                }
                & $append (& $formatLine $headerCells)
                for ($i = 0; $i -lt $b.Rows.Count; $i++) {
                    $style = Get-LedgerReportRowStyle -Block $b -Index $i
                    if ($style -eq 'Section' -and $i -gt 0) { & $append '' }
                    & $append (& $formatLine $b.Rows[$i])
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
            'PageBreak' { }
            'Signatures' {
                foreach ($name in $b.Names) {
                    & $append '_________________________'
                    & $append ''
                    & $append $name
                    & $append ''
                }
            }
            'Certificate' {
                & $append "### $($b.Heading)"; & $append ''
                & $append $b.Text; & $append ''
                & $append $b.Place; & $append ''
                & $append '_________________________'; & $append ''
                & $append $b.Signer; & $append ''
            }
            'Table' {
                $cols = $b.Header.Count
                & $append ('| ' + (($b.Header | ForEach-Object { ([string]$_) -replace "`n", ' ' }) -join ' | ') + ' |')
                $divider = @()
                for ($c = 0; $c -lt $cols; $c++) {
                    $align = if ($b.Align) { $b.Align[$c] } else { 'left' }
                    $divider += if ($align -eq 'right') { '---:' } else { '---' }
                }
                & $append ('| ' + ($divider -join ' | ') + ' |')
                for ($i = 0; $i -lt $b.Rows.Count; $i++) {
                    $style = Get-LedgerReportRowStyle -Block $b -Index $i
                    $cells = @()
                    foreach ($cell in $b.Rows[$i]) {
                        $text = [string]$cell
                        if ($style -ne 'Normal' -and $text -ne '') { $text = "**$text**" }
                        $cells += $text
                    }
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

    # Text area width of an A4 page with 25 mm margins, in twentieths of a point.
    $textWidth = 9072

    function Escape-Xml {
        param ([string]$Text)
        if ($null -eq $Text) { return '' }
        $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
    }

    function New-Run {
        param ([string]$Text, [switch]$Bold)
        $rPr = if ($Bold) { '<w:rPr><w:b/><w:bCs/></w:rPr>' } else { '' }
        # A newline in the text becomes a line break (used for period column headers).
        $parts = foreach ($line in ($Text -split "`n")) { "<w:t xml:space=""preserve"">$(Escape-Xml $line)</w:t>" }
        "<w:r>$rPr$($parts -join '<w:br/>')</w:r>"
    }

    function New-Paragraph {
        param ([string]$Text, [string]$Style, [switch]$Bold, [string]$Align, [string]$ExtraPPr = '')
        $pPr = ''
        if ($Style) { $pPr += "<w:pStyle w:val=""$Style""/>" }
        $pPr += $ExtraPPr
        if ($Align -eq 'right') { $pPr += '<w:jc w:val="right"/>' }
        elseif ($Align -eq 'center') { $pPr += '<w:jc w:val="center"/>' }
        $pPrXml = if ($pPr) { "<w:pPr>$pPr</w:pPr>" } else { '' }
        $run = if ($null -ne $Text -and $Text -ne '') { New-Run -Text $Text -Bold:$Bold } else { '' }
        "<w:p>$pPrXml$run</w:p>"
    }

    # Column widths: wide label column, a narrow Not column and equal amount columns.
    function Get-ColumnWidths {
        param ($Header)
        $cols = $Header.Count
        $hasNote = $cols -gt 2 -and [string]$Header[1] -eq 'Not'
        $amountCols = if ($hasNote) { $cols - 2 } else { $cols - 1 }
        $amountWidth = if ($cols -ge 5) { 1450 } else { 1600 }
        $noteWidth = if ($hasNote) { 600 } else { 0 }
        $tableWidth = if ($cols -le 2) { 6800 } else { $textWidth }
        $labelWidth = $tableWidth - $noteWidth - ($amountCols * $amountWidth)
        $widths = @($labelWidth)
        if ($hasNote) { $widths += $noteWidth }
        for ($i = 0; $i -lt $amountCols; $i++) { $widths += $amountWidth }
        , $widths
    }

    $border = { param($edge, $size) "<w:$edge w:val=""single"" w:sz=""$size"" w:space=""0"" w:color=""000000""/>" }

    $body = New-Object System.Text.StringBuilder
    $isFirstCover = $true
    foreach ($b in $Block) {
        switch ($b.Type) {
            'Title' {
                if ($b.Cover) {
                    [void]$body.Append((New-Paragraph -Text $b.Text -Style 'Title' -Align 'center' -ExtraPPr '<w:spacing w:before="2400" w:after="480"/>'))
                }
                else {
                    [void]$body.Append((New-Paragraph -Text $b.Text -Style 'Title'))
                }
            }
            'Heading' {
                $style = if ($b.Level -eq 1) { 'Heading1' } else { 'Heading2' }
                [void]$body.Append((New-Paragraph -Text $b.Text -Style $style))
            }
            'Paragraph' {
                if ($b.Cover) {
                    $style = if ($isFirstCover) { 'CoverName' } else { 'CoverText' }
                    $isFirstCover = $false
                    [void]$body.Append((New-Paragraph -Text $b.Text -Style $style -Align 'center'))
                }
                elseif ($b.KeepNext) {
                    [void]$body.Append((New-Paragraph -Text $b.Text -ExtraPPr '<w:keepNext/>'))
                }
                else {
                    [void]$body.Append((New-Paragraph -Text $b.Text))
                }
            }
            'Spacer' { [void]$body.Append('<w:p/>') }
            'PageBreak' { [void]$body.Append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>') }
            'Certificate' {
                # Lower part of the cover page, left-aligned like a form to fill in.
                [void]$body.Append((New-Paragraph -Text $b.Heading -Style 'Heading2' -ExtraPPr '<w:keepNext/><w:spacing w:before="3600" w:after="120"/>'))
                [void]$body.Append((New-Paragraph -Text $b.Text -ExtraPPr '<w:keepNext/>'))
                [void]$body.Append((New-Paragraph -Text $b.Place -ExtraPPr '<w:keepNext/><w:spacing w:before="240"/>'))
                [void]$body.Append('<w:p><w:pPr><w:keepNext/><w:spacing w:before="720" w:after="0"/></w:pPr></w:p>')
                [void]$body.Append((New-Paragraph -Text $b.Signer -ExtraPPr ("<w:pBdr>$(& $border 'top' 6)</w:pBdr><w:ind w:right=""$([int]($textWidth / 2 + 720))""/>")))
            }
            'Signatures' {
                # Two signatures per row in a borderless table with a line to sign on.
                $names = @($b.Names)
                $cellWidth = [int]($textWidth / 2)
                $tbl = New-Object System.Text.StringBuilder
                [void]$tbl.Append("<w:tbl><w:tblPr><w:tblW w:w=""$textWidth"" w:type=""dxa""/><w:tblLayout w:type=""fixed""/></w:tblPr>")
                [void]$tbl.Append("<w:tblGrid><w:gridCol w:w=""$cellWidth""/><w:gridCol w:w=""$cellWidth""/></w:tblGrid>")
                for ($i = 0; $i -lt $names.Count; $i += 2) {
                    [void]$tbl.Append('<w:tr><w:trPr><w:cantSplit/></w:trPr>')
                    foreach ($name in @($names[$i], $(if ($i + 1 -lt $names.Count) { $names[$i + 1] } else { $null }))) {
                        [void]$tbl.Append("<w:tc><w:tcPr><w:tcW w:w=""$cellWidth"" w:type=""dxa""/></w:tcPr>")
                        if ($name) {
                            [void]$tbl.Append('<w:p><w:pPr><w:keepNext/><w:spacing w:before="0" w:after="0" w:line="720" w:lineRule="exact"/></w:pPr></w:p>')
                            [void]$tbl.Append((New-Paragraph -Text $name -ExtraPPr ("<w:pBdr>$(& $border 'top' 6)</w:pBdr><w:ind w:right=""720""/>")))
                        }
                        else {
                            [void]$tbl.Append('<w:p/>')
                        }
                        [void]$tbl.Append('</w:tc>')
                    }
                    [void]$tbl.Append('</w:tr>')
                }
                # Word needs a paragraph after a table; keep it tiny so it cannot spill onto a new page.
                [void]$tbl.Append('</w:tbl><w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/></w:pPr></w:p>')
                [void]$body.Append($tbl.ToString())
            }
            'Table' {
                $cols = $b.Header.Count
                $widths = Get-ColumnWidths -Header $b.Header
                $tableWidth = ($widths | Measure-Object -Sum).Sum
                $tbl = New-Object System.Text.StringBuilder
                [void]$tbl.Append("<w:tbl><w:tblPr><w:tblW w:w=""$tableWidth"" w:type=""dxa""/><w:tblLayout w:type=""fixed""/>")
                [void]$tbl.Append('<w:tblCellMar><w:left w:w="57" w:type="dxa"/><w:right w:w="57" w:type="dxa"/></w:tblCellMar></w:tblPr>')
                [void]$tbl.Append('<w:tblGrid>')
                foreach ($w in $widths) { [void]$tbl.Append("<w:gridCol w:w=""$w""/>") }
                [void]$tbl.Append('</w:tblGrid>')

                $makeRow = {
                    param($cells, [string]$RowStyle, [switch]$HeaderRow, [switch]$KeepNext)
                    $trPr = '<w:cantSplit/>'
                    if ($HeaderRow) { $trPr += '<w:tblHeader/>' }
                    $tr = "<w:tr><w:trPr>$trPr</w:trPr>"
                    for ($c = 0; $c -lt $cols; $c++) {
                        $align = if ($b.Align) { $b.Align[$c] } else { 'left' }
                        $tcBorders = ''
                        if ($HeaderRow) { $tcBorders = "<w:tcBorders>$(& $border 'bottom' 6)</w:tcBorders>" }
                        elseif ($RowStyle -eq 'Sum' -and $c -gt 0 -and [string]$b.Header[$c] -ne 'Not') { $tcBorders = "<w:tcBorders>$(& $border 'top' 4)</w:tcBorders>" }
                        $pPr = '<w:spacing w:before="20" w:after="20"/>'
                        if ($RowStyle -eq 'Section') { $pPr = '<w:spacing w:before="160" w:after="20"/>' }
                        if ($KeepNext) { $pPr = '<w:keepNext/>' + $pPr }
                        $bold = $HeaderRow -or $RowStyle -eq 'Sum' -or $RowStyle -eq 'Section'
                        $para = New-Paragraph -Text ([string]$cells[$c]) -Style 'TableText' -Bold:$bold -Align $align -ExtraPPr $pPr
                        $tr += "<w:tc><w:tcPr><w:tcW w:w=""$($widths[$c])"" w:type=""dxa""/>$tcBorders<w:vAlign w:val=""bottom""/></w:tcPr>$para</w:tc>"
                    }
                    $tr + '</w:tr>'
                }

                [void]$tbl.Append((& $makeRow $b.Header -RowStyle 'Normal' -HeaderRow -KeepNext))
                for ($i = 0; $i -lt $b.Rows.Count; $i++) {
                    $style = Get-LedgerReportRowStyle -Block $b -Index $i
                    # Keep a table on one page where possible.
                    # KeepNext on the block also keeps the last row with what follows.
                    $keep = $b.KeepNext -or $i -lt $b.Rows.Count - 1
                    [void]$tbl.Append((& $makeRow $b.Rows[$i] -RowStyle $style -KeepNext:$keep))
                }
                [void]$tbl.Append('</w:tbl>')
                # A table must be followed by a paragraph in Word; a 6 pt one gives just enough air.
                $spacerKeep = if ($b.KeepNext) { '<w:keepNext/>' } else { '' }
                [void]$tbl.Append("<w:p><w:pPr>$spacerKeep<w:spacing w:before=""0"" w:after=""0"" w:line=""120"" w:lineRule=""exact""/></w:pPr></w:p>")
                [void]$body.Append($tbl.ToString())
            }
        }
    }

    # The footer repeats the company line from the cover page with page numbers.
    $footerLabel = ($Block | Where-Object { $_.Type -eq 'Paragraph' -and $_.Cover } | Select-Object -First 1).Text
    $fld = { param($instr) "<w:r><w:fldChar w:fldCharType=""begin""/></w:r><w:r><w:instrText xml:space=""preserve""> $instr </w:instrText></w:r><w:r><w:fldChar w:fldCharType=""separate""/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType=""end""/></w:r>" }
    $footerXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
        "<w:p><w:pPr><w:pStyle w:val=""Footer""/><w:pBdr>$(& $border 'top' 4)</w:pBdr><w:tabs><w:tab w:val=""right"" w:pos=""$textWidth""/></w:tabs></w:pPr>" +
        "<w:r><w:t xml:space=""preserve"">$(Escape-Xml $footerLabel)</w:t></w:r><w:r><w:tab/><w:t xml:space=""preserve"">Sida </w:t></w:r>" +
        (& $fld 'PAGE') + '<w:r><w:t xml:space="preserve"> (</w:t></w:r>' + (& $fld 'NUMPAGES') + '<w:r><w:t>)</w:t></w:r></w:p></w:ftr>'

    $documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
        '<w:body>' + $body.ToString() +
        '<w:sectPr><w:footerReference w:type="default" r:id="rId2"/><w:pgSz w:w="11906" w:h="16838"/>' +
        '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" w:header="708" w:footer="708" w:gutter="0"/>' +
        '<w:titlePg/></w:sectPr></w:body></w:document>'

    $font = '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>'
    $stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
        "<w:docDefaults><w:rPrDefault><w:rPr>$font<w:sz w:val=""21""/><w:szCs w:val=""21""/><w:lang w:val=""sv-SE""/></w:rPr></w:rPrDefault>" +
        '<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>' +
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>' +
        '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>' +
        '<w:pPr><w:spacing w:after="240"/></w:pPr><w:rPr><w:b/><w:color w:val="1F3864"/><w:sz w:val="56"/><w:szCs w:val="56"/></w:rPr></w:style>' +
        '<w:style w:type="paragraph" w:styleId="CoverName"><w:name w:val="Cover Name"/><w:basedOn w:val="Normal"/><w:qFormat/>' +
        '<w:pPr><w:spacing w:after="120"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style>' +
        '<w:style w:type="paragraph" w:styleId="CoverText"><w:name w:val="Cover Text"/><w:basedOn w:val="Normal"/><w:qFormat/>' +
        '<w:rPr><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:style>' +
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>' +
        '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="160"/><w:outlineLvl w:val="0"/></w:pPr>' +
        '<w:rPr><w:b/><w:color w:val="1F3864"/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style>' +
        '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>' +
        '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr>' +
        '<w:rPr><w:b/><w:sz w:val="23"/><w:szCs w:val="23"/></w:rPr></w:style>' +
        '<w:style w:type="paragraph" w:styleId="TableText"><w:name w:val="Table Text"/><w:basedOn w:val="Normal"/>' +
        '<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>' +
        '<w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/>' +
        '<w:pPr><w:spacing w:after="0"/></w:pPr><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr></w:style>' +
        '</w:styles>'

    $contentTypesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' +
        '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>' +
        '</Types>'

    $relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
        '</Relationships>'

    $documentRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>' +
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
            & $writeEntry 'word/_rels/document.xml.rels' $documentRelsXml
            & $writeEntry 'word/styles.xml' $stylesXml
            & $writeEntry 'word/footer1.xml' $footerXml
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}
