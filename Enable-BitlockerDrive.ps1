#---------------------------------------------------------------
# Params

param(
    [Parameter(Mandatory = $false)]
    [string]$MasterDriveLetter = "",

    [Parameter(Mandatory = $false)]
    [string]$SlaveDriveLetter = "",

    [Parameter(Mandatory = $false)]
    [string]$MasterDriveEnvvar = "",

    [Parameter(Mandatory = $false)]
    [string]$SlaveDriveEnvvar = ""
)

#---------------------------------------------------------------
# Env

# Get current working directory
$baseDirectory = split-path $MyInvocation.MyCommand.Path

# Load environment variables from .env file
. $baseDirectory\library\script\Script_Dotenv.ps1

#--------------------------------------------------------------------------
# Check required env variables 

if ($MasterDriveLetter -ne "" -and ($MasterDriveEnvvar -eq "" -or $null -eq [System.Environment]::GetEnvironmentVariable($MasterDriveEnvvar))) {
    Write-Host "Master Drive / Envar does not exists." -ForegroundColor Red
    Start-Sleep -Seconds 10
    exit 1
}

if ($SlaveDriveLetter -ne "" -and ($SlaveDriveEnvvar -eq "" -or $null -eq [System.Environment]::GetEnvironmentVariable($SlaveDriveEnvvar))) {
    Write-Host "Slave Drive / Envar does not exists." -ForegroundColor Red
    Start-Sleep -Seconds 10
    exit 1
}

#--------------------------------------------------------------------------
# Check if script is running as Administrator

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    
    Write-Host "Restarting script as administrator..."
    
    $ScriptPath = $MyInvocation.MyCommand.Path
    
    $Arguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', $ScriptPath
        '-MasterDriveLetter', $MasterDriveLetter
        '-SlaveDriveLetter', $SlaveDriveLetter
        '-MasterDriveEnvvar', $MasterDriveEnvvar
        '-SlaveDriveEnvvar', $SlaveDriveEnvvar
    )
    
    Start-Process pwsh `
        -Verb runAs `
        -ArgumentList $Arguments `
        -Wait

    exit 0
}

#--------------------------------------------------------------------------
# Bitlocker logic

foreach ($i in 1..2) {
    
    #--------------------------------------------------------------------------
    # Set drive letter and env var based on iteration

    if (1 -eq $i) {
        $drive = $MasterDriveLetter.ToUpper()
        $envVar = [System.Environment]::GetEnvironmentVariable($MasterDriveEnvvar)
    }
    else {
        $drive = $SlaveDriveLetter.ToUpper()
        $envVar = [System.Environment]::GetEnvironmentVariable($SlaveDriveEnvvar)
    }

    Write-Host "`nProcessing drive $drive ...`n" -ForegroundColor Cyan

    if( $drive -eq "") {
        Write-Host "Drive letter or environment variable is empty. Skipping..." -ForegroundColor Yellow
        continue
    }


    #--------------------------------------------------------------------------
    # Process BitLocker drive

    try {
        $BitLockerVolume = Get-BitLockerVolume -MountPoint $drive -ErrorAction SilentlyContinue

        if ($error[0]) {

            Write-Error "Fehler beim Abrufen des BitLocker-Volumes: $($error[0].Exception.Message)"
            Start-Sleep -Seconds 10
            exit 1
        }

        # Display BitLocker volume status
        $BitLockerVolume | Select-Object * | Format-List
    
        # Check if the volume is locked
        if ($BitLockerVolume.LockStatus -eq "Locked") {
        
            Write-Host "Drive $drive is locked. Attempting to unlock..."

            # Or use password
            Unlock-BitLocker -MountPoint $drive -Password (ConvertTo-SecureString $envVar -AsPlainText -Force)
        
            # Confirm unlock
            $NewBitLockerVolume = Get-BitLockerVolume -MountPoint $drive
        
            if ($NewBitLockerVolume.LockStatus -eq "Unlocked") {
            
                Write-Host "`nDrive $drive successfully unlocked."
            }
            else {
                Write-Host "`nFailed to unlock drive $drive."
            }
        }
        else {
            Write-Host "`nDrive $drive is already unlocked."
        }
    }
    catch {
        Write-Error "`nFehler beim Entsperren: $($_.Exception.Message)"
    }
}

Start-Sleep -Seconds 10