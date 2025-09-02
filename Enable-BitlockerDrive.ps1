#---------------------------------------------------------------
# Params

param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[A-Z]$|^$')]
    [string]$MasterDriveLetter = "",

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[A-Z]$|^$')]
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

#---------------------------------------------------------------
# Dot Source required Function Libraries

. $baseDirectory\library\function\Function_Test-IsAdmin.ps1

#--------------------------------------------------------------------------
# Check required env variables 

if ($MasterDriveLetter.Length -eq 1 -and ($MasterDriveEnvvar -eq "" -or $null -eq [System.Environment]::GetEnvironmentVariable($MasterDriveEnvvar))) {
    Write-Host "Master Drive / Envar does not exists." -ForegroundColor Red
    Start-Sleep -Seconds 10
    exit 1
}

if ($SlaveDriveLetter.Length -eq 1 -and ($SlaveDriveEnvvar -eq "" -or $null -eq [System.Environment]::GetEnvironmentVariable($SlaveDriveEnvvar))) {
    Write-Host "Slave Drive / Envar does not exists." -ForegroundColor Red
    Start-Sleep -Seconds 10
    exit 1
}

#--------------------------------------------------------------------------
# Check if script is running as Administrator

if (-not (Test-IsAdmin)) {
    
    Write-Host "Restarting script as administrator..." -ForegroundColor Yellow

    $Arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)

    if ($MasterDriveLetter -ne '') { $Arguments += @('-MasterDriveLetter', $MasterDriveLetter) }
    if ($SlaveDriveLetter -ne '') { $Arguments += @('-SlaveDriveLetter', $SlaveDriveLetter) }
    if ($MasterDriveEnvvar -ne '') { $Arguments += @('-MasterDriveEnvvar', $MasterDriveEnvvar) }
    if ($SlaveDriveEnvvar -ne '') { $Arguments += @('-SlaveDriveEnvvar', $SlaveDriveEnvvar) }

    $proc = Start-Process pwsh -Verb RunAs -ArgumentList $Arguments -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Elevated run failed with exit code $($proc.ExitCode). See the elevated log for details."
    }
   
    exit $proc.ExitCode
}

#--------------------------------------------------------------------------
# Start logging

Start-Transcript -Path "$($PSScriptRoot)\log\stdout_evaluated.log"

#--------------------------------------------------------------------------
# Main logic

try {

    # Make non-terminating errors throw so catch works
    $ErrorActionPreference = 'Stop'

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

        if ( [string]::IsNullOrEmpty($drive)) {
            Write-Host "Drive letter variable is empty or unvalid. Skipping..." -ForegroundColor Yellow
            continue
        }


        #--------------------------------------------------------------------------
        # Process BitLocker drive

        try {
            $BitLockerVolume = Get-BitLockerVolume -MountPoint $drive -ErrorAction SilentlyContinue

            if ($Error.Count -gt 0 -or $null -eq $BitLockerVolume) {
                Write-Host "Drive $drive not found or not BitLocker enabled. Skipping..." -ForegroundColor Yellow
                continue
            }

            # Display BitLocker volume status
            $BitLockerVolume | Format-List
    
            # Check if the volume is locked
            if ($BitLockerVolume.LockStatus -eq "Locked") {
        
                Write-Host "Drive $drive is locked. Attempting to unlock..."

                # Or use password
                Unlock-BitLocker -MountPoint $drive -Password (ConvertTo-SecureString $envVar -AsPlainText -Force) -ErrorAction Stop
        
                # Confirm unlock
                $NewBitLockerVolume = Get-BitLockerVolume -MountPoint $drive -ErrorAction Stop
        
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

    exit 0
}
catch {
    Write-Error $_
    exit 1 # make sure the elevated process returns non-zero
}
finally {
    Stop-Transcript
}