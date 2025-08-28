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
Write-Host "|               Version 2.0                     |            " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host

#---------------------------------------------------------------
# Config

# Get current working directory
$baseDirectory = split-path $MyInvocation.MyCommand.Path

# Get config values
[xml]$sshsetupConfig = Get-Content ($baseDirectory + "/config/sshsetup.xml")

# Dot Source required Function Libraries
. "$($env:USERPROFILE)\Joachim\Devpool\Skripte\library\function\Function_Get-XmlNode.ps1"

#--------------------------------------------------------------------------
# Process

foreach ($prop in $sshsetupConfig.settings.access.job) {
    
    if ([bool]::Parse($prop.done) -eq $true) { continue }

    $answer = Read-Host "Are you sure you want to proceed [yes/no] -> Setup ssh access for '$($prop.name) / $($prop.host)'"

    if ($answer -eq 'yes') {

        $USER_AT_HOST = (Get-XmlNode -Node $prop -XPath "host").InnerText
        $PUBKEYPATH = "$HOME\.ssh\id_ed25519.pub"
    
        $pubKey = (Get-Content "$PUBKEYPATH" | Out-String); ssh "$USER_AT_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '${pubKey}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    }
    
    Write-Host ""
}
