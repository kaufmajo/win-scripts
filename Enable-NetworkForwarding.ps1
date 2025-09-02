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
Write-Host "|               Network forwarding script       |            " -ForegroundColor Cyan
Write-Host "|               Version 2.0                     |            " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host

#---------------------------------------------------------------
# Config

# Get current working directory
$baseDirectory = split-path $MyInvocation.MyCommand.Path

# Get config values
[xml]$networkConfig = Get-Content ($baseDirectory + "/config/network.xml")

#---------------------------------------------------------------
# Dot Source required Function Libraries

. $baseDirectory\library\function\Function_Get-XmlNode.ps1
. $baseDirectory\library\function\Function_Test-IsAdmin.ps1

#--------------------------------------------------------------------------
# Check if script is running as Administrator

if (-not (Test-IsAdmin)) {

  Write-Host "Restarting script as administrator..."

  $Arguments = @(
    '-NoProfile'
    '-ExecutionPolicy', 'Bypass'
    '-File', $PSCommandPath
  )

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

  #--------------------------------------------------------------------------
  # Check WSL network is active


  Write-Host "Try to run 'wsl -d Debian hostname -i' ..." -ForegroundColor Green
  
  wsl -d Debian hostname -i

  Write-Host

  # --------------------------------------------------------------------------
  # Check network forwarding for given interfaces

  $interfaces = Get-XmlNode -Xml $networkConfig -XPath "settings/network/forwarding" 

  foreach ($interface in $Interfaces.ChildNodes) {

    $alias = $interface.InnerText

    Write-Host "Checking network forwarding: $($alias)" -ForegroundColor Cyan

    $interface = Get-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 

    if ('Enabled' -ne $interface.Forwarding) {  

      #--------------------------------------------------------------------------
      # Enable network forwarding

      Write-Host "Enabling network forwarding: $($alias)" -ForegroundColor Yellow
    
      Set-NetIPInterface -InterfaceIndex $interface.InterfaceIndex -Forwarding Enabled
    }
  }

  Start-Sleep -Seconds 3

  #---------------------------------------------------------------

  exit 0
}
catch {
  Write-Error $_
  exit 1 # make sure the elevated process returns non-zero
}
finally {
  Stop-Transcript
}
