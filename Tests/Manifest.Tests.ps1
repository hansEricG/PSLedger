BeforeAll {
    $script:ModuleDir = Join-Path $PSScriptRoot '..' 'PSLedger'
    $script:ManifestPath = Join-Path $ModuleDir 'PSLedger.psd1'
    $script:Manifest = Import-PowerShellDataFile -Path $ManifestPath
    $script:PublicFunctions = @((Get-ChildItem -Path (Join-Path $ModuleDir 'Public') -Filter '*.ps1').BaseName | Sort-Object)
}

Describe 'Module manifest' {
    It 'Should pass Test-ModuleManifest' {
        { Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Should list the exported functions explicitly' {
        $Manifest.FunctionsToExport | Should -Not -Contain '*'
    }

    It 'Should export exactly the functions in Public' {
        $exported = @($Manifest.FunctionsToExport | Sort-Object)
        Compare-Object -ReferenceObject $PublicFunctions -DifferenceObject $exported | Should -BeNullOrEmpty
    }

    It 'Should export every listed function after import' {
        $module = Import-Module $ManifestPath -Force -PassThru
        $missing = @($Manifest.FunctionsToExport | Where-Object { -not $module.ExportedFunctions.ContainsKey($_) })
        $missing | Should -BeNullOrEmpty
    }

    It 'Should have the metadata the PowerShell Gallery needs' {
        $Manifest.Description | Should -Not -BeNullOrEmpty
        $Manifest.Author | Should -Not -BeNullOrEmpty
        $Manifest.PrivateData.PSData.LicenseUri | Should -Not -BeNullOrEmpty
        $Manifest.PrivateData.PSData.ProjectUri | Should -Not -BeNullOrEmpty
        $Manifest.PrivateData.PSData.Tags | Should -Not -BeNullOrEmpty
    }
}
