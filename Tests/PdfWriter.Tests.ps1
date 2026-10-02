BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    $Module = Import-Module $ModulePath -Force -PassThru
}

Describe 'PDF report writer' {
    BeforeAll {
        function ConvertTo-TestPdfText {
            param ([object[]]$Block)
            $path = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).pdf"
            & $Module { param($b, $p) ConvertTo-LedgerReportPdf -Block $b -Path $p } $Block $path
            [System.Text.Encoding]::Latin1.GetString([System.IO.File]::ReadAllBytes($path))
        }
    }

    It 'Starts a new page at a PageBreak block' {
        $pdf = ConvertTo-TestPdfText -Block @(
            @{ Type = 'Title'; Text = 'Årsredovisning' }
            @{ Type = 'PageBreak' }
            @{ Type = 'Paragraph'; Text = 'Förvaltningsberättelse' }
        )
        $pdf | Should -Match '/Count 2 '
    }

    It 'Ignores a PageBreak at the top of a page' {
        $pdf = ConvertTo-TestPdfText -Block @(
            @{ Type = 'PageBreak' }
            @{ Type = 'Paragraph'; Text = 'Förvaltningsberättelse' }
        )
        $pdf | Should -Match '/Count 1 '
    }

    It 'Writes signature lines and the audit certificate' {
        $pdf = ConvertTo-TestPdfText -Block @(
            @{ Type = 'Signatures'; Names = @('Anna Andersson', 'Bertil Berg') }
            @{ Type = 'Certificate'; Heading = 'Fastställelseintyg'; Text = 'Resultat- och balansräkningen har fastställts.'; Place = 'Stockholm'; Signer = 'Anna Andersson' }
        )
        $pdf | Should -Match '\(Anna Andersson\) Tj'
        $pdf | Should -Match '\(Bertil Berg\) Tj'
        $pdf | Should -Match '\(Fastställelseintyg\) Tj'
        $pdf | Should -Match '\(Stockholm\) Tj'
        $pdf | Should -Match '\(_{30}\) Tj'
    }
}
