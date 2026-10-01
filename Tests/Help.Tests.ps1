BeforeDiscovery {
    $PublicDir = Join-Path $PSScriptRoot '..' 'PSLedger' 'Public'
    $Commands = @(Get-ChildItem -Path $PublicDir -Filter '*.ps1' | ForEach-Object { @{ Name = $_.BaseName } })
    $TypedCommands = @($Commands | Where-Object { $_.Name -match '^(Get|New|Test)-' })
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1') -Force
    $script:CommonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters +
        [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
}

Describe 'Comment-based help for <Name>' -ForEach $Commands {
    BeforeAll {
        $script:Help = Get-Help -Name $Name -Full
        $script:Command = Get-Command -Name $Name -Module PSLedger
    }

    It 'Should be exported' {
        $Command | Should -Not -BeNullOrEmpty
    }

    It 'Should have a synopsis' {
        $Help.Synopsis | Should -Not -BeNullOrEmpty
        $Help.Synopsis.Trim() | Should -Not -Be $Name
    }

    It 'Should have a description' {
        ($Help.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
    }

    It 'Should have at least two examples' {
        @($Help.Examples.Example).Count | Should -BeGreaterOrEqual 2
    }

    It 'Should describe every parameter' {
        $documented = @{}
        foreach ($p in @($Help.Parameters.Parameter)) {
            if ($p -and ($p.Description | Out-String).Trim()) { $documented[$p.Name] = $true }
        }
        $missing = @($Command.Parameters.Keys | Where-Object {
                $_ -notin $script:CommonParameters -and -not $documented.ContainsKey($_)
            })
        $missing | Should -BeNullOrEmpty -Because "every parameter of $Name needs a .PARAMETER block"
    }
}

Describe 'OutputType declaration for <Name>' -ForEach $TypedCommands {
    It 'Should declare [OutputType()]' {
        (Get-Command -Name $Name -Module PSLedger).OutputType | Should -Not -BeNullOrEmpty
    }
}
