# Dependency-free minimal PDF writer for the shared report block model (see
# AnnualReportRender.ps1 for the block shapes). Renders the same ordered list of
# layout blocks used by the text/Markdown/Word renderers into a single-file PDF
# 1.4 document built entirely by hand — no external module or assembly beyond the
# .NET base class library, in the same spirit as the hand-rolled .docx package.
#
# Text is written with the 14 standard PDF fonts (Helvetica, Helvetica-Bold and
# Courier), which require no font embedding. Strings are encoded as single bytes
# with ISO-8859-1 (Latin-1); combined with the fonts' WinAnsiEncoding this renders
# Swedish characters (å, ä, ö, Å, Ä, Ö) correctly. Tables are drawn in the
# monospace Courier font so numeric columns line up exactly using the same padding
# logic as the plain-text renderer.

function ConvertTo-LedgerReportPdf {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Block,

        [Parameter(Mandatory)]
        [string]$Path
    )

    # --- Page geometry (A4, points) -------------------------------------------
    $pageW = 595
    $pageH = 842
    $marginX = 56
    $marginTop = 56
    $marginBottom = 56
    $yTop = $pageH - $marginTop

    # Font keys: F1 Helvetica, F2 Helvetica-Bold, F3 Courier (monospace).
    $escape = {
        param([string]$Text)
        if ($null -eq $Text) { return '' }
        $Text.Replace('\', '\\').Replace('(', '\(').Replace(')', '\)') -replace '[\r\n]', ' '
    }

    # --- 1. Flatten blocks into a list of drawable lines ----------------------
    # Each line: @{ Font='F1'; Size=10; Text='...' } or @{ Spacer=$true; Size=6 }
    $lines = New-Object System.Collections.Generic.List[object]
    $addLine = { param($font, $size, $text) $lines.Add(@{ Font = $font; Size = $size; Text = [string]$text }) }
    $addSpacer = { param($size) $lines.Add(@{ Spacer = $true; Size = $size }) }

    # Wrap long proportional-font text at a conservative character count so it
    # does not run off the right margin (invoice paragraphs are short).
    $wrapAt = 95
    $addWrapped = {
        param($font, $size, $text)
        $text = [string]$text
        if ($text.Length -le $wrapAt) { & $addLine $font $size $text; return }
        $words = $text -split ' '
        $current = ''
        foreach ($w in $words) {
            $candidate = if ($current) { "$current $w" } else { $w }
            if ($candidate.Length -gt $wrapAt -and $current) {
                & $addLine $font $size $current
                $current = $w
            }
            else {
                $current = $candidate
            }
        }
        if ($current) { & $addLine $font $size $current }
    }

    foreach ($b in $Block) {
        switch ($b.Type) {
            'Title' { & $addLine 'F2' 18 $b.Text; & $addSpacer 6 }
            'Heading' {
                $size = if ($b.Level -eq 1) { 14 } else { 12 }
                & $addSpacer 2
                & $addLine 'F2' $size $b.Text
                & $addSpacer 2
            }
            'Paragraph' { & $addWrapped 'F1' 10 $b.Text }
            'Spacer' { & $addSpacer 6 }
            'Table' {
                # Reuse the plain-text column padding so Courier lines align.
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
                $buildLine = {
                    param($cells)
                    $line = ''
                    for ($c = 0; $c -lt $cols; $c++) {
                        $align = if ($b.Align) { $b.Align[$c] } else { 'left' }
                        $line += (& $formatCell $cells[$c] $widths[$c] $align)
                        if ($c -lt $cols - 1) { $line += '  ' }
                    }
                    $line
                }
                $headerLine = & $buildLine $b.Header
                & $addLine 'F3' 9 $headerLine
                & $addLine 'F3' 9 ('-' * $headerLine.Length)
                foreach ($row in $b.Rows) { & $addLine 'F3' 9 (& $buildLine $row) }
                & $addSpacer 4
            }
        }
    }

    # --- 2. Paginate: assign each line a page and y position -------------------
    $pages = New-Object System.Collections.Generic.List[object]
    $currentPage = New-Object System.Collections.Generic.List[object]
    $y = $yTop
    $newPage = {
        if ($currentPage.Count -gt 0) { $pages.Add($currentPage) }
        $script:__pdfPage = New-Object System.Collections.Generic.List[object]
        $currentPage = $script:__pdfPage
        $y = $yTop
    }
    foreach ($ln in $lines) {
        $lineHeight = [Math]::Round($ln.Size * 1.4)
        if ($lineHeight -lt 8) { $lineHeight = 8 }
        if (($y - $lineHeight) -lt $marginBottom) {
            if ($currentPage.Count -gt 0) { $pages.Add($currentPage) }
            $currentPage = New-Object System.Collections.Generic.List[object]
            $y = $yTop
        }
        $y = $y - $lineHeight
        if (-not $ln.Spacer) {
            $currentPage.Add(@{ Font = $ln.Font; Size = $ln.Size; Text = $ln.Text; X = $marginX; Y = $y })
        }
    }
    if ($currentPage.Count -gt 0) { $pages.Add($currentPage) }
    if ($pages.Count -eq 0) { $pages.Add((New-Object System.Collections.Generic.List[object])) }

    # --- 3. Build content stream text for each page ---------------------------
    $pageStreams = foreach ($page in $pages) {
        $sb = New-Object System.Text.StringBuilder
        foreach ($item in $page) {
            $t = & $escape $item.Text
            [void]$sb.Append("BT /$($item.Font) $($item.Size) Tf $($item.X) $($item.Y) Td ($t) Tj ET`n")
        }
        $sb.ToString()
    }
    $pageStreams = @($pageStreams)

    # --- 4. Assemble PDF objects with a byte-accurate xref --------------------
    $enc = [System.Text.Encoding]::GetEncoding(28591)   # ISO-8859-1 (Latin-1)
    $bytes = New-Object System.Collections.Generic.List[byte]
    $offsets = @{}
    $append = { param([string]$s) $b = $enc.GetBytes($s); $bytes.AddRange($b) }
    $startObj = { param([int]$n) $offsets[$n] = $bytes.Count; & $append "$n 0 obj`n" }
    $endObj = { & $append "endobj`n" }

    # Object plan:
    #   1 Catalog, 2 Pages, 3 Helvetica, 4 Helvetica-Bold, 5 Courier
    #   per page p (0-based): page obj = 6 + p*2, content obj = 7 + p*2
    $pageCount = $pageStreams.Count
    $pageObjNums = 0..($pageCount - 1) | ForEach-Object { 6 + $_ * 2 }
    $totalObjects = 5 + $pageCount * 2

    & $append "%PDF-1.4`n"
    & $append "%$([char]0xE2)$([char]0xE3)$([char]0xCF)$([char]0xD3)`n"

    # 1: Catalog
    & $startObj 1
    & $append "<< /Type /Catalog /Pages 2 0 R >>`n"
    & $endObj

    # 2: Pages
    & $startObj 2
    $kids = ($pageObjNums | ForEach-Object { "$_ 0 R" }) -join ' '
    & $append "<< /Type /Pages /Kids [$kids] /Count $pageCount >>`n"
    & $endObj

    # 3-5: Fonts
    $fonts = @(
        @{ N = 3; Base = 'Helvetica' }
        @{ N = 4; Base = 'Helvetica-Bold' }
        @{ N = 5; Base = 'Courier' }
    )
    foreach ($f in $fonts) {
        & $startObj $f.N
        & $append "<< /Type /Font /Subtype /Type1 /BaseFont /$($f.Base) /Encoding /WinAnsiEncoding >>`n"
        & $endObj
    }

    # Page + content objects
    for ($p = 0; $p -lt $pageCount; $p++) {
        $pageObj = 6 + $p * 2
        $contentObj = 7 + $p * 2

        & $startObj $pageObj
        & $append ("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageW $pageH] " +
            "/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> " +
            "/Contents $contentObj 0 R >>`n")
        & $endObj

        $stream = $pageStreams[$p]
        $streamLen = $enc.GetBytes($stream).Length
        & $startObj $contentObj
        & $append "<< /Length $streamLen >>`nstream`n"
        & $append $stream
        & $append "endstream`n"
        & $endObj
    }

    # xref
    $xrefOffset = $bytes.Count
    & $append "xref`n"
    & $append "0 $($totalObjects + 1)`n"
    & $append "0000000000 65535 f `n"
    for ($n = 1; $n -le $totalObjects; $n++) {
        $off = ([string]$offsets[$n]).PadLeft(10, '0')
        & $append "$off 00000 n `n"
    }

    # trailer
    & $append "trailer`n"
    & $append "<< /Size $($totalObjects + 1) /Root 1 0 R >>`n"
    & $append "startxref`n"
    & $append "$xrefOffset`n"
    & $append "%%EOF`n"

    # --- Write bytes to disk ---------------------------------------------------
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (Test-Path $fullPath) { Remove-Item $fullPath -Force }
    [System.IO.File]::WriteAllBytes($fullPath, $bytes.ToArray())
}
