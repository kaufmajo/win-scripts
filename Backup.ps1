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
    [switch]$IncludeBackup = $false,
    [switch]$IncludeConfig = $false,
    [switch]$IncludeHyperV = $false,
    [switch]$IncludeWsl = $false,
    [switch]$SkipTimeline = $false
)

#---------------------------------------------------------------
# Logging setup

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$stdoutLog = Join-Path -Path $PSScriptRoot -ChildPath "log/${scriptName}_stdout_$timestamp.log"
$stdErrLog = Join-Path -Path $PSScriptRoot -ChildPath "log/${scriptName}_stderr_$timestamp.log"
$stdoutElevatedLog = Join-Path -Path $PSScriptRoot -ChildPath "log/${scriptName}_stdout_elevated_$timestamp.log"
$stdErrElevatedLog = Join-Path -Path $PSScriptRoot -ChildPath "log/${scriptName}_stderr_elevated_$timestamp.log"

#---------------------------------------------------------------
# Check PowerShell edition

if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Output "Running in PowerShell (Core)"
}
elseif ($PSVersionTable.PSEdition -eq 'Desktop') {
    Write-Output "Running in Windows PowerShell. Please use PowerShell (Core) instead."
    Exit 1;
}

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
Write-Host "|               Version 3.0                     |            " -ForegroundColor Cyan
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

. $baseDirectory\library\function\Function_Get-BackupVolumes.ps1
. $baseDirectory\library\function\Function_Get-XmlNode.ps1
. $baseDirectory\library\function\Function_Test-IsAdmin.ps1
. $baseDirectory\library\function\Function_Wait-ForInput.ps1

#---------------------------------------------------------------
# Init

$masterDriveLetter = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/letter").InnerText
$slaveDriveLetter = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/letter").InnerText
$masterDriveDesc = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/description").InnerText
$slaveDriveDesc = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/description").InnerText
$masterDriveBitlocker = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/bitlocker").InnerText
$slaveDriveBitlocker = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/bitlocker").InnerText
# 
$rootfolder = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/rootfolder").InnerText
$timelineRoot = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/timelineFolder").InnerText
$wslExportPath = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/wslExportFolder").InnerText
$hyperVExportPath = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/hyperVExportFolder").InnerText
$hyperVPoolPath = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/hyperVPoolFolder").InnerText
# 
$enableForwarding = (Get-XmlNode -Xml $backupConfig -XPath "settings/enableNetworkForwarding").InnerText
$bitLockerScript = (Get-XmlNode -Xml $backupConfig -XPath "settings/script/unlockMasterDrive").InnerText
$masterDriveEnvvar = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/envvar").InnerText
$slaveDriveEnvvar = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/envvar").InnerText

# Backup excludes
$backupExcludes = [System.Collections.Generic.List[string]]@('$RECYCLE.BIN', 'System Volume Information', $timelineRoot, $hyperVPoolPath)
$timelineExcludes = [System.Collections.Generic.List[string]]@('$RECYCLE.BIN', 'System Volume Information', $timelineRoot, $hyperVPoolPath, $hyperVExportPath, $wslExportPath)

# Reset Error Action Preference
$ErrorActionPreference = $oldErrorActionPreference

#--------------------------------------------------------------------------
# Check if script is running as Administrator

if (-not (Test-IsAdmin)) {

    Write-Host
    Write-Host "If script must run with administrator privileges: " -ForegroundColor Yellow
    Write-Host "sudo pwsh -executionpolicy remotesigned -File $($MyInvocation.MyCommand.Definition)" -ForegroundColor Yellow  # https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.invocationinfo?view=powershellsdk-7.4.0
    Write-Host
}

Write-Host

#---------------------------------------------------------------
# Run scripts with elevated privileges

$elevatedCommands = [System.Collections.Generic.List[string]]::new()

function Convert-ToSingleQuotedArgument {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    # Single-quote escaping for PowerShell literals
    return "'" + ($Value -replace "'", "''") + "'"
}

#---------------------------------------------------------------
# Unlock drive

if (
    ($masterDriveLetter -ne "" -and $masterDriveBitlocker -eq "true") -or 
    ($slaveDriveLetter -ne "" -and $slaveDriveBitlocker -eq "true")
) {

    try {
        $bitLockerScript = (Resolve-Path -LiteralPath $bitLockerScript -ErrorAction Stop).Path
    }
    catch {
        throw "BitLocker script path '$bitLockerScript' is invalid. $($_.Exception.Message)"
    }

    $bitLockerArgs = [System.Collections.Generic.List[string]]::new()

    if ($masterDriveLetter) { $bitLockerArgs.Add("-MasterDriveLetter " + (Convert-ToSingleQuotedArgument -Value $masterDriveLetter)) }
    if ($slaveDriveLetter) { $bitLockerArgs.Add("-SlaveDriveLetter " + (Convert-ToSingleQuotedArgument -Value $slaveDriveLetter)) }
    if ($masterDriveEnvvar) { $bitLockerArgs.Add("-MasterDriveEnvvar " + (Convert-ToSingleQuotedArgument -Value $masterDriveEnvvar)) }
    if ($slaveDriveEnvvar) { $bitLockerArgs.Add("-SlaveDriveEnvvar " + (Convert-ToSingleQuotedArgument -Value $slaveDriveEnvvar)) }

    $bitLockerInvocation = "& " + (Convert-ToSingleQuotedArgument -Value $bitLockerScript)
    
    if ($bitLockerArgs.Count -gt 0) {
        $bitLockerInvocation += " " + ($bitLockerArgs -join " ")
    }

    $elevatedCommands.Add($bitLockerInvocation)
}

