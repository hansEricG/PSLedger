<#
.SYNOPSIS
Returns the accounting principles (redovisnings- och värderingsprinciper) text for
an årsredovisning.

.DESCRIPTION
Returns the standard boilerplate wording used under Tilläggsupplysningar in a small
Swedish company's annual report, prepared according to K2 (BFNAR 2016:10). The text
is read from the built-in template AccountingPrinciples-K2-sv.txt so it can be kept
in one place and reused by the report export.

By default the text is returned as a single string with newlines between the
paragraphs. Use -AsLines to get one string per paragraph.

.PARAMETER AsLines
Return the principles as an array of paragraph strings instead of a single string.

.EXAMPLE
Get-LedgerAccountingPrinciples

Returns the K2 accounting principles as a single block of text.

.EXAMPLE
Get-LedgerAccountingPrinciples -AsLines | ForEach-Object { "- $_" }

Returns each principle paragraph on its own line, prefixed with a dash.
#>
function Get-LedgerAccountingPrinciples {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$AsLines
    )

    $TemplateFile = Join-Path $PSScriptRoot '..' 'Data' 'AnnualReportTemplates' 'AccountingPrinciples-K2-sv.txt'
    if (-not (Test-Path $TemplateFile)) {
        throw "Accounting principles template not found: $TemplateFile"
    }

    $lines = @(Get-Content -Path $TemplateFile -Encoding UTF8 | Where-Object { $_.Trim() -ne '' })

    if ($AsLines) {
        return $lines
    }
    return ($lines -join "`n")
}
