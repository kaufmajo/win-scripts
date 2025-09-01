<#
    ---------------------------------------------------------------

    https://superuser.com/questions/748069/how-do-i-compare-two-folders-recursively-and-generate-a-list-of-files-and-folder

    ---------------------------------------------------------------

    https://stackoverflow.com/questions/6584402/after-robocopy-the-copied-directory-and-files-are-not-visible-on-the-destinatio

    Just ran into this issue myself, so it may be a late response and you may have worked it out already, but for those stumbling on this page here's my solution...

    The problem is that for whatever reason, Robocopy has marked the directory with the System Attribute of hidden, making it invisible in the directory structure, unless you enable the viewing of system files.

    The easiest way to resolve this is through the command line.

        Open a command prompt and change the focus to the drive in question (e.g. x:)
        Then use the command dir /A:S to display all directories with the System attribute set.
        Locate your directory name and then enter the command ATTRIB -R -S x:\MyBackup /S /D where x:\ is the drive letter and MyBackup is your directory name.
        The /S re-curses subfolders and /D processes folders as well.

    This should clear the Read Only and System attributes on all directories and files, allowing you to view the directory normally.

    ---------------------------------------------------------------
#>

#---------------------------------------------------------------
# Params

param(
    [string]$ConfigFile = "",
    [switch]$IncludeAllRobocopyJobs = $false,
    [switch]$IncludeDotfileBackup = $false,
    [switch]$IncludeHyperVExport = $false,
    [switch]$IncludeWslExport = $false,
    [switch]$SkipTimeline = $false
)

#---------------------------------------------------------------
# Error handling and start

$Error.Clear();
$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Stop"

#---------------------------------------------------------------
# Header

Write-Host ">>> Script started at $(Get-Date) <<<"
Write-Host
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host "|               Backup script                   |            " -ForegroundColor Cyan
Write-Host "|               Version 2.0                     |            " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host

#---------------------------------------------------------------
# Config

# Get current base directory
# Prefer PSScriptRoot when available; fall back to MyInvocation
$baseDirectory = $PSScriptRoot

# Resolve config path: use provided -ConfigFile if given; else default
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $configPath = Join-Path -Path $baseDirectory -ChildPath 'config\backup.xml'
}
else {
    try {
        # Allow relative or absolute paths for -ConfigFile
        $configPath = (Resolve-Path -LiteralPath $ConfigFile -ErrorAction Stop).Path
    }
    catch {
        throw "The provided -ConfigFile path '$ConfigFile' could not be resolved. $($_.Exception.Message)"
    }
}

# Validate and load the config XML
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Config file not found at: $configPath"
}

Write-Host "Using config file: $configPath" -ForegroundColor Cyan

# Get config values
try {
    [xml]$backupConfig = Get-Content -LiteralPath $configPath -ErrorAction Stop
}
catch {
    throw "Failed to load config file '$configPath'. $($_.Exception.Message)"
}

#---------------------------------------------------------------
# Dot Source required Function Libraries

. $baseDirectory\library\function\Function_Get-XmlNode.ps1

#---------------------------------------------------------------
# Init

$masterDriveLetter = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/letter").InnerText
$slaveDriveLetter = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/letter").InnerText
$masterDriveDesc = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/description").InnerText
$slaveDriveDesc = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/description").InnerText
$masterDriveBitlocker = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/bitlocker").InnerText
$slaveDriveBitlocker = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/bitlocker").InnerText
$rootfolder = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/rootfolder").InnerText
$timelineRoot = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/timelineFolder").InnerText
$wslExportPath = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/wslExportFolder").InnerText
$hyperVExportPath = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/hyperVExportFolder").InnerText
$hyperVPoolPath = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/hyperVPoolFolder").InnerText

# Backup excludes
$backupExcludes = [System.Collections.Generic.List[string]]@('$RECYCLE.BIN', 'System Volume Information', $timelineRoot, $hyperVPoolPath)
$timelineExcludes = [System.Collections.Generic.List[string]]@('$RECYCLE.BIN', 'System Volume Information', $timelineRoot, $hyperVPoolPath, $hyperVExportPath, $wslExportPath)

# Reset Error Action Preference
$ErrorActionPreference = $oldErrorActionPreference

#---------------------------------------------------------------
# Check current principal mode

$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not ($isAdmin)) {

    Write-Host ""
    Write-Host "If script must run with administrator privileges: " -ForegroundColor Yellow
    Write-Host "sudo pwsh -executionpolicy remotesigned -File $($MyInvocation.MyCommand.Definition)" -ForegroundColor Yellow  # https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.invocationinfo?view=powershellsdk-7.4.0
    Write-Host ""
}

Write-Host ""

#---------------------------------------------------------------
# Unlock drive

