# Module-scoped state for loaded extensions
$script:LoadedExtensions = @()

function Register-LedgerExtension {
    <#
    .SYNOPSIS
    Registers a loaded extension in the tracking list (bookkeeping only).
    #>
    param (
        [string]$Name,
        [string]$Path,
        [string]$Source,
        [string[]]$Functions
    )

    $script:LoadedExtensions += [PSCustomObject]@{
        Name      = $Name
        Path      = $Path
        Source    = $Source
        Functions = $Functions
    }
}

function Import-LedgerExtensionRuntime {
    <#
    .SYNOPSIS
    Loads a single extension at runtime (from Set-LedgerJournal).
    Creates global functions so they are immediately callable.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('Env', 'User', 'Journal')]
        [string]$Source
    )

    if (-not (Test-Path $Path -PathType Leaf)) {
        Write-Warning "PSLedger extension not found: $Path"
        return
    }

    $functionsBefore = (Get-ChildItem function:).Name

    try {
        # Dot-source in current scope (within this function)
        . $Path
    }
    catch {
        Write-Warning "PSLedger extension failed to load: $Path — $($_.Exception.Message)"
        return
    }

    $functionsAfter = (Get-ChildItem function:).Name
    $newFunctions = @($functionsAfter | Where-Object { $_ -notin $functionsBefore })

    # Promote new functions to global scope so they persist after this function returns
    foreach ($funcName in $newFunctions) {
        $funcDef = Get-Item "function:$funcName"
        Set-Item "function:global:$funcName" -Value $funcDef.ScriptBlock
    }
    $newFunctions = @($functionsAfter | Where-Object { $_ -notin $functionsBefore })

    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    Register-LedgerExtension -Name $name -Path $Path -Source $Source -Functions $newFunctions
}

function Remove-LedgerJournalExtensions {
    <#
    .SYNOPSIS
    Removes all extensions that were loaded from a journal source.
    #>
    [CmdletBinding()]
    param ()

    $journalExtensions = @($script:LoadedExtensions | Where-Object { $_.Source -eq 'Journal' })

    foreach ($ext in $journalExtensions) {
        foreach ($funcName in $ext.Functions) {
            if (Test-Path "function:global:$funcName") {
                Remove-Item "function:global:$funcName" -Force
            }
            if (Test-Path "function:$funcName") {
                Remove-Item "function:$funcName" -Force
            }
        }
    }

    $script:LoadedExtensions = @($script:LoadedExtensions | Where-Object { $_.Source -ne 'Journal' })
}
