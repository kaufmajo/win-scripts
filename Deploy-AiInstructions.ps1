<#
.SYNOPSIS
    Deploy AI coding assistant instructions.

.DESCRIPTION
    Copies samples/ai-instructions.md to the user-level instruction files for
    GitHub Copilot CLI, Claude Code, and OpenAI Codex. Creates missing folders
    and backs up existing files before replacing them. Unchanged files are skipped.

.PARAMETER SourceFile
    Instructions to deploy. Defaults to samples/ai-instructions.md beside this script.

.PARAMETER UserProfilePath
    Profile directory containing .copilot, .claude, and .codex. Defaults to $HOME.
    When omitted, COPILOT_HOME and CODEX_HOME are respected if set.

.EXAMPLE
    .\Deploy-AiInstructions.ps1 -WhatIf

.EXAMPLE
    .\Deploy-AiInstructions.ps1

.NOTES
    Feature                    | GitHub Copilot                         | Claude Code             | OpenAI Codex
    ---------------------------|----------------------------------------|-------------------------|-------------------------
    Main instruction file      | copilot-instructions.md                | CLAUDE.md               | AGENTS.md
    Project-level location     | .github/copilot-instructions.md        | ./CLAUDE.md             | ./AGENTS.md
    Global/user-level location | ~/.copilot/copilot-instructions.md (*) | ~/.claude/CLAUDE.md     | ~/.codex/AGENTS.md
    Subdirectory instructions  | .github/instructions/*.instructions.md | subfolder/CLAUDE.md     | subfolder/AGENTS.md
    Automatically discovered   | Yes                                    | Yes                     | Yes
    Markdown format            | Yes                                    | Yes                     | Yes
    Nested instructions        | Yes                                    | Yes                     | Yes
    Can be committed to Git    | Yes                                    | Yes                     | Yes
    Primary purpose            | Project rules and coding standards     | Project rules/context   | Project rules/context

    (*) Global path applies to GitHub Copilot CLI.
        Support varies between Copilot environments.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [ValidateNotNullOrEmpty()]
    [string]$SourceFile = (Join-Path $PSScriptRoot 'samples/ai-instructions.md'),

    [ValidateNotNullOrEmpty()]
    [string]$UserProfilePath = $HOME
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) {
    throw "Instructions file not found: $SourceFile"
}

$sourcePath = (Resolve-Path -LiteralPath $SourceFile).ProviderPath
$sourceContent = [System.IO.File]::ReadAllText($sourcePath)

$copilotDirectory = Join-Path $UserProfilePath '.copilot'
$claudeDirectory = Join-Path $UserProfilePath '.claude'
$codexDirectory = Join-Path $UserProfilePath '.codex'

if (-not $PSBoundParameters.ContainsKey('UserProfilePath')) {
    if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) {
        $copilotDirectory = $env:COPILOT_HOME
    }
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        $codexDirectory = $env:CODEX_HOME
    }
}

$destinations = @(
    (Join-Path $copilotDirectory 'copilot-instructions.md')
    (Join-Path $claudeDirectory 'CLAUDE.md')
    (Join-Path $codexDirectory 'AGENTS.md')
)

foreach ($destination in $destinations) {
    $exists = Test-Path -LiteralPath $destination
    if ($exists) {
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            throw "Destination is not a file: $destination"
        }
        $destinationPath = (Resolve-Path -LiteralPath $destination).ProviderPath
        if ([System.IO.File]::ReadAllText($destinationPath) -ceq $sourceContent) {
            Write-Output "Already up to date: $destination"
            continue
        }
    }

    if ($PSCmdlet.ShouldProcess($destination, "Deploy instructions from '$sourcePath' (back up existing file)")) {
        $directory = Split-Path -Path $destination -Parent
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null

        if ($exists) {
            $backupPath = "$destination.$(Get-Date -Format 'yyyyMMdd-HHmmss-fffffff').bak"
            Copy-Item -LiteralPath $destination -Destination $backupPath
            Write-Output "Backup created: $backupPath"
        }

        Copy-Item -LiteralPath $sourcePath -Destination $destination -Force
        Write-Output "Deployed: $destination"
    }
}
