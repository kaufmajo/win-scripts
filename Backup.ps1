<#
    ---------------------------------------------------------------

    Backup.ps1 - Mirror the Windows root folder to the master and slave backup drives.

    - Backs up Windows files only. The WSL filesystem is backed up by
      linux_scripts/backup.sh (start it afterwards with -WithLinux).

    - History: before mirroring, the old version of every file that robocopy
      will overwrite or delete is moved to the history folder on the backup drive.

    Layout on each backup drive:

        X:\<COMPUTERNAME>\<targetFolder>\<USERNAME>\           mirror
        X:\<COMPUTERNAME>\<targetFolder>\<USERNAME>.history\   history (newest <historyKeep> runs)

    ---------------------------------------------------------------

    If robocopy marks a copied directory with the System+Hidden attribute,
    make it visible again with:

        attrib -R -S X:\MyBackup /S /D

    https://stackoverflow.com/questions/6584402/after-robocopy-the-copied-directory-and-files-are-not-visible-on-the-destinatio

    ---------------------------------------------------------------
#>

#===============================================================
# PARAMS
#===============================================================

param(
    [string]$ConfigFile = "",
    [switch]$ExportHyperV = $false,
    [switch]$ExportWsl = $false,
    [switch]$SkipHistory = $false,
    [switch]$WithLinux = $false
)

#===============================================================
# ERROR HANDLING AND START
#===============================================================

$Error.Clear();
$ErrorActionPreference = "Stop"

#===============================================================
# BASE DIRECTORY (PSSCRIPTROOT PREFERRED)
#===============================================================

$baseDirectory = $PSScriptRoot

#===============================================================
# DOT SOURCE REQUIRED FUNCTION LIBRARIES
#===============================================================

. $baseDirectory\library\function\Function_Get-BackupVolumes.ps1
. $baseDirectory\library\function\Function_Get-XmlNode.ps1
. $baseDirectory\library\function\Function_Wait-ForInput.ps1
. $baseDirectory\library\function\Function_Write-MainHeader.ps1
. $baseDirectory\library\function\Function_Write-SectionHeader.ps1

#===============================================================
# CHECK POWERSHELL EDITION
#===============================================================

if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Output "Running in PowerShell (Core)"
}
elseif ($PSVersionTable.PSEdition -eq 'Desktop') {
    Write-Output "Running in Windows PowerShell. Please use PowerShell (Core) instead"
    Exit 1;
}

#===============================================================
# MAIN HEADER
#===============================================================

Write-MainHeader -Title "Backup Script (Win)" -Subtitle "Version 0.7.4"

#===============================================================
# CONFIG
#===============================================================

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

Write-Host "Using config file $configPath"

try {
    [xml]$backupConfig = Get-Content -LiteralPath $configPath -ErrorAction Stop
}
catch {
    throw "Failed to load config file '$configPath'. $($_.Exception.Message)"
}

#===============================================================
# INIT
#===============================================================

$masterDriveLetter = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/letter").InnerText
$masterDriveLabel = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/label").InnerText
$masterDriveBitlocker = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/bitlocker").InnerText
$masterDriveEnvvar = (Get-XmlNode -Xml $backupConfig -XPath "settings/masterdrive/envvar").InnerText
#
$slaveDriveLetter = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/letter").InnerText
$slaveDriveLabel = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/label").InnerText
$slaveDriveBitlocker = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/bitlocker").InnerText
$slaveDriveEnvvar = (Get-XmlNode -Xml $backupConfig -XPath "settings/slavedrive/envvar").InnerText
#
$rootfolder = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/rootfolder").InnerText
$targetFolder = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/targetFolder").InnerText
$configFolder = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/configFolder").InnerText.TrimEnd('\')
$wslExportPath = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/wslExportFolder").InnerText
$hyperVExportPath = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/hyperVExportFolder").InnerText
$hyperVPoolPath = (Get-XmlNode -Xml $backupConfig -XPath "settings/folder/hyperVPoolFolder").InnerText
#
$historyKeep = [int](Get-XmlNode -Xml $backupConfig -XPath "settings/historyKeep").InnerText
$bitLockerScript = (Get-XmlNode -Xml $backupConfig -XPath "settings/script/unlockDrive").InnerText
$linuxDistribution = (Get-XmlNode -Xml $backupConfig -XPath "settings/linux/distribution").InnerText
$linuxScript = (Get-XmlNode -Xml $backupConfig -XPath "settings/linux/script").InnerText
$configPaths = @($backupConfig.settings.config.path)

# Excluded from the mirror
$backupExcludes = @('$RECYCLE.BIN', 'System Volume Information', $hyperVPoolPath)

# Excluded from the history in addition (big export files, only the latest is kept)
$historyExcludes = $backupExcludes + @($hyperVExportPath, $wslExportPath)

# Robocopy source without trailing backslash ("C:\path\" would escape the closing quote)
$source = $rootfolder.TrimEnd('\')

# The config folder is emptied and rebuilt on every run: it must be a subfolder
# of the root folder (so it is mirrored) and never the root folder itself.
if (-not $configFolder.StartsWith("$source\", [StringComparison]::OrdinalIgnoreCase)) {
    throw "configFolder must be a subfolder of rootfolder: $configFolder"
}

$failed = $false

#===============================================================
# FUNCTIONS
#===============================================================

# Returns 'Ready' (label matches), 'NotReady' (locked BitLocker drive or
# wrong label) or 'Missing'. Works without administrator rights.
function Get-DriveState {
    param(
        [string]$Letter,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Letter)) { return 'Missing' }

    $volume = Get-Volume -DriveLetter $Letter -ErrorAction SilentlyContinue

    if (-not $volume) { return 'Missing' }
    if ($volume.FileSystemLabel -eq $Label) { return 'Ready' }

    return 'NotReady'
}

# Copies each path (file or folder) to $ConfigFolder, keeping the full source
# path, like "rsync --relative":
#   C:\Users\me\.gitconfig  ->  <ConfigFolder>\C\Users\me\.gitconfig
# Returns the number of failed copies.
function Copy-ConfigFiles {
    param(
        [string]$ConfigFolder,
        [string[]]$Paths
    )

    $failures = 0

    foreach ($path in $Paths) {

        if ([string]::IsNullOrWhiteSpace($path)) { continue }

        $path = $path.TrimEnd('\')

        # "C:\Users\me" -> "C\Users\me" (drive letter becomes a folder)
        $relative = ($path -replace '^([A-Za-z]):', '$1').TrimStart('\')
        $target = Join-Path $ConfigFolder $relative

        # "| Out-Host" shows robocopy's output; without it, the output would
        # become the return value of this function.
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            robocopy (Split-Path $path) (Split-Path $target) (Split-Path $path -Leaf) /R:0 /NS /NC /NDL /NP /NJH /NJS | Out-Host
        }
        elseif (Test-Path -LiteralPath $path -PathType Container) {
            robocopy $path $target /E /R:0 /NS /NC /NDL /NP /NJH /NJS | Out-Host
        }
        else {
            Write-Host "Config path not found, skipped: $path" -ForegroundColor Yellow
            continue
        }

        if ($LASTEXITCODE -ge 8) {
            Write-Host "Robocopy failed with exit code $($LASTEXITCODE): $path" -ForegroundColor Red
            $failures++
        }
    }

    return $failures
}

# Moves the old version of every file that "robocopy /MIR" would overwrite or
# delete in $Target to $HistoryDir (same relative path). Returns the file count.
function Move-ToHistory {
    param(
        [string]$Source,
        [string]$Target,
        [string]$HistoryDir,
        [string[]]$Excludes
    )

    if (-not (Test-Path -LiteralPath $Target)) { return 0 }

    # /L only lists what /MIR would do, one full path per line:
    #   source path -> new or changed file (overwrites the target file, if any)
    #   target path -> extra file (will be deleted)
    $lines = robocopy $Source $Target /L /MIR /FP /NS /NC /NDL /NP /NJH /NJS /XD $Excludes

    if ($LASTEXITCODE -ge 8) {
        throw "robocopy /L failed with exit code $LASTEXITCODE"
    }

    $sourcePrefix = "$Source\"
    $targetPrefix = "$Target\"
    $count = 0

    foreach ($line in $lines) {

        $path = $line.Trim()

        # Skip empty lines and directories (they end with a backslash)
        if ($path -eq '' -or $path.EndsWith('\')) { continue }

        if ($path.StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            # Extra file: will be deleted
            $relative = $path.Substring($targetPrefix.Length)
        }
        elseif ($path.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            # New or changed file: only an existing target file has an old version
            $relative = $path.Substring($sourcePrefix.Length)
            if (-not (Test-Path -LiteralPath (Join-Path $Target $relative) -PathType Leaf)) { continue }
        }
        else {
            continue
        }

        $oldFile = Join-Path $Target $relative
        $historyFile = Join-Path $HistoryDir $relative

        try {
            New-Item -ItemType Directory -Path (Split-Path $historyFile) -Force | Out-Null
            Move-Item -LiteralPath $oldFile -Destination $historyFile -Force
            Write-Host "History: $relative"
            $count++
        }
        catch {
            Write-Host "Could not move to history: $oldFile. $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    return $count
}

#===============================================================
# UNLOCK DRIVES (ONLY IF NEEDED)
#===============================================================

# Enable-BitlockerDrive.ps1 elevates itself (UAC prompt), so it is only
# called for drives that are present but not ready (= locked).

$unlockArgs = @{}

if ($masterDriveBitlocker -eq "true" -and (Get-DriveState $masterDriveLetter $masterDriveLabel) -eq 'NotReady') {
    $unlockArgs.MasterDriveLetter = $masterDriveLetter
    $unlockArgs.MasterDriveEnvvar = $masterDriveEnvvar
}

if ($slaveDriveBitlocker -eq "true" -and (Get-DriveState $slaveDriveLetter $slaveDriveLabel) -eq 'NotReady') {
    $unlockArgs.SlaveDriveLetter = $slaveDriveLetter
    $unlockArgs.SlaveDriveEnvvar = $slaveDriveEnvvar
}

if ($unlockArgs.Count -gt 0) {

    Write-SectionHeader -Title "Unlock BitLocker drives"

    try {
        $bitLockerScript = (Resolve-Path -LiteralPath $bitLockerScript -ErrorAction Stop).Path
        & $bitLockerScript @unlockArgs

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Unlock script failed with exit code $LASTEXITCODE" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Unlock failed. $($_.Exception.Message)" -ForegroundColor Red
    }
}

#===============================================================
# SHOW DRIVES OVERVIEW
#===============================================================

Write-SectionHeader -Title "Drives"

$drives = Get-BackupVolumes

if ($drives) {

    Write-Host "Letter Label       Selected"
    Write-Host "______ ___________ ________"

    $drives | ForEach-Object {
        Write-Host ("{0}" -f $_.DriveLetter).PadRight(7) -NoNewline
        Write-Host ("{0}" -f $_.FileSystemLabel).PadRight(12) -NoNewline
        if ($_.DriveLetter -eq $masterDriveLetter -and $_.FileSystemLabel -eq $masterDriveLabel) { Write-Host "Master" -ForegroundColor Green }
        elseif ($_.DriveLetter -eq $slaveDriveLetter -and $_.FileSystemLabel -eq $slaveDriveLabel) { Write-Host "Slave" -ForegroundColor Green }
        else { Write-Host }
    }
}

Write-Host

#===============================================================
# PICK DRIVES AND SET TARGETS
#===============================================================

$targets = [System.Collections.Generic.List[string]]::new()

$driveConfigs = @(
    @{ Role = 'master'; Letter = $masterDriveLetter; Label = $masterDriveLabel },
    @{ Role = 'slave'; Letter = $slaveDriveLetter; Label = $slaveDriveLabel }
)

foreach ($drive in $driveConfigs) {

    $letter = $drive.Letter

    if ((Get-DriveState $letter $drive.Label) -ne 'Ready') {
        Write-Host "Enter " -NoNewline
        Write-Host "$($drive.Role) " -NoNewline -ForegroundColor Yellow
        Write-Host "drive letter: " -NoNewline
        $letter = Wait-ForInput
    }

    if ((Get-DriveState $letter $drive.Label) -eq 'Ready') {
        $target = "$($letter):\$($env:COMPUTERNAME)\$targetFolder\$($env:UserName)"
        $roleName = $drive.Role.Substring(0, 1).ToUpper() + $drive.Role.Substring(1)
        Write-Host "$roleName is $target\"
        $targets.Add($target)
    }
    else {
        Write-Host "No valid $($drive.Role) drive given, or drive is locked" -ForegroundColor Yellow
    }
}

Write-Host

if ($targets.Count -eq 0) { exit 1 }

#===============================================================
# CHECK ROOT FOLDER
#===============================================================

if ( -not (Test-Path -Path $rootfolder) ) {
    throw "Root path not found: $rootfolder"
}

# From here on, single failures are reported, the script continues
$ErrorActionPreference = "Continue"

#===============================================================
# EXPORT HYPERV
#===============================================================

if ($ExportHyperV) {

    Write-SectionHeader -Title "Export: HyperV"

    if ( -not (Test-Path -Path $hyperVExportPath) ) {
        throw "HyperV Export path not found: $hyperVExportPath"
    }

    foreach ($job in $backupConfig.settings.hyperVExport.job) {

        if ([string]::IsNullOrEmpty($job.name)) { continue }

        Write-Host "... $($job.name)"

        try {
            # Export-VM creates <path>\<vm name>\ - remove only the previous export of this VM
            $vmExportPath = Join-Path $hyperVExportPath $job.name
            if (Test-Path -LiteralPath $vmExportPath) {
                Remove-Item -LiteralPath $vmExportPath -Recurse -Force -ErrorAction Stop
            }

            Export-VM -Name $job.name -Path $hyperVExportPath -ErrorAction Stop
        }
        catch {
            Write-Host "HyperV export of '$($job.name)' failed. $($_.Exception.Message)" -ForegroundColor Red
            $failed = $true
        }
    }
}

#===============================================================
# EXPORT WSL
#===============================================================

if ($ExportWsl) {

    Write-SectionHeader -Title "Export: WSL"

    if ( -not (Test-Path -Path $wslExportPath) ) {
        throw "WSL Export path not found: $wslExportPath"
    }

    foreach ($job in $backupConfig.settings.wslExport.job) {

        if ([string]::IsNullOrEmpty($job.name)) { continue }

        Write-Host "... $($job.name)"

        # One file per distribution: <name>.tar
        $tarFile = Join-Path $wslExportPath "$($job.name).tar"

        if (Test-Path -LiteralPath $tarFile) {
            Remove-Item -LiteralPath $tarFile -Force
        }

        wsl.exe --export $job.name $tarFile

        if ($LASTEXITCODE -ne 0) {
            Write-Host "WSL export of '$($job.name)' failed with exit code $LASTEXITCODE" -ForegroundColor Red
            $failed = $true
        }
    }
}

#===============================================================
# CONFIG FILES (always, before the mirror, so the copies get backed up)
#===============================================================

# The folder is rebuilt from scratch, so it always contains exactly the
# configured paths. Robocopy keeps the timestamps: unchanged files look
# identical to the mirror and create no history.

Write-SectionHeader -Title "Config" -Detail "$configFolder\"

if (Test-Path -LiteralPath $configFolder) {
    Remove-Item -LiteralPath $configFolder -Recurse -Force
}

if ((Copy-ConfigFiles -ConfigFolder $configFolder -Paths $configPaths) -gt 0) {
    $failed = $true
}

#===============================================================
# HISTORY AND BACKUP PER TARGET
#===============================================================

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH_mm_ss'

foreach ($target in $targets) {

    $historyRoot = "$target.history"

    #---------------------------------------------------------------
    # Move old versions to history

    if (-not $SkipHistory) {

        Write-SectionHeader -Title "History" -Detail "$historyRoot\$timestamp\"

        try {
            $moved = Move-ToHistory -Source $source -Target $target -HistoryDir "$historyRoot\$timestamp" -Excludes $historyExcludes
            Write-Host "Moved $moved file(s) to history"
        }
        catch {
            Write-Host "History failed. $($_.Exception.Message)" -ForegroundColor Red
            $failed = $true
        }
    }
    else {
        Write-Host "History: skipped (-SkipHistory)" -ForegroundColor Yellow
    }

    #---------------------------------------------------------------
    # Mirror

    Write-SectionHeader -Title "Backup" -Detail "$target\"

    robocopy $source $target /r:0 /ndl /njs /njh /MIR /XD $backupExcludes

    # Exit code 0 = nothing copied and nothing deleted
    if ($LASTEXITCODE -eq 0) {
        Write-Host "No changed files found for backup"
    }
    elseif ($LASTEXITCODE -ge 8) {
        Write-Host "Robocopy failed with exit code $LASTEXITCODE" -ForegroundColor Red
        $failed = $true
    }

    #---------------------------------------------------------------
    # Keep only the newest history folders (names are timestamps)

    if (-not $SkipHistory -and (Test-Path -LiteralPath $historyRoot)) {

        Get-ChildItem -LiteralPath $historyRoot -Directory |
        Sort-Object Name -Descending |
        Select-Object -Skip $historyKeep |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ProgressAction SilentlyContinue
            Write-Host "Deleted history: $($_.FullName)"
        }
    }
}

#===============================================================
# LINUX BACKUP (WSL)
#===============================================================

if ($WithLinux) {

    wsl.exe -d $linuxDistribution -- $linuxScript

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Linux backup failed with exit code $LASTEXITCODE" -ForegroundColor Red
        $failed = $true
    }
}

#---------------------------------------------------------------

if ($failed) {
    Write-Host
    Write-Host "Backup finished with errors" -ForegroundColor Red
    exit 1
}

#---------------------------------------------------------------
