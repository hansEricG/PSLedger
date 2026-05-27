<#
.SYNOPSIS
Imports a chart of accounts into a journal from a template or file.

.DESCRIPTION
Populates the journal's accounts.txt from a built-in chart template or an
external tab-separated file. Built-in templates follow the Swedish BAS structure
in three sizes: BAS-Mini (~30 accounts), BAS-Smaforetag (~70 accounts), and
BAS-Komplett (~250 accounts).

.PARAMETER JournalPath
The path to an existing journal directory.

.PARAMETER Template
The name of a built-in chart template to import (e.g. 'BAS-Mini', 'BAS-Smaforetag',
'BAS-Komplett'). Use -ListAvailable to see available templates.

.PARAMETER Path
The path to an external tab-separated chart file (format: AccountNumber\tAccountName
per line).

.PARAMETER ListAvailable
Lists the names of all built-in chart templates without importing anything.

.PARAMETER Force
If specified, replaces any existing accounts.txt. Without this flag, the command
throws an error if accounts already exist in the journal.

.EXAMPLE
Import-LedgerChart -JournalPath .\MinFirma.ledger -Template 'BAS-Smaforetag'

Imports the small-business chart (~70 accounts) into the journal.

.EXAMPLE
Import-LedgerChart -ListAvailable

Lists available built-in templates: BAS-Mini, BAS-Smaforetag, BAS-Komplett.

.EXAMPLE
Import-LedgerChart -JournalPath .\MinFirma.ledger -Path .\min-kontoplan.tsv -Force

Imports a custom chart file, replacing any existing accounts.
#>
function Import-LedgerChart {
    [CmdletBinding(DefaultParameterSetName = 'Template')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Template')]
        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$JournalPath,

        [Parameter(Mandatory, ParameterSetName = 'Template')]
        [string]$Template,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'List')]
        [switch]$ListAvailable,

        [Parameter(ParameterSetName = 'Template')]
        [Parameter(ParameterSetName = 'File')]
        [switch]$Force
    )

    $TemplateDir = Join-Path $PSScriptRoot '..' 'Data' 'ChartTemplates'

    if ($ListAvailable) {
        $Templates = Get-ChildItem -Path $TemplateDir -Filter '*.txt' -File -ErrorAction SilentlyContinue
        return ($Templates | ForEach-Object { $_.BaseName })
    }

    if (-not (Test-Path $JournalPath -PathType Container)) {
        throw "Journal not found: $JournalPath"
    }

    # Determine source file
    if ($PSCmdlet.ParameterSetName -eq 'Template') {
        $SourceFile = Join-Path $TemplateDir "$Template.txt"
        if (-not (Test-Path $SourceFile)) {
            $Available = (Get-ChildItem -Path $TemplateDir -Filter '*.txt' -File | ForEach-Object { $_.BaseName }) -join ', '
            throw "Template '$Template' not found. Available templates: $Available"
        }
    }
    else {
        $SourceFile = $Path
        if (-not (Test-Path $SourceFile)) {
            throw "Chart file not found: $Path"
        }
    }

    $KontoplanFile = Join-Path $JournalPath 'accounts.txt'

    # Check for existing accounts
    if ((Test-Path $KontoplanFile) -and -not $Force) {
        $Existing = Get-Content $KontoplanFile | Where-Object { $_ -match '^\d+\t' }
        if ($Existing) {
            throw "Journal already has accounts. Use -Force to replace the existing chart."
        }
    }

    # Copy content
    $Content = Get-Content $SourceFile
    $Content | Set-Content -Path $KontoplanFile -Encoding UTF8
}
