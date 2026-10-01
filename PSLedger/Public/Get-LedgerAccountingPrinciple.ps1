<#
.SYNOPSIS
Returns the accounting principles (redovisnings- och värderingsprinciper) text for
an årsredovisning.

.DESCRIPTION
Returns the standard boilerplate wording used under Tilläggsupplysningar in a small
Swedish company's annual report, prepared according to K2 (BFNAR 2016:10) or K3
(BFNAR 2012:1). The text is read from the built-in template
AccountingPrinciples-<Framework>-sv.txt so it can be kept in one place and reused
by the report export. The K3 text covers the general principles; the report export
adds principles for the significant balance sheet posts the company has.

By default the text is returned as a single string with newlines between the
paragraphs. Use -AsLines to get one string per paragraph.

.PARAMETER Framework
The regelverk: 'K2' (default) or 'K3'.

.PARAMETER AsLines
Return the principles as an array of paragraph strings instead of a single string.

.EXAMPLE
Get-LedgerAccountingPrinciple

Returns the K2 accounting principles as a single block of text.

.EXAMPLE
Get-LedgerAccountingPrinciple -AsLines | ForEach-Object { "- $_" }

Returns each principle paragraph on its own line, prefixed with a dash.

.EXAMPLE
Get-LedgerAccountingPrinciple -Framework K3 -AsLines

Returns the general K3 principles, e.g. for Gävle Konsult AB's first K3 year.
#>
function Get-LedgerAccountingPrinciple {
    [OutputType([string], [string[]])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateSet('K2', 'K3')]
        [string]$Framework = 'K2',

        [Parameter()]
        [switch]$AsLines
    )

    $TemplateFile = Join-Path $PSScriptRoot '..' 'Data' 'AnnualReportTemplates' "AccountingPrinciples-$Framework-sv.txt"
    if (-not (Test-Path $TemplateFile)) {
        throw "Accounting principles template not found: $TemplateFile"
    }

    $lines = @(Get-Content -Path $TemplateFile -Encoding UTF8 | Where-Object { $_.Trim() -ne '' })

    if ($AsLines) {
        return $lines
    }
    return ($lines -join "`n")
}
