<#
.SYNOPSIS
Adds one or more general supporting documents to a fiscal year.

.DESCRIPTION
Copies (or moves) one or more files into the fiscal year's shared document
directory. Unlike attachments, which belong to a single verification, documents
are scoped to the whole fiscal year and can serve as supporting material
(underlag) for several verifications — for example a bank statement (kontoutdrag)
covering many entries. The directory is created on demand as a subdirectory of
the fiscal year directory, named documents/.

Several files can be added in one call: pass an array of paths, use wildcards, or
pipe in file objects from Get-ChildItem. This makes it easy to add every underlag
in a folder without a dedicated folder parameter — you stay in full control of
filtering (file type, recursion, etc.) via Get-ChildItem.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal.

.PARAMETER FiscalYear
The fiscal year identifier. If omitted, uses the latest fiscal year.
Accepts pipeline input from fiscal year objects.

.PARAMETER Path
The path to one or more files to add. Accepts an array of paths and wildcard
patterns. Also accepts pipeline input by value or by the FullName/PSPath
property, so the output of Get-ChildItem can be piped directly.

.PARAMETER Move
If specified, moves the files instead of copying them.

.PARAMETER Force
If specified, overwrites an existing document with the same file name. By default
a file that would overwrite an existing document is skipped with a non-terminating
error, so the rest of a batch still completes.

.EXAMPLE
Add-LedgerDocument -Path .\kontoutdrag-jan.pdf

Copies kontoutdrag-jan.pdf to the document directory for the latest fiscal year.

.EXAMPLE
Add-LedgerDocument -FiscalYear '2024-01_2024-12' -Path .\kontoutdrag-feb.pdf -Move

Moves kontoutdrag-feb.pdf into the shared document directory for the 2024
fiscal year of Bokforing Nord AB.

.EXAMPLE
Get-ChildItem .\underlag\*.pdf | Add-LedgerDocument

Adds every PDF in the underlag folder to the latest fiscal year of Bokforing
Nord AB by piping the files from Get-ChildItem. Use Get-ChildItem -Recurse or a
filter to control exactly which files are included.

.EXAMPLE
Get-ChildItem .\underlag -File -Recurse | Add-LedgerDocument -Force

Adds every file from the underlag folder and all its subdirectories, overwriting
any existing document with the same name. Without -Force, files whose name
collides with an existing document are skipped with a non-terminating error.
#>
function Add-LedgerDocument {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$FiscalYear,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [string[]]$Path,

        [Parameter()]
        [switch]$Move,

        [Parameter()]
        [switch]$Force
    )

    process {
        $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath
        $FiscalYear = Resolve-LedgerFiscalYear -FiscalYear $FiscalYear -JournalPath $JournalPath

        $YearDir = Join-Path $JournalPath $FiscalYear
        if (-not (Test-Path $YearDir -PathType Container)) {
            throw "Fiscal year not found: $FiscalYear"
        }

        $docDir = Join-Path $YearDir 'documents'

        foreach ($p in $Path) {
            # Resolve each path to one or more leaf files. Literal paths are
            # checked first so names containing wildcard characters still work;
            # otherwise the path is treated as a wildcard pattern.
            if (Test-Path -LiteralPath $p -PathType Leaf) {
                $sourceFiles = @(Get-Item -LiteralPath $p)
            }
            elseif (Test-Path -LiteralPath $p -PathType Container) {
                throw "Path is a directory, not a file: $p. To add all files in a folder, pipe them in, e.g. Get-ChildItem '$p' -File | Add-LedgerDocument"
            }
            else {
                $sourceFiles = @(Get-Item -Path $p -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })
                if (-not $sourceFiles) {
                    throw "File not found: $p"
                }
            }

            foreach ($sourceFile in $sourceFiles) {
                # Create document directory on demand
                if (-not (Test-Path $docDir)) {
                    New-Item -ItemType Directory -Path $docDir -Force | Out-Null
                }

                $destPath = Join-Path $docDir $sourceFile.Name

                if ((Test-Path -LiteralPath $destPath -PathType Leaf) -and -not $Force) {
                    Write-Error "A document named '$($sourceFile.Name)' already exists in fiscal year '$FiscalYear'. Use -Force to overwrite."
                    continue
                }

                if ($Move) {
                    Move-Item -LiteralPath $sourceFile.FullName -Destination $destPath -Force
                }
                else {
                    Copy-Item -LiteralPath $sourceFile.FullName -Destination $destPath -Force
                }

                [PSCustomObject]@{
                    FiscalYear      = $FiscalYear
                    FileName        = $sourceFile.Name
                    DestinationPath = $destPath
                    Size            = $sourceFile.Length
                }
            }
        }
    }
}
