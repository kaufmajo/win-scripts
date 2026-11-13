#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\Backup.ps1'), [ref]$null, [ref]$errors)
if ($errors) { throw ($errors -join "`n") }
$function = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Invoke-MasterSlaveMirror'
}, $true)
. ([scriptblock]::Create($function.Extent.Text))

function Read-Host { $answer }
function Write-SectionHeader {}
function Write-RobocopyOutput {
    param([Parameter(ValueFromPipeline)]$Line, $SourceRoot, $TargetRoot)
    process {}
}
function Get-DriveState { $state }
function Test-Path { $sourceExists }
function Get-Item {
    [pscustomobject]@{ PSIsContainer = $true; Attributes = [IO.FileAttributes]::Directory }
}
function robocopy {
    $script:copyArguments = $args
    $global:LASTEXITCODE = $copyExitCode
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$options = @{ MasterLetter = 'M'; SlaveLetter = 'S'; MasterLabel = 'master'; SlaveLabel = 'slave' }
$state = 'Ready'
$sourceExists = $true
$copyExitCode = 1
$copyArguments = $null
$answer = ''
Assert-True (Invoke-MasterSlaveMirror @options) 'Declining should succeed.'
Assert-True (-not $copyArguments) 'Default must not run robocopy.'
$answer = 'Y'
Assert-True (Invoke-MasterSlaveMirror @options) 'Confirmed mirror should succeed.'
Assert-True ($copyArguments[0] -eq 'M:\__master' -and
    $copyArguments[1] -eq 'S:\__slave' -and '/MIR' -in $copyArguments -and
    '/XJ' -in $copyArguments) 'Mirror must use selected drives, mirror mode and junction exclusion.'
$copyArguments = $null
$state = 'Missing'
Assert-True (-not (Invoke-MasterSlaveMirror @options)) 'Disconnected drive must fail.'
Assert-True (-not $copyArguments) 'Disconnected drive must not be mirrored.'
$state = 'Ready'
$sourceExists = $false
Assert-True (-not (Invoke-MasterSlaveMirror @options)) 'Missing source must fail.'
Assert-True (-not $copyArguments) 'Missing source must not trigger destination deletion.'
$sourceExists = $true
$copyExitCode = 8
Assert-True (-not (Invoke-MasterSlaveMirror @options)) 'Robocopy error must be reported.'
Write-Host 'Master/slave mirror checks passed (no real drives accessed).'
