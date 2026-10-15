<#
.SYNOPSIS
    Deploy personal AI skills for Codex, GitHub Copilot, and Claude Code.

.DESCRIPTION
    Copies complete skill folders from samples/skills to ~/.agents/skills
    (Codex and Copilot) and ~/.claude/skills (Claude Code).
    Changed skills are replaced completely, removing obsolete files and folders.
    Unchanged skills are skipped. Other installed skills are preserved, including
    skills removed entirely from the source collection; uninstall those explicitly.

    Copies are staged before replacement. Previous versions are moved to
    ~/.ai-skill-backups, outside skill discovery folders, and retained for recovery.
    If installing a staged copy fails, the previous version is restored.
    Linked directories and files are rejected to avoid modifying linked targets.

.PARAMETER SourceDirectory
    Collection of skill folders. Defaults to samples/skills beside this script.

.PARAMETER SkillName
    Optional names of skills to deploy. Defaults to all source skills.

.PARAMETER UserProfilePath
    Profile containing .agents and .claude. Defaults to $HOME.
    CLAUDE_CONFIG_DIR is respected when this parameter is omitted.
    Codex and Copilot share ~/.agents/skills independently of CODEX_HOME.

.EXAMPLE
    .\Deploy-AiSkills.ps1 -WhatIf

.EXAMPLE
    .\Deploy-AiSkills.ps1 -SkillName code-mentor

.EXAMPLE
    .\Deploy-AiSkills.ps1 -UserProfilePath C:\Temp\skill-test-profile
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [ValidateNotNullOrEmpty()]
    [string]$SourceDirectory = (Join-Path $PSScriptRoot 'samples/skills'),

    [ValidateNotNullOrEmpty()]
    [string[]]$SkillName,

    [ValidateNotNullOrEmpty()]
    [string]$UserProfilePath = $HOME
)

$ErrorActionPreference = 'Stop'

function Assert-UnlinkedPath {
    param ([string]$Path)

    $currentPath = [IO.Path]::GetFullPath($Path)
    while ($currentPath) {
        $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Linked paths are not supported: $currentPath"
        }
        $currentPath = Split-Path -Path $currentPath -Parent
    }
}

function Get-SkillInventory {
    param ([string]$Path)

    $rootPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    foreach ($item in Get-ChildItem -LiteralPath $rootPath -Force -Recurse | Sort-Object FullName) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked skill content is not supported: $($item.FullName)"
        }
        $relativePath = $item.FullName.Substring($rootPath.Length + 1)
        if ($item.PSIsContainer) {
            "Directory:$relativePath"
        }
        else {
            $stream = [IO.File]::OpenRead($item.FullName)
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try {
                $hash = [BitConverter]::ToString($algorithm.ComputeHash($stream))
                "File:$relativePath`:$hash"
            }
            finally {
                $stream.Dispose()
                $algorithm.Dispose()
            }
        }
    }
}

Assert-UnlinkedPath -Path $SourceDirectory
if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "Skills directory not found: $SourceDirectory"
}
$sourcePath = (Resolve-Path -LiteralPath $SourceDirectory).ProviderPath
$profilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($UserProfilePath)
$claudeDirectory = Join-Path $profilePath '.claude'
if (-not $PSBoundParameters.ContainsKey('UserProfilePath') -and
    -not [string]::IsNullOrWhiteSpace($env:CLAUDE_CONFIG_DIR)) {
    $claudeDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($env:CLAUDE_CONFIG_DIR)
}
$destinationRoots = @(
    (Join-Path $profilePath '.agents/skills')
    (Join-Path $claudeDirectory 'skills')
) | Select-Object -Unique
$backupRoot = Join-Path $profilePath '.ai-skill-backups'

$skills = @(Get-ChildItem -LiteralPath $sourcePath -Directory -Force)
if ($SkillName) {
    foreach ($name in $SkillName) {
        if ($name -notin $skills.Name) { throw "Source skill not found: $name" }
    }
    $skills = @($skills | Where-Object { $_.Name -in $SkillName })
}
if ($skills.Count -eq 0) { throw "No source skills found in: $sourcePath" }

# Validate every source and destination before changing any installed skills.
$deployments = foreach ($skill in $skills) {
    if ($skill.Name -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
        throw "Invalid skill directory name: $($skill.Name)"
    }
    Assert-UnlinkedPath -Path $skill.FullName
    if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md') -PathType Leaf)) {
        throw "Missing SKILL.md in: $($skill.FullName)"
    }
    $sourceInventory = @(Get-SkillInventory -Path $skill.FullName)
    foreach ($root in $destinationRoots) {
        $destination = [IO.Path]::GetFullPath((Join-Path $root $skill.Name))
        foreach ($protectedPath in @($sourcePath, $backupRoot)) {
            $protectedFullPath = [IO.Path]::GetFullPath($protectedPath).TrimEnd('\', '/')
            if ($destination.Equals($protectedFullPath, [StringComparison]::OrdinalIgnoreCase) -or
                $destination.StartsWith($protectedFullPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
                $protectedFullPath.StartsWith($destination + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Deployment and source/backup paths must not overlap: $destination"
            }
        }
        Assert-UnlinkedPath -Path $destination
        $exists = Test-Path -LiteralPath $destination
        if ($exists -and -not (Test-Path -LiteralPath $destination -PathType Container)) {
            throw "Destination is not a directory: $destination"
        }
        $unchanged = $false
        if ($exists) {
            $destinationInventory = @(Get-SkillInventory -Path $destination)
            $unchanged = ($sourceInventory -join "`n") -ceq ($destinationInventory -join "`n")
        }
        [pscustomobject]@{
            Source = $skill.FullName
            Destination = $destination
            Exists = $exists
            Unchanged = $unchanged
            Inventory = $sourceInventory
        }
    }
}
Assert-UnlinkedPath -Path $backupRoot

foreach ($deployment in $deployments) {
    if ($deployment.Unchanged) {
        Write-Output "Already up to date: $($deployment.Destination)"
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($deployment.Destination, 'Replace complete skill folder (retain previous version in .ai-skill-backups)')) {
        continue
    }

    $operationPath = Join-Path $backupRoot ([Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($operationPath) | Out-Null
    $stagedPath = Join-Path $operationPath 'staged'
    $previousPath = Join-Path $operationPath 'previous'
    Copy-Item -LiteralPath $deployment.Source -Destination $stagedPath -Recurse -Force
    $stagedInventory = @(Get-SkillInventory -Path $stagedPath)
    if (($stagedInventory -join "`n") -cne ($deployment.Inventory -join "`n")) {
        throw "Staged copy verification failed; installed skill was preserved. Staging folder: $operationPath"
    }

    $destinationParent = Split-Path -Path $deployment.Destination -Parent
    [IO.Directory]::CreateDirectory($destinationParent) | Out-Null
    if ($deployment.Exists) {
        Move-Item -LiteralPath $deployment.Destination -Destination $previousPath
        Write-Output "Backup created for '$($deployment.Destination)': $previousPath"
    }
    try {
        Move-Item -LiteralPath $stagedPath -Destination $deployment.Destination
    }
    catch {
        if ($deployment.Exists) {
            Move-Item -LiteralPath $previousPath -Destination $deployment.Destination
        }
        throw
    }
    Write-Output "Deployed: $($deployment.Destination)"
}
