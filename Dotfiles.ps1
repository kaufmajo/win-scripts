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
Write-Host "|               Dotfile script                  |            " -ForegroundColor Cyan
Write-Host "|               Version 2.0                     |            " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host ""

#---------------------------------------------------------------
# Config

# Get current working directory
$baseDirectory = split-path $MyInvocation.MyCommand.Path

# Get config values
[xml]$dotfileConfig = Get-Content ($baseDirectory + "/config/dotfile.xml")

# Dot Source required Function Libraries
. "$($env:USERPROFILE)\Joachim\Devpool\Skripte\library\function\Function_Get-XmlNode.ps1"

#--------------------------------------------------------------------------
# network forwarding

$enableForwarding = Get-XmlNode -Xml $dotfileConfig -XPath "settings/enableNetworkForwarding" 

if ($enableForwarding.InnerText -eq "true") {

    Write-Host "Enable network forwarding" -ForegroundColor Yellow

    # Start EnableNetworkForwarding.ps1 as separate process to get elevated rights via UAC prompt

    $proc = Start-Process pwsh `
        -Verb runAs `
        -ArgumentList "-File `"$($PSScriptRoot)\Enable-NetworkForwarding.ps1`"" `
        -Wait `
        -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Enable network forwarding script process failed with exit code $($process.ExitCode)"
    }
}

#---------------------------------------------------------------
# Robocopy jobs

foreach ($prop in $dotfileConfig.settings.robocopy.job) {

    Write-Host ""
    Write-Host "$($prop.name)" -ForegroundColor Cyan
    Write-Host "---"

    if ($prop.source -and $prop.target) {

        robocopy ($prop.options -split " ") $prop.source $prop.target $prop.file
    }
}

#---------------------------------------------------------------
# Rsync jobs

foreach ($prop in $dotfileConfig.settings.rsync.job) {

    Write-Host ""
    Write-Host "$($prop.name)" -ForegroundColor Cyan
    Write-Host "---"

    if ($prop.source -and $prop.target) {

        wsl rsync ($prop.options -split " ") $prop.source $prop.target
    }
}

Start-Sleep -Seconds 10
