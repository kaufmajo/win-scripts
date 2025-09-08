<#
    ---------------------------------------------------------------

    https://code.visualstudio.com/docs/remote/troubleshooting#_configuring-key-based-authentication

    ---------------------------------------------------------------

    cd C:\Users\joachim.kaufmann\.ssh

    ssh-keygen -t ed25519 -b 4096

    icacls "id_ed25519" /grant espas\joachim.kaufmann:R

#>

#---------------------------------------------------------------
# Header

Write-Host ">>> Script started at $(Get-Date) <<<"
Write-Host
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host "|               Setup Ssh access script         |            " -ForegroundColor Cyan
Write-Host "|               Version 2.1                     |            " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host

Write-Host " >>> Please run similar script on wsl to setup ssh access from wsl  <<<" -ForegroundColor Red
Write-Host 

#---------------------------------------------------------------
# Config

# Get current working directory
$baseDirectory = split-path $MyInvocation.MyCommand.Path

# Get config values
[xml]$sshsetupConfig = Get-Content ($baseDirectory + "/config/sshsetup.xml")

#---------------------------------------------------------------
# Dot Source required Function Libraries

. $baseDirectory\library\function\Function_Get-XmlNode.ps1
. $baseDirectory\library\function\Function_Test-IsAdmin.ps1

#--------------------------------------------------------------------------
# Check if script is running as Administrator

if (-not (Test-IsAdmin)) {

    $answer = Read-Host "Do you want to run this script as admin? [yes/no]?"

    if ($answer -eq 'yes') {

        Write-Host "Restarting script as administrator..."
    
        $Arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    
        $proc = Start-Process pwsh -Verb RunAs -ArgumentList $Arguments -Wait -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "Elevated run failed with exit code $($proc.ExitCode). See the elevated log for details."
        }
   
        exit $proc.ExitCode
    }
}

#--------------------------------------------------------------------------
# Process

foreach ($prop in $sshsetupConfig.settings.access.job) {
    
    if ([bool]::Parse($prop.done) -eq $true) { continue }

    $answer = Read-Host "Are you sure you want to proceed? [yes/no] -> Setup ssh access for '$($prop.name) / $($prop.host)'"

    if ($answer -eq 'yes') {

        $USER_AT_HOST = (Get-XmlNode -Node $prop -XPath "host").InnerText
        $PUBKEYPATH = "$HOME\.ssh\id_ed25519.pub"
    
        $pubKey = (Get-Content "$PUBKEYPATH" | Out-String); ssh "$USER_AT_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '${pubKey}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    }
    
    Write-Host ""
}
