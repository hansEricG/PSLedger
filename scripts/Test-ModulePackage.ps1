<#
.SYNOPSIS
Builds and smoke-tests the local PSLedger package without publishing it.

.DESCRIPTION
Saves a NuGet package to a temporary local repository, restores it into an
isolated module directory, and tests its manifest, exports and a bookkeeping
flow in a fresh PowerShell process. Only a successful package is copied to
DestinationPath. No Gallery credentials or globally installed PSLedger are used.

.PARAMETER DestinationPath
Directory for the verified .nupkg. An existing package is not overwritten.

.PARAMETER ModulePath
Module source directory. Defaults to this checkout's PSLedger directory.

.EXAMPLE
./scripts/Test-ModulePackage.ps1 -DestinationPath ./artifacts
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$DestinationPath,

    [string]$ModulePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'PSLedger')
)

$ErrorActionPreference = 'Stop'
$ModulePath = (Resolve-Path -LiteralPath $ModulePath).ProviderPath
$DestinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
$version = (Import-PowerShellDataFile (Join-Path $ModulePath 'PSLedger.psd1')).ModuleVersion
$workRoot = [System.IO.Directory]::CreateTempSubdirectory('PSLedger-package-').FullName

try {
    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    # Keep PSResourceGet's package handles in the child so cleanup also works on Windows.
    & $pwsh -NoProfile -NonInteractive -Command {
        param ($ModulePath, $WorkRoot, $Version)
        $ErrorActionPreference = 'Stop'
        Import-Module Microsoft.PowerShell.PSResourceGet -MinimumVersion 1.1.0
        $feed = New-Item -ItemType Directory -Path (Join-Path $WorkRoot 'feed')
        $install = New-Item -ItemType Directory -Path (Join-Path $WorkRoot 'modules')
        $repository = "PSLedger-package-$([guid]::NewGuid().ToString('N'))"
        Register-PSResourceRepository -Name $repository -Uri $feed.FullName -Trusted
        try {
            Publish-PSResource -Path $ModulePath -Repository $repository
            Save-PSResource -Name PSLedger -Version $Version -Repository $repository -Path $install.FullName -Quiet
        }
        finally {
            Unregister-PSResourceRepository -Name $repository
        }

        $ManifestPath = Join-Path $install.FullName 'PSLedger' $Version 'PSLedger.psd1'
        $env:PSLEDGER_EXTENSIONS = ''
        $env:PSLEDGER_USER_EXTENSIONS = Join-Path $WorkRoot 'extensions'
        $manifest = Test-ModuleManifest -Path $ManifestPath
        $module = Import-Module $ManifestPath -Force -PassThru
        $expectedRoot = Join-Path (Split-Path $ManifestPath -Parent) 'PSLedger.psm1'
        if ($module.Path -ne $expectedRoot) { throw "Imported the wrong module: $($module.Path)." }
        $expected = @((Import-PowerShellDataFile $ManifestPath).FunctionsToExport | Sort-Object)
        $actual = @(Get-Command -Module PSLedger | Select-Object -ExpandProperty Name | Sort-Object)
        if (Compare-Object $expected $actual) { throw 'Packaged exports do not match the manifest.' }
        if ($module.Version -ne $manifest.Version) { throw 'Imported version does not match the manifest.' }

        $journal = Join-Path $WorkRoot 'Paketprov.ledger'
        New-LedgerJournal -Path $journal -Name 'Paketprov AB' -OrgNumber '556677-8899'
        Import-LedgerChart -JournalPath $journal -Template 'BAS-Smaforetag'
        New-LedgerFiscalYear -JournalPath $journal -StartDate '2024-01-01' -EndDate '2024-12-31'
        $period = @{ JournalPath = $journal; FiscalYear = '2024-01_2024-12'; FromDate = '2024-01-01'; ToDate = '2024-01-31' }
        Add-LedgerEntry -JournalPath $journal -FiscalYear $period.FiscalYear -Date '2024-01-15' -Description 'Konsulttjanst' -Rows @(
            @{ Account = '1930'; Amount = 1250 }
            @{ Account = '3010'; Amount = -1000 }
            @{ Account = '2610'; Amount = -250 }
        )
        $detail = @(Get-LedgerVatReportDetail @period | Where-Object AccountNumber -EQ '3010')
        if ($detail.Count -ne 1 -or $detail[0].Box -ne 5 -or $detail[0].Amount -ne 1000) {
            throw 'Packaged VAT detail returned an unexpected sales contribution.'
        }
        $xmlPath = Join-Path $WorkRoot 'vat.xml'
        Export-LedgerVatDeclaration @period -Path $xmlPath | Out-Null
        [xml]$xml = Get-Content -LiteralPath $xmlPath -Raw
        if ($xml.eSKDUpload.Moms.ForsMomsEjAnnan -ne '1000' -or $xml.eSKDUpload.Moms.MomsBetala -ne '250') {
            throw 'Packaged VAT declaration returned unexpected amounts.'
        }
        $integrity = Test-LedgerIntegrity -JournalPath $journal -FiscalYear $period.FiscalYear
        if (-not $integrity.IsValid) { throw 'Packaged verification failed its integrity check.' }
    } -args $ModulePath, $workRoot, $version
    if ($LASTEXITCODE -ne 0) { throw "Package smoke check failed (exit code $LASTEXITCODE)." }

    $packages = @(Get-ChildItem -LiteralPath (Join-Path $workRoot 'feed') -Filter '*.nupkg' -File)
    if ($packages.Count -ne 1) { throw "Expected one package, found $($packages.Count)." }
    $null = New-Item -ItemType Directory -Path $DestinationPath -Force
    $packagePath = Join-Path $DestinationPath $packages[0].Name
    if (Test-Path -LiteralPath $packagePath) { throw "Package already exists: $packagePath" }
    Copy-Item -LiteralPath $packages[0].FullName -Destination $packagePath
}
finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}
Get-Item -LiteralPath $packagePath