if (($masterDriveLetter -ne "" -and $masterDriveBitlocker -eq "true") -or ($slaveDriveLetter -ne "" -and $slaveDriveBitlocker -eq "true")) {

    Write-Host ""
    Write-Host "Unlock Master Drive" -ForegroundColor Cyan
    Write-Host "---"
    Write-Host ""

    $Arguments = @('-File', (Get-XmlNode -Xml $backupConfig -XPath "settings/script/unlockMasterDrive").InnerText)

    if ($masterDriveLetter -ne "" -and $masterDriveBitlocker -eq "true") {
        $Arguments += "-MasterDriveLetter"
        $Arguments += $masterDriveLetter
        $Arguments += "-MasterDriveEnvvar"
        $Arguments += $(Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/envvar").InnerText
    }

    if ($slaveDriveLetter -ne "" -and $slaveDriveBitlocker -eq "true") {
        $Arguments += "-SlaveDriveLetter"
        $Arguments += $slaveDriveLetter
        $Arguments += "-SlaveDriveEnvvar"
        $Arguments += $(Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/envvar").InnerText
    }

    $process = Start-Process pwsh `
        -ArgumentList $Arguments `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Unlock master drive script process failed with exit code $($process.ExitCode)"
    }
}

#---------------------------------------------------------------
# Show drives overview

$master = if ($masterDriveLetter) { Get-PSDrive -Name $masterDriveLetter -ErrorAction SilentlyContinue } else { $false }
$slave = if ($slaveDriveLetter) { Get-PSDrive -Name $slaveDriveLetter -ErrorAction SilentlyContinue } else { $false }
$drives = Get-PSDrive -PSProvider FileSystem

if ($drives) {
        
    Write-Host "Letter Description Selected"
    Write-Host "______ ___________ ________"
        
    $drives | ForEach-Object {

        Write-Host ("{0}" -f $_.Name).PadRight(7) -NoNewline
        Write-Host ("{0}" -f $_.Description).PadRight(12) -NoNewline
        if ($master -and $_.Name -eq $master.Name -and $_.Description -eq $masterDriveDesc) { Write-Host "Master" -NoNewline -ForegroundColor Green } else { Write-Host "" -NoNewline }
        if ($slave -and $_.Name -eq $slave.Name -and $_.Description -eq $slaveDriveDesc) { Write-Host "Slave" -ForegroundColor Green } else { Write-Host "" }
    }    
}

Write-Host ""

#---------------------------------------------------------------
# Pick master drive

if (-not $master -or $masterDriveDesc -ne $master.Description) {
    
    Write-Host "Enter " -NoNewline
    Write-Host "master " -NoNewline -ForegroundColor Yellow
    Write-Host "drive letter: " -NoNewline
    $masterDriveLetter = Read-Host

    $master = if ($masterDriveLetter) { Get-PSDrive -Name $masterDriveLetter -ErrorAction SilentlyContinue } else { $false }
}

#---------------------------------------------------------------
# Pick slave drive

if (-not $slave -or $slaveDriveDesc -ne $slave.Description) {

    Write-Host "Enter " -NoNewline
    Write-Host "slave " -NoNewline -ForegroundColor Yellow
    Write-Host "drive letter: " -NoNewline
    $slaveDriveLetter = Read-Host

    $slave = if ($slaveDriveLetter) { Get-PSDrive -Name $slaveDriveLetter -ErrorAction SilentlyContinue } else { $false }
}

#---------------------------------------------------------------
# Check and set target2

if ($slave -and $slaveDriveDesc -eq $slave.Description -and (Test-Path -Path "$($slaveDriveLetter):")) {
    $target2 = "$($slaveDriveLetter):\$($env:COMPUTERNAME)\$($env:UserName)\"
    $target3 = $target2
}
else {
    Write-Host "No valid slave drive given, or drive is locked." -ForegroundColor Red
    $slave = ""
}

#---------------------------------------------------------------
# Check and set target1

if ($master -and $masterDriveDesc -eq $master.Description -and (Test-Path -Path "$($masterDriveLetter):")) {
    $target1 = "$($masterDriveLetter):\$($env:COMPUTERNAME)\$($env:UserName)\"
    $target3 = $target1
}
else {
    Write-Host "No valid master drive given, or drive is locked." -ForegroundColor Red
    $master = ""
}

#---------------------------------------------------------------

Write-Host ""

if (-not ($master) -and -not ($slave)) { exit }

#---------------------------------------------------------------
#
#
# Start processing
#
#
#---------------------------------------------------------------

if ( -not (Test-Path -Path $rootfolder) ) {
    throw "Root path not found: $rootfolder"
}

#---------------------------------------------------------------
# HyperV Export

if ($IncludeHyperVExport) { 

    if ( -not (Test-Path -Path $hyperVExportPath) ) {
        throw "HyperV Export path not found: $hyperVExportPath"
    }

    Write-Host ""
    Write-Host "HyperV Export for $($prop.name)" -ForegroundColor Cyan
    Write-Host "---"

    foreach ($prop in $backupConfig.settings.hyperVExport.job) {

        if ($prop.name -eq "") { continue }

        Write-Host "... $($prop.name)"

        Remove-Item $hyperVExportPath\* -Recurse

        Export-VM -Name $prop.name -Path $hyperVExportPath
    }
}

#---------------------------------------------------------------
# Wsl Export

if ($IncludeWslExport) { 

    if ( -not (Test-Path -Path $wslExportPath) ) {
        throw "WSL Export path not found: $wslExportPath"
    }

    Write-Host ""
    Write-Host "WSL Export for $($prop.name)" -ForegroundColor Cyan
    Write-Host "---"

    foreach ($prop in $backupConfig.settings.wslExport.job) {

        if ($prop.name -eq "") { continue }

        Write-Host "... $($prop.name)"

        Remove-Item $wslExportPath\* -Recurse

        wsl --export $prop.name $wslExportPath\debian.tar
    }
}

#---------------------------------------------------------------
# Backup dotfiles

if ($IncludeDotfileBackup) {

    Write-Host ""
    Write-Host "Dotfile Script" -ForegroundColor Cyan
    Write-Host "---"

    $dotfileScript = (Get-XmlNode -Xml $backupConfig -XPath "settings/script/dotfile").InnerText

    $process = Start-Process pwsh -ArgumentList "$dotfileScript" -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Dotfile script process failed with exit code $($process.ExitCode)"
    }
}

#---------------------------------------------------------------
# Robocopy jobs

foreach ($prop in $backupConfig.settings.robocopy.job) {

    if ([string]::IsNullOrEmpty($prop.source) -or [string]::IsNullOrEmpty($prop.target)) { continue }

    Write-Host ""
    Write-Host "$($prop.name)" -ForegroundColor Cyan
    Write-Host "---"

    $answer = if ($IncludeAllRobocopyJobs) { 'yes' } else { Read-Host "Are you sure you want to proceed [yes/no] (default: yes)" }

    if ( $IncludeAllRobocopyJobs -or $answer -eq 'yes' -or [string]::IsNullOrWhiteSpace($answer)) {

        robocopy $prop.source $prop.target ($prop.options -split " ")
    }
}

#---------------------------------------------------------------
# Timeline

Write-Host ""
Write-Host "Timeline" -ForegroundColor Cyan
Write-Host "---"
Write-Host ""

if (!$SkipTimeline) { 

    if ( -not (Test-Path -Path $timelineRoot) ) {
        throw "Timeline root path not found: $timelineRoot"
    }

    # Keep only last 10 timeline folders
    $timelineFolders = Get-ChildItem -Path $timelineRoot -Directory | Sort-Object Name
    $timelineFolders | Select-Object -Skip 3 | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ProgressAction SilentlyContinue
        Write-Host "Deleted: $($_.FullName)" -ForegroundColor Yellow
    }

    Write-Host

    # Timeline subfolder and diff file
    $timelineDir = $timelineRoot + "$((Get-Date).ToString('yyyy-MM-dd_HH_mm_ss'))\"
    $timelineDiff = $timelineDir + "diff.txt"

    # Create timeline subfolder
    if (-not (Test-Path -Path $timelineDir)) {
        New-Item -ItemType Directory -Path $timelineDir | Out-Null
    }

    # Create diff file
    robocopy $rootfolder $target3 /l /s /xo /fp /ns /nc /ndl /np /njh /njs /XD $timelineExcludes /unilog:"$($timelineDiff)" | Out-Null

    # Read diff file and copy files to timeline subfolder
    Get-Content $timelineDiff | Where-Object { $_ -match '^\s+|\s+$' } | ForEach-Object {
    
        $versionCopyFileSrc = $_.Trim()
        
        # copy deleted files
        if ($versionCopyFileSrc.StartsWith($target3)) {
        
            $versionCopyFileDst = [IO.Path]::GetDirectoryName($versionCopyFileSrc.Replace($target3, $timelineDir)) + "\"
            xcopy $versionCopyFileSrc $versionCopyFileDst
        }
        # copy new or changed files
        else {
        
            $versionCopyFileDst = [IO.Path]::GetDirectoryName($versionCopyFileSrc.Replace($rootfolder, $timelineDir)) + "\"
            xcopy $versionCopyFileSrc $versionCopyFileDst
        }
    }
}
else {
    Write-Host "Timeline skip parameter is active" -ForegroundColor Red
}

#---------------------------------------------------------------
# Backup target1

if ($master -and $masterDriveDesc -eq $master.Description) {

    Write-Host ""
    Write-Host "Robocopy to $($target1)" -ForegroundColor Cyan
    Write-Host "---"

    robocopy $rootfolder $target1 /r:0 /ndl /njs /njh /MIR /XD $backupExcludes # /r:0
}

#---------------------------------------------------------------
# Backup target2

if ($slave -and $slaveDriveDesc -eq $slave.Description) {

    Write-Host ""
    Write-Host "Robocopy to $($target2)" -ForegroundColor Cyan
    Write-Host "---"

    robocopy $rootfolder $target2 /r:0 /ndl /njs /njh /MIR /XD $backupExcludes # /r:0
}

#---------------------------------------------------------------

Write-Host ""

#---------------------------------------------------------------
