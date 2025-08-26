#---------------------------------------------------------------
# Params

param(
    [Parameter(Mandatory = $true)]
    [string]$DriveLetter
)

#---------------------------------------------------------------
# Env

# Get current working directory
$baseDirectory = split-path $MyInvocation.MyCommand.Path

# Load environment variables from .env file
. $baseDirectory\library\script\Script_Dotenv.ps1

#--------------------------------------------------------------------------
# Check required env variables 

if (-not $env:ZOK_BACKUP_MASTERDRIVE_PASSWORD) {
    Write-Host "ZOK_BACKUP_MASTERDRIVE_PASSWORD does not exists." -ForegroundColor Red
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
        '-DriveLetter', $DriveLetter
    )
    
    Start-Process pwsh `
        -Verb runAs `
        -ArgumentList $Arguments `
        -Wait

    exit 0
}

#--------------------------------------------------------------------------
# Bitlocker logic

try {
    $BitLockerVolume = Get-BitLockerVolume -MountPoint $DriveLetter -ErrorAction SilentlyContinue

    if ($error[0]) {

        Write-Error "Fehler beim Abrufen des BitLocker-Volumes: $($error[0].Exception.Message)"
        Start-Sleep -Seconds 10
        exit 1
    }

    # Display BitLocker volume status
    $BitLockerVolume | Select-Object * | Format-List
    
    # Check if the volume is locked
    if ($BitLockerVolume.LockStatus -eq "Locked") {
        
        Write-Host "Drive $DriveLetter is locked. Attempting to unlock..."

        # Or use password
        Unlock-BitLocker -MountPoint $DriveLetter -Password (ConvertTo-SecureString $env:ZOK_BACKUP_MASTERDRIVE_PASSWORD -AsPlainText -Force)

        # Confirm unlock
        $NewBitLockerVolume = Get-BitLockerVolume -MountPoint $DriveLetter
        
        if ($NewBitLockerVolume.LockStatus -eq "Unlocked") {
            
            Write-Host "Drive $DriveLetter successfully unlocked."
        }
        else {
            Write-Host "Failed to unlock drive $DriveLetter."
        }
    }
    else {
        Write-Host "Drive $DriveLetter is already unlocked."
    }
}
catch {
    Write-Error "Fehler beim Entsperren: $($_.Exception.Message)"
}

Start-Sleep -Seconds 10