<#
.SYNOPSIS
Exports a payslip to a PDF, Word, Markdown or plain-text document.

.DESCRIPTION
Renders a single payslip (lönebesked) as a printable document and writes it to a
file. The document contains the employer (from the journal), the employee (from
the employee register), the pay period and date, the gross salary, the preliminary
tax withheld, the net pay to be disbursed and the employer's social security
contribution.

The PDF is produced by a dependency-free built-in writer (standard fonts, no
external module). Amounts use Swedish formatting.

.PARAMETER JournalPath
The path to an existing journal directory. If omitted, uses the current journal
set via Set-LedgerCurrentJournal.

.PARAMETER PayslipNumber
The number of the payslip to export.

.PARAMETER Path
Destination path for the document.

.PARAMETER Format
The output format: 'Pdf' (default), 'Word' (.docx), 'Markdown' or 'Text'.

.PARAMETER Force
Overwrite the destination file if it already exists.

.EXAMPLE
Export-LedgerPayslip -JournalPath .\MinFirma.ledger -PayslipNumber 1 -Path .\lonebesked-1.pdf

Writes payslip 1 as a PDF document.

.EXAMPLE
Export-LedgerPayslip -PayslipNumber 1 -Path .\lonebesked-1.docx -Format Word -Force

Writes payslip 1 as a Word document, overwriting any existing file.
#>
function Export-LedgerPayslip {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$JournalPath,

        [Parameter(Mandatory)]
        [int]$PayslipNumber,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Pdf', 'Word', 'Markdown', 'Text')]
        [string]$Format = 'Pdf',

        [Parameter()]
        [switch]$Force
    )
    $JournalPath = Resolve-LedgerJournalPath -JournalPath $JournalPath

    if ((Test-Path $Path) -and -not $Force) {
        throw "Destination file already exists: $Path. Use -Force to overwrite."
    }

    $payslip = Get-LedgerPayslip -JournalPath $JournalPath -PayslipNumber $PayslipNumber
    if (-not $payslip) {
        throw "Payslip $PayslipNumber does not exist."
    }

    $journal = Get-LedgerJournal -Path $JournalPath
    $employee = Get-LedgerEmployee -JournalPath $JournalPath -EmployeeNumber $payslip.EmployeeNumber

    $blocks = @(Build-LedgerPayslipBlock -Payslip $payslip -Journal $journal -Employee $employee)

    switch ($Format) {
        'Word' { ConvertTo-LedgerReportDocx -Block $blocks -Path $Path }
        'Pdf' { ConvertTo-LedgerReportPdf -Block $blocks -Path $Path }
        'Markdown' { ConvertTo-LedgerReportMarkdown -Block $blocks | Set-Content -Path $Path -Encoding UTF8 }
        default { ConvertTo-LedgerReportText -Block $blocks | Set-Content -Path $Path -Encoding UTF8 }
    }
}

function Build-LedgerPayslipBlock {
    <#
    .SYNOPSIS
    Builds the shared report block model for a single payslip document.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject]$Payslip,

        [Parameter(Mandatory)]
        [psobject]$Journal,

        [Parameter()]
        [psobject]$Employee
    )

    $blocks = New-Object System.Collections.Generic.List[object]

    # --- Employer -------------------------------------------------------------
    $blocks.Add(@{ Type = 'Title'; Text = $Journal.Name })
    if ($Journal.OrgNumber) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "Org.nr $($Journal.OrgNumber)" })
    }

    # --- Payslip heading + metadata ------------------------------------------
    $blocks.Add(@{ Type = 'Heading'; Level = 1; Text = "Lönespecifikation $($Payslip.PayslipNumber)" })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Utbetalningsdatum: $($Payslip.PayDate.ToString('yyyy-MM-dd'))" })
    if ($Payslip.PeriodStart -and $Payslip.PeriodEnd) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "Löneperiod: $($Payslip.PeriodStart.ToString('yyyy-MM-dd')) – $($Payslip.PeriodEnd.ToString('yyyy-MM-dd'))" })
    }
    if ($Payslip.Description) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "Avser: $($Payslip.Description)" })
    }

    # --- Employee -------------------------------------------------------------
    $blocks.Add(@{ Type = 'Spacer' })
    $empName = if ($Payslip.PSObject.Properties['EmployeeName'] -and $Payslip.EmployeeName) { $Payslip.EmployeeName } elseif ($Employee) { $Employee.Name } else { '' }
    $blocks.Add(@{ Type = 'Heading'; Level = 2; Text = 'Anställd' })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "$($Payslip.EmployeeNumber)  $empName" })
    if ($Employee -and $Employee.PersonalNumber) {
        $blocks.Add(@{ Type = 'Paragraph'; Text = "Personnr $($Employee.PersonalNumber)" })
    }

    # --- Salary breakdown table ----------------------------------------------
    $blocks.Add(@{ Type = 'Spacer' })
    $rows = @(
        , @('Bruttolön', (Format-LedgerAmount -Value $Payslip.GrossSalary))
        , @('Preliminär skatt', ('-' + (Format-LedgerAmount -Value $Payslip.TaxAmount)))
        , @('Nettolön', (Format-LedgerAmount -Value $Payslip.NetPay))
    )
    $blocks.Add(@{
            Type   = 'Table'
            Header = @('Post', 'Belopp')
            Align  = @('left', 'right')
            Rows   = @($rows)
        })

    $blocks.Add(@{ Type = 'Heading'; Level = 2; Text = "Att utbetala: $(Format-LedgerAmount -Value $Payslip.NetPay) kr" })

    # --- Employer contribution (informational) -------------------------------
    $blocks.Add(@{ Type = 'Spacer' })
    $ratePct = (Format-LedgerAmount -Value ([decimal]$Payslip.EmployerContributionRate * 100)) + ' %'
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Arbetsgivaravgift ($ratePct): $(Format-LedgerAmount -Value $Payslip.EmployerContribution) kr" })
    $blocks.Add(@{ Type = 'Paragraph'; Text = "Total lönekostnad för arbetsgivaren: $(Format-LedgerAmount -Value $Payslip.TotalEmployerCost) kr" })

    $blocks
}
