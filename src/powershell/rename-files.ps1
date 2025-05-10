<#
.SYNOPSIS
    Renames files and folders by replacing a specified string in their names.

.DESCRIPTION
    This script searches for files and folders within a target directory (and optionally subdirectories)
    and replaces a specified part of their names with a new string.
    It supports a simulation mode (WhatIf) to preview changes before applying them.

.PARAMETER OldString
    The string to be replaced in the names of files and folders. This parameter is mandatory.

.PARAMETER NewString
    The string to replace the OldString with. This parameter is mandatory.

.PARAMETER TargetPath
    The path to the directory containing items to rename. Defaults to the current directory ('.').
    The path should be a valid directory path.

.PARAMETER Recurse
    A switch parameter. If present, the script will rename items in subfolders as well.

.PARAMETER WhatIfMode
    A boolean parameter that specifies whether to simulate the renaming operation.
    Defaults to 0 (renaming mode). Set to 1 to perform simulation mode.

.EXAMPLE
    .\Rename-ItemsFresh.ps1 -OldString "Draft" -NewString "Final" -TargetPath "C:\MyDocuments"
    This command simulates renaming items containing "Draft" to "Final" in C:\MyDocuments.

.EXAMPLE
    .\Rename-ItemsFresh.ps1 -OldString "Backup_" -NewString "" -TargetPath "D:\Archive" -Recurse
    This command simulates removing "Backup_" from item names in D:\Archive and its subfolders.

.EXAMPLE
    .\Rename-ItemsFresh.ps1 -OldString "image" -NewString "picture" -WhatIfMode 1
    This command actually renames items containing "image" to "picture" in the current directory.

.NOTES
    Version: 1.0
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')] # Enables -WhatIf and -Confirm common parameters
param(
    [Parameter(Mandatory = $true, HelpMessage = "The string to be replaced in the names.")]
    [string]$OldString,

    [Parameter(Mandatory = $true, HelpMessage = "The string to replace the old string with.")]
    [string]$NewString,

    [Parameter(Mandatory = $false, HelpMessage = "The path to the directory containing items to rename. Defaults to the current directory.")]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "TargetPath '$_' is not a valid directory or does not exist."
        }
        return $true
    })]
    [string]$TargetPath = ".",

    [Parameter(Mandatory = $false, HelpMessage = "Set to true to rename items in subfolders as well. Defaults to false.")]
    [switch]$Recurse,

    [Parameter(Mandatory = $false, HelpMessage = "Set to true to perform in simulation mode. Defaults to false (renaming mode).")]
    [bool]$WhatIfMode = $false # Custom WhatIfMode, distinct from cmdlet's -WhatIf
)

# --- Script Initialization ---
Write-Verbose "Starting script execution."
Write-Verbose "OldString: '$OldString'"
Write-Verbose "NewString: '$NewString'"
Write-Verbose "TargetPath: '$TargetPath'"
Write-Verbose "Recurse: $($Recurse.IsPresent)"
Write-Verbose "Custom WhatIfMode: $WhatIfMode"

# Resolve the target path to an absolute path
try {
    $ResolvedTargetPath = Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop
    Write-Host "Processing items in target directory: '$($ResolvedTargetPath.ProviderPath)'"
}
catch {
    Write-Error "Failed to resolve TargetPath '$TargetPath'. Error: $($_.Exception.Message)"
    exit 1 # Exit if the path cannot be resolved
}

# --- Main Processing Logic ---
try {
    # Determine parameters for Get-ChildItem
    $gciParameters = @{
        LiteralPath = $ResolvedTargetPath.ProviderPath # Use ProviderPath for filesystem operations
        Force       = $true # Include hidden/system items
        ErrorAction = 'Stop' # Stop on errors during item retrieval
    }
    if ($Recurse.IsPresent) {
        $gciParameters.Recurse = $true
    }

    Write-Verbose "Getting items with parameters: $($gciParameters | Out-String)"
    $itemsToProcess = Get-ChildItem @gciParameters

    if ($null -eq $itemsToProcess -or $itemsToProcess.Count -eq 0) {
        Write-Host "No items found in '$($ResolvedTargetPath.ProviderPath)'"
        if ($Recurse.IsPresent) {
            Write-Host "(Searched recursively)"
        }
        Write-Host "Renaming process finished. No changes were made."
        exit 0
    }

    Write-Host "Found $($itemsToProcess.Count) item(s) to potentially process."
    Write-Host "------------------------------------"

    # Process each item
    # To ensure items are renamed from deepest levels first (to avoid path issues if parent folders are renamed),
    # sort items by the length of their FullName in descending order.
    # This is particularly important if renaming folders.
    $sortedItems = $itemsToProcess | Sort-Object -Property @{Expression = {$_.FullName.Length}} -Descending

    foreach ($item in $sortedItems) {
        Write-Verbose "Processing item: '$($item.FullName)'"

        if ($item.Name -match [regex]::Escape($OldString)) {
            $newName = $item.Name -replace [regex]::Escape($OldString), $NewString

            if ($item.Name -eq $newName) {
                Write-Verbose "Item '$($item.Name)' already matches the new name pattern. No rename needed."
                continue # Skip to the next item
            }

            $newFullPath = Join-Path -Path $item.PSParentPath -ChildPath $newName

            # Determine the PathType for Test-Path
            $expectedPathType = "Any" # Default
            if ($item.PSProvider.Name -eq "FileSystem") {
                if ($item.PSIsContainer) {
                    $expectedPathType = "Container"
                } else {
                    $expectedPathType = "Leaf"
                }
            }
            Write-Verbose "Checking for existing item at '$newFullPath' with expected PathType '$expectedPathType'."

            # Check for existing item with the new name
            if (Test-Path -LiteralPath $newFullPath -PathType $expectedPathType) { # Corrected line
                Write-Warning "SKIPPING: An item named '$newName' (type: $expectedPathType) already exists at '$($item.PSParentPath)'. Cannot rename '$($item.Name)'."
                continue
            }

            Write-Host "Plan to rename '$($item.FullName)' to '$newName'"

            # Check with ShouldProcess for -WhatIf/-Confirm common parameters
            # And also check our custom $WhatIfMode
            if ($PSCmdlet.ShouldProcess($item.FullName, "Rename to '$newName'")) {
                # If ShouldProcess is true, it means either -WhatIf was used, or user confirmed with -Confirm, or neither was used (proceed).
                # Now, only perform the rename if our custom $WhatIfMode is $false.
                if (-not $WhatIfMode) {
                    try {
                        Rename-Item -LiteralPath $item.FullName -NewName $newName -ErrorAction Stop
                        Write-Host "SUCCESS: Renamed '$($item.FullName)' to '$newName'" -ForegroundColor Green
                    }
                    catch {
                        Write-Error "Error renaming '$($item.FullName)': $($_.Exception.Message)"
                    }
                } else {
                    # This case handles when $PSCmdlet.ShouldProcess was true (e.g. -Confirm was used and user said Yes)
                    # but our custom $WhatIfMode is still true. We should still only simulate.
                    # Or if only $WhatIfMode is true and -WhatIf common param was NOT used.
                    Write-Host "WHATIF (Custom): Renaming item '$($item.FullName)' to '$newName'"
                }
            } elseif ($WhatIfMode) {
                # This handles the case where $PSCmdlet.ShouldProcess is $false (e.g. -WhatIf common param was used, or user said No to -Confirm)
                # AND our custom $WhatIfMode is true. This is a pure simulation scenario.
                # The $PSCmdlet.ShouldProcess output (e.g. "What if: Performing the operation...") would have already been displayed.
                # We can add an extra custom message if desired, but it might be redundant.
                # For clarity, if PowerShell's -WhatIf was NOT used, but our $WhatIfMode IS true, show custom message.
                if (-not $PSBoundParameters.ContainsKey('WhatIf') -or -not $PSBoundParameters['WhatIf'].IsPresent) {
                     Write-Host "WHATIF (Custom): Renaming item '$($item.FullName)' to '$newName'"
                }
            }
        } else {
            Write-Verbose "Item '$($item.Name)' does not contain the OldString '$OldString'."
        }
    }
}
catch {
    Write-Error "An error occurred during item processing: $($_.Exception.Message)"
    Write-Verbose ($_.Exception | Format-List * -Force | Out-String) # Detailed error for verbose
}

# --- Script Completion ---
Write-Host "------------------------------------"
Write-Host "Renaming process finished."
if ($WhatIfMode -and (-not $PSBoundParameters.ContainsKey('WhatIf') -or -not $PSBoundParameters['WhatIf'].IsPresent)) {
    # Show custom WhatIfMode reminder only if PowerShell's -WhatIf was not the primary driver of simulation.
    Write-Host "REMINDER: Script ran in custom WhatIf mode (simulation). No actual changes were made." -ForegroundColor Yellow
    Write-Host "To perform actual renaming, set '-WhatIfMode `$false'." -ForegroundColor Yellow
}
# PowerShell's -WhatIf common parameter would have already displayed its summary if used.

Write-Verbose "Script execution completed."
