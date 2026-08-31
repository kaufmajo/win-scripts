<#
.SYNOPSIS
    This script creates a symbolic link within the Git repository.

.DESCRIPTION
    This script is used to create a symbolic link within the Git repository.
    It requires administrator permissions to create symbolic links.
    The script will search for the Git repository root directory starting from the script's location.
    If a symbolic link already exists at the specified path, the script will prompt the user to confirm its deletion before creating a new symbolic link.

.PARAMETER Path
    The path where the symbolic link will be created.
    - Type: [string]
    - Mandatory: True

.PARAMETER Target
    The target path that the symbolic link will point to.
    - Type: [string]
    - Mandatory: True

.PARAMETER CreateConfirmed
    A switch to automatically confirm the creation of the symbolic link without prompting.
    - Type: [switch]
    - Mandatory: False

.EXAMPLE
    An example of how to run the script.
    PS C:\> .\Set-SymbolicLink.ps1 -Path "RaspberryPi\v2\docs" -Target "..\..\Docs\articles\RaspberryPi\v2\"

.NOTES
    Author: Joachim Kaufmann
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias("LinkPath")]
    [string] $Path,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias("LinkTarget")]
    [string] $Target,

    [switch] $CreateConfirmed
)

#===============================================================
# This script requires administrator permissions to create symbolic links.

function ConvertTo-SingleQuotedPowerShellLiteral {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    return "'" + ($Value -replace "'", "''") + "'"
}

#===============================================================
# Method: Find the Git repository root directory.

function Find-GitRepositoryRoot {
    param (
        [Parameter(Mandatory = $true)]
        [string] $StartPath
    )

    $currentDirectory = Get-Item -LiteralPath $StartPath -Force -ErrorAction Stop

    if (-not $currentDirectory.PSIsContainer) {
        $currentDirectory = $currentDirectory.Directory
    }

    while ($currentDirectory) {
        $gitPath = Join-Path $currentDirectory.FullName ".git"

        if (Test-Path -LiteralPath $gitPath) {
            return $currentDirectory.FullName
        }

        $currentDirectory = $currentDirectory.Parent
    }

    throw "Could not find Git repository root from '$StartPath'."
}

#===============================================================
# Method: Resolve the symbolic link path.

function Resolve-SymbolicLinkPath {
    param (
        [Parameter(Mandatory = $true)]
        [string] $InputPath,

        [Parameter(Mandatory = $true)]
        [string] $BasePath
    )

    if ([System.IO.Path]::IsPathRooted($InputPath)) {
        return [System.IO.Path]::GetFullPath($InputPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $InputPath))
}

#===============================================================
# Method: Test whether the script is running with administrator permissions.

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#===============================================================
# Method: Request administrator permissions before creating a symbolic link.

function Request-AdministratorForSymbolicLinkCreation {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Target
    )

    if (Test-IsAdministrator) {
        return
    }

    $powerShellExecutable = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }
    $scriptCommand = "& $(ConvertTo-SingleQuotedPowerShellLiteral -Value $PSCommandPath) -Path $(ConvertTo-SingleQuotedPowerShellLiteral -Value $Path) -Target $(ConvertTo-SingleQuotedPowerShellLiteral -Value $Target) -CreateConfirmed"
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptCommand))
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedCommand)

    Write-Host "Administrator permissions are required to create symbolic links. Requesting elevation..." -ForegroundColor Yellow

    try {
        $elevatedProcess = Start-Process -FilePath $powerShellExecutable -ArgumentList $arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop

        exit $elevatedProcess.ExitCode
    }
    catch {
        throw "Administrator permission was not granted. The symbolic link was not created."
    }
}

#===============================================================
# Method: Confirm an action with the user.

function Confirm-Action {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $confirmation = Read-Host "$Message Type 'yes' to continue"
    return $confirmation -eq "yes"
}

#===============================================================
# Method: Wait before closing the elevated console window.

function Wait-ForEnterBeforeClosingElevatedWindow {
    if (-not $CreateConfirmed) {
        return
    }

    Write-Host ""
    Write-Host "Press Enter to close this administrator window." -ForegroundColor Yellow
    [void](Read-Host)
}

trap {
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Wait-ForEnterBeforeClosingElevatedWindow
    exit 1
}

#===============================================================
# Method: Remove the existing symbolic link if it exists.

function Remove-ExistingSymbolicLink {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue

    if (-not $item) {
        return $true
    }

    if ($item.LinkType -ne "SymbolicLink") {
        throw "Refusing to remove '$Path' because it is not a symbolic link."
    }

    $currentTarget = if ($item.Target) { $item.Target } else { "<unknown>" }

    Write-Host ""
    Write-Host "Existing symbolic link found:" -ForegroundColor Yellow
    Write-Host "----------------------------------" -ForegroundColor Yellow
    Write-Host "Path   -> $Path"
    Write-Host "Target -> $currentTarget"
    Write-Host ""

    if (-not (Confirm-Action -Message "Delete this symbolic link?")) {
        Write-Host "Skipped deleting symbolic link." -ForegroundColor Red
        return $false
    }

    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    Write-Host "Deleted symbolic link." -ForegroundColor Green
    return $true
}

#===============================================================
# Find the Git repository root directory.

$gitRoot = Find-GitRepositoryRoot -StartPath $PSScriptRoot
Write-Host ""
Write-Host "Git repository:" -ForegroundColor Yellow
Write-Host "----------------------------------" -ForegroundColor Yellow
Write-Host "Root   -> $gitRoot"

#===============================================================
# Initialize the script.

$linkPath = Resolve-SymbolicLinkPath -InputPath $Path -BasePath $gitRoot
$linkTarget = $Target

#===============================================================
# Create the symbolic link.

if (-not (Remove-ExistingSymbolicLink -Path $linkPath)) {
    Wait-ForEnterBeforeClosingElevatedWindow
    exit 0
}

Write-Host ""
Write-Host "Symbolic link can be created:" -ForegroundColor Yellow
Write-Host "----------------------------------" -ForegroundColor Yellow
Write-Host "Path   -> $linkPath"
Write-Host "Target -> $linkTarget"
Write-Host ""

if ((-not $CreateConfirmed) -and (-not (Confirm-Action -Message "Create this symbolic link?"))) {
    Write-Host "Skipped creating symbolic link." -ForegroundColor Red
    Wait-ForEnterBeforeClosingElevatedWindow
    exit 0
}

Request-AdministratorForSymbolicLinkCreation -Path $Path -Target $Target

$parentPath = Split-Path -Path $linkPath -Parent

if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
    throw "The parent folder for the symbolic link does not exist: $parentPath"
}

New-Item -ItemType SymbolicLink -Path $linkPath -Target $linkTarget -ErrorAction Stop
Write-Host "Created symbolic link: $linkPath -> $linkTarget" -ForegroundColor Green
Wait-ForEnterBeforeClosingElevatedWindow
