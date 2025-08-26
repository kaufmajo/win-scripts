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
Write-Host ""

#---------------------------------------------------------------
# Config

# Get current working directory
$baseDirectory = split-path $MyInvocation.MyCommand.Path

# Get config values
[xml]$networkConfig = Get-Content ($baseDirectory + "/config/network.xml")

# Dot Source required Function Libraries
. "$($env:USERPROFILE)\Joachim\Devpool\Skripte\library\function\Function_Get-XmlNode.ps1"

#--------------------------------------------------------------------------
# Check if script is running as Administrator

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    
  Write-Host "Restarting script as administrator..."
    
  $ScriptPath = $MyInvocation.MyCommand.Path
    
  $Arguments = @(
    '-NoProfile'
    '-ExecutionPolicy', 'Bypass'
    '-File', $ScriptPath
  )
    
  Start-Process pwsh `
    -Verb runAs `
    -ArgumentList $Arguments `
    -Wait

  exit 0
}

#--------------------------------------------------------------------------
# Check WSL network is active

try {
  Write-Host "Try to run 'wsl -d Debian hostname -i' ..." -ForegroundColor Green
  
  wsl -d Debian hostname -i
}
catch {
  Write-Host "WSL konnte nicht gestartet werden: $_" -ForegroundColor Red
}

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