#---------------------------------------------------------------
# Enable network forwarding

if ($enableForwarding -eq "true") {

    $networkForwardingScript = "$($PSScriptRoot)\Enable-NetworkForwarding.ps1"

    try {
        $networkForwardingScript = (Resolve-Path -LiteralPath $networkForwardingScript -ErrorAction Stop).Path
    }
    catch {
        throw "Network forwarding script path '$networkForwardingScript' is invalid. $($_.Exception.Message)"
    }

    $elevatedCommands.Add("& " + (Convert-ToSingleQuotedArgument -Value $networkForwardingScript))
}

#---------------------------------------------------------------
# If no calls, exit

if ($elevatedCommands.Count -gt 0) { 

    Write-Host
    Write-Host "Scripts require elevated privileges and will be executed with admin rights." -ForegroundColor Yellow
    Write-Host "---"
    Write-Host

    $cmdLines = [System.Collections.Generic.List[string]]::new()
    $cmdLines.Add("`$ErrorActionPreference = 'Stop'")
    $cmdLines.Add("Start-Transcript -Path " + (Convert-ToSingleQuotedArgument -Value $stdoutElevatedLog))
    $cmdLines.Add("try {")
    foreach ($elevatedCommand in $elevatedCommands) {
        $cmdLines.Add("    $elevatedCommand")
    }
    $cmdLines.Add("    exit 0")
    $cmdLines.Add("}")
    $cmdLines.Add("catch {")
    $cmdLines.Add("    Write-Error `$_.Exception.Message")
    $cmdLines.Add("    exit 1")
    $cmdLines.Add("}")
    $cmdLines.Add("finally {")
    $cmdLines.Add("    Stop-Transcript")
    $cmdLines.Add("}")

    $process = Start-Process pwsh `
        -Verb RunAs `
        -Wait `
        -PassThru `
        -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", ($cmdLines -join "`n")
    )

    if ($process.ExitCode -ne 0) {
        throw "Elevated script failed with exit code $($process.ExitCode). Check log: $elevatedLogPath"
    }
}

#---------------------------------------------------------------
# Show drives overview

$master = if ($masterDriveLetter) { Get-Volume -DriveLetter $masterDriveLetter -ErrorAction SilentlyContinue } else { $false }
$slave = if ($slaveDriveLetter) { Get-Volume -DriveLetter $slaveDriveLetter -ErrorAction SilentlyContinue } else { $false }
$drives = Get-BackupVolumes

if ($drives) {
        
    Write-Host "Letter Description Selected"
    Write-Host "______ ___________ ________"
        
    $drives | ForEach-Object {
        Write-Host ("{0}" -f $_.DriveLetter).PadRight(7) -NoNewline
        Write-Host ("{0}" -f $_.FileSystemLabel).PadRight(12) -NoNewline
        if ($master -and $_.DriveLetter -eq $master.DriveLetter -and $_.FileSystemLabel -eq $masterDriveDesc) { Write-Host "Master" -NoNewline -ForegroundColor Green } else { Write-Host -NoNewline }
        if ($slave -and $_.DriveLetter -eq $slave.DriveLetter -and $_.FileSystemLabel -eq $slaveDriveDesc) { Write-Host "Slave" -ForegroundColor Green } else { Write-Host }
    }    
}

Write-Host

#---------------------------------------------------------------
# Pick master drive

if (-not $master -or $masterDriveDesc -ne $master.FileSystemLabel) {
    
    Write-Host "Enter " -NoNewline
    Write-Host "master " -NoNewline -ForegroundColor Yellow
    Write-Host "drive letter: " -NoNewline
    $masterDriveLetter = Wait-ForInput

    $master = if ($masterDriveLetter) { Get-Volume -DriveLetter $masterDriveLetter -ErrorAction SilentlyContinue } else { $false }
}

#---------------------------------------------------------------
# Pick slave drive

if (-not $slave -or $slaveDriveDesc -ne $slave.FileSystemLabel) {

    Write-Host "Enter " -NoNewline
    Write-Host "slave " -NoNewline -ForegroundColor Yellow
    Write-Host "drive letter: " -NoNewline
    $slaveDriveLetter = Wait-ForInput

    $slave = if ($slaveDriveLetter) { Get-Volume -DriveLetter $slaveDriveLetter -ErrorAction SilentlyContinue } else { $false }
}

#---------------------------------------------------------------
# Check and set target2

if ($slave -and $slaveDriveDesc -eq $slave.FileSystemLabel -and (Test-Path -Path "$($slaveDriveLetter):")) {
    $target2 = "$($slaveDriveLetter):\$($env:COMPUTERNAME)\$($env:UserName)\"
    $target3 = $target2
}
else {
    Write-Host "No valid slave drive given, or drive is locked." -ForegroundColor Red
    $slave = ""
}

#---------------------------------------------------------------
# Check and set target1

if ($master -and $masterDriveDesc -eq $master.FileSystemLabel -and (Test-Path -Path "$($masterDriveLetter):")) {
    $target1 = "$($masterDriveLetter):\$($env:COMPUTERNAME)\$($env:UserName)\"
    $target3 = $target1
}
else {
    Write-Host "No valid master drive given, or drive is locked." -ForegroundColor Red
    $master = ""
}

#---------------------------------------------------------------

Write-Host

if (-not ($master) -and -not ($slave)) { exit }

#---------------------------------------------------------------
#
#
# Start processing
#
#
#---------------------------------------------------------------

#---------------------------------------------------------------
# Check root folder

if ( -not (Test-Path -Path $rootfolder) ) {
    throw "Root path not found: $rootfolder"
}

#---------------------------------------------------------------
# HyperV Export

if ($IncludeHyperV) { 

    if ( -not (Test-Path -Path $hyperVExportPath) ) {
        throw "HyperV Export path not found: $hyperVExportPath"
    }

    Write-Host
    Write-Host "HyperV Export for ... " -ForegroundColor Cyan
    Write-Host "---"
    Write-Host

    foreach ($prop in $backupConfig.settings.hyperVExport.job) {

        if ($prop.name -eq "") { continue }

        Write-Host "... $($prop.name)"

        Remove-Item $hyperVExportPath\* -Recurse

        Export-VM -Name $prop.name -Path $hyperVExportPath
    }
}

#---------------------------------------------------------------
# Wsl Export

if ($IncludeWsl) { 

    if ( -not (Test-Path -Path $wslExportPath) ) {
        throw "WSL Export path not found: $wslExportPath"
    }

    Write-Host
    Write-Host "WSL Export for ... " -ForegroundColor Cyan
    Write-Host "---"
    Write-Host

    foreach ($prop in $backupConfig.settings.wslExport.job) {

        if ($prop.name -eq "") { continue }

        Write-Host "... $($prop.name)"

        Remove-Item $wslExportPath\* -Recurse

        wsl --export $prop.name $wslExportPath\debian.tar
    }
}

#---------------------------------------------------------------
# Robocopy jobs

foreach ($prop in $backupConfig.settings.robocopy.job) {

    if (
        [string]::IsNullOrEmpty($prop.source) -or
        [string]::IsNullOrEmpty($prop.target) -or
        (-not $IncludeBackup -and $prop.type -eq "backup") -or
        (-not $IncludeConfig -and $prop.type -eq "config")
    ) {
        continue
    }

    Write-Host
    Write-Host "$($prop.name)" -ForegroundColor Cyan
    Write-Host "---"
    Write-Host

    robocopy ($prop.options -split " ") $prop.source $prop.target $prop.file
}

#---------------------------------------------------------------
# Rsync jobs

foreach ($prop in $dotfileConfig.settings.rsync.job) {

    if (
        [string]::IsNullOrEmpty($prop.source) -or
        [string]::IsNullOrEmpty($prop.target) -or
        (-not $IncludeBackup -and $prop.type -eq "backup") -or
        (-not $IncludeConfig -and $prop.type -eq "config")
    ) {
        continue
    }

    Write-Host ""
    Write-Host "$($prop.name)" -ForegroundColor Cyan
    Write-Host "---"
    Write-Host

    wsl rsync ($prop.options -split " ") $prop.source $prop.target
}

#---------------------------------------------------------------
# Timeline

Write-Host
Write-Host "Timeline" -ForegroundColor Cyan
Write-Host "---"
Write-Host

if (!$SkipTimeline) { 

    if ( -not (Test-Path -Path $timelineRoot) ) {
        throw "Timeline root path not found: $timelineRoot"
    }

    # Keep only last timeline folders
    $timelineFolders = Get-ChildItem -Path $timelineRoot -Directory | Sort-Object Name -Descending
    $timelineFolders | Select-Object -Skip 30 | ForEach-Object {
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

if ($master -and $masterDriveDesc -eq $master.FileSystemLabel) {

    Write-Host
    Write-Host "Robocopy to $($target1)" -ForegroundColor Cyan
    Write-Host "---"
    Write-Host

    robocopy $rootfolder $target1 /r:0 /ndl /njs /njh /MIR /XD $backupExcludes # /r:0
}

#---------------------------------------------------------------
# Backup target2

if ($slave -and $slaveDriveDesc -eq $slave.FileSystemLabel) {

    Write-Host
    Write-Host "Robocopy to $($target2)" -ForegroundColor Cyan
    Write-Host "---"
    Write-Host

    robocopy $rootfolder $target2 /r:0 /ndl /njs /njh /MIR /XD $backupExcludes # /r:0
}

#---------------------------------------------------------------

Write-Host

#---------------------------------------------------------------
