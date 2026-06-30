BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'PSLedger' 'PSLedger.psd1'
    Import-Module $ModulePath -Force
    Import-Module TDDUtils -Force
}

Describe 'ExtensionLoader' {
    BeforeAll {
        $CommandName = 'Get-LedgerExtension'
        $Command = Get-Command -Name $CommandName
    }

    Context 'Get-LedgerExtension metadata' {
        It 'Should exist as a command in the module' {
            $Command | Should -Not -BeNullOrEmpty
        }

        It 'Should be an advanced function with CmdletBinding' {
            Test-TDDCmdletBinding $Command | Should -BeTrue
        }

        It 'Should have an optional Source parameter' {
            $Param = $Command.Parameters['Source']
            $Param | Should -Not -BeNullOrEmpty
            $Param.Attributes.Mandatory | Should -Not -Contain $true
        }
    }

    Context 'Loading extensions from a directory' {
        BeforeAll {
            $extDir = Join-Path $TestDrive 'Extensions'
            New-Item -Path $extDir -ItemType Directory -Force | Out-Null

            # Create a valid extension
            @'
function Get-TestGreeting {
    [CmdletBinding()]
    param ()
    "Hello from extension"
}
'@ | Set-Content (Join-Path $extDir 'Greeting.ps1') -Encoding UTF8

            # Create a second extension
            @'
function Get-TestVersion {
    [CmdletBinding()]
    param ()
    "1.0.0"
}
'@ | Set-Content (Join-Path $extDir 'Version.ps1') -Encoding UTF8

            # Reload module with env pointing to test dir
            $env:PSLEDGER_EXTENSIONS = $extDir
            Import-Module $ModulePath -Force
        }

        AfterAll {
            $env:PSLEDGER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        It 'Should load extensions from PSLEDGER_EXTENSIONS path' {
            $extensions = Get-LedgerExtension
            $extensions | Should -Not -BeNullOrEmpty
            $extensions.Count | Should -BeGreaterOrEqual 2
        }

        It 'Should track extension name based on filename' {
            $ext = Get-LedgerExtension | Where-Object { $_.Name -eq 'Greeting' }
            $ext | Should -Not -BeNullOrEmpty
        }

        It 'Should record source as Env' {
            $ext = Get-LedgerExtension | Where-Object { $_.Name -eq 'Greeting' }
            $ext.Source | Should -Be 'Env'
        }

        It 'Should track exported functions' {
            $ext = Get-LedgerExtension | Where-Object { $_.Name -eq 'Greeting' }
            $ext.Functions | Should -Contain 'Get-TestGreeting'
        }

        It 'Should make extension functions callable' {
            $cmd = Get-Command -Name 'Get-TestGreeting' -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            Get-TestGreeting | Should -Be 'Hello from extension'
        }

        It 'Should filter by Source parameter' {
            $envExts = Get-LedgerExtension -Source 'Env'
            $envExts | Should -Not -BeNullOrEmpty
            $userExts = Get-LedgerExtension -Source 'User'
            $userExts.Count | Should -Be 0
        }
    }

    Context 'Extensions have access to module scope (Private helpers)' {
        BeforeAll {
            $extDir = Join-Path $TestDrive 'ScopeExt'
            New-Item -Path $extDir -ItemType Directory -Force | Out-Null

            # Extension that calls a Private function (Resolve-LedgerJournalPath)
            @'
function Test-ScopeAccess {
    [CmdletBinding()]
    param ()
    try {
        $result = Resolve-LedgerJournalPath -JournalPath 'C:\Dummy'
        return ($result -eq 'C:\Dummy')
    } catch {
        return $false
    }
}
'@ | Set-Content (Join-Path $extDir 'ScopeTest.ps1') -Encoding UTF8

            $env:PSLEDGER_EXTENSIONS = $extDir
            Import-Module $ModulePath -Force
        }

        AfterAll {
            $env:PSLEDGER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        It 'Should allow extensions to call Private functions' {
            $cmd = Get-Command -Name 'Test-ScopeAccess' -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            Test-ScopeAccess | Should -BeTrue
        }
    }

    Context 'Error handling for broken extensions' {
        BeforeAll {
            $extDir = Join-Path $TestDrive 'BrokenExt'
            New-Item -Path $extDir -ItemType Directory -Force | Out-Null

            # Broken extension with syntax error
            @'
function Get-BrokenThing {
    this is not valid powershell {{{{
}
'@ | Set-Content (Join-Path $extDir 'Broken.ps1') -Encoding UTF8

            # Valid extension in same directory (sorted after Broken)
            @'
function Get-ValidAfterBroken {
    [CmdletBinding()]
    param ()
    "I still work"
}
'@ | Set-Content (Join-Path $extDir 'Valid.ps1') -Encoding UTF8

            $env:PSLEDGER_EXTENSIONS = $extDir
            Import-Module $ModulePath -Force 3>&1 | Out-Null
        }

        AfterAll {
            $env:PSLEDGER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        It 'Should still load valid extensions after a broken one' {
            $cmd = Get-Command -Name 'Get-ValidAfterBroken' -Module PSLedger -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Module should still be importable' {
            { Get-Command -Module PSLedger } | Should -Not -Throw
        }
    }

    Context 'User-level extensions directory' {
        BeforeAll {
            $userDir = Join-Path $TestDrive 'UserExtensions'
            New-Item -Path $userDir -ItemType Directory -Force | Out-Null

            @'
function Get-UserExt {
    [CmdletBinding()]
    param ()
    "user extension"
}
'@ | Set-Content (Join-Path $userDir 'UserCmd.ps1') -Encoding UTF8

            $env:PSLEDGER_EXTENSIONS = $null
            $env:PSLEDGER_USER_EXTENSIONS = $userDir
            Import-Module $ModulePath -Force
        }

        AfterAll {
            $env:PSLEDGER_USER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        It 'Should load extensions from user extensions path' {
            $ext = Get-LedgerExtension | Where-Object { $_.Name -eq 'UserCmd' }
            $ext | Should -Not -BeNullOrEmpty
            $ext.Source | Should -Be 'User'
        }
    }

    Context 'Per-journal extensions via Set-LedgerCurrentJournal' {
        BeforeAll {
            $journalDir = Join-Path $TestDrive 'TestFirma.ledger'
            New-Item -Path $journalDir -ItemType Directory -Force | Out-Null
            "Name: TestFirma`nOrgNumber: 556677-8899" |
                Set-Content (Join-Path $journalDir 'journal.txt') -Encoding UTF8

            $journalExtDir = Join-Path $journalDir 'Extensions'
            New-Item -Path $journalExtDir -ItemType Directory -Force | Out-Null

            @'
function Get-JournalSpecific {
    [CmdletBinding()]
    param ()
    "journal-specific"
}
'@ | Set-Content (Join-Path $journalExtDir 'JournalCmd.ps1') -Encoding UTF8

            $env:PSLEDGER_EXTENSIONS = $null
            Import-Module $ModulePath -Force
        }

        AfterAll {
            Clear-LedgerCurrentJournal
            if (Test-Path function:global:Get-JournalSpecific) {
                Remove-Item function:global:Get-JournalSpecific -Force
            }
        }

        It 'Should load journal extensions when Set-LedgerCurrentJournal is called' {
            Set-LedgerCurrentJournal -Path (Join-Path $TestDrive 'TestFirma.ledger')
            $ext = Get-LedgerExtension -Source 'Journal'
            $ext | Should -Not -BeNullOrEmpty
            $ext[0].Functions | Should -Contain 'Get-JournalSpecific'
        }

        It 'Should make journal extension functions callable' {
            $cmd = Get-Command -Name 'Get-JournalSpecific' -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            Get-JournalSpecific | Should -Be 'journal-specific'
        }

        It 'Should remove journal extensions when Clear-LedgerCurrentJournal is called' {
            Clear-LedgerCurrentJournal
            Get-LedgerExtension -Source 'Journal' | Should -BeNullOrEmpty
            { Get-JournalSpecific } | Should -Throw
        }
    }
}
