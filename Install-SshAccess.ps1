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

Write-Host "`n"
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host "|               Setup Ssh access script         |            " -ForegroundColor Cyan
Write-Host "|               Version 1.0                     |            " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host ""

#--------------------------------------------------------------------------
# Init

$hosts = [ordered]@{
    debian_01___hyperv = 'user1@10.99.99.20'
    debian_02___hyperv = 'user1@10.99.99.30'
    debian_04___hyperv = 'user1@10.99.99.40'
}

#--------------------------------------------------------------------------
# Process

foreach ($h in $hosts.GetEnumerator() ) {
    
    $answer = Read-Host "Are you sure you want to proceed [y/n] -> Setup ssh access for '$($h.Value)/$($h.Name)'"

    if ($answer -eq 'y') {

        $USER_AT_HOST = $h.Value
        $PUBKEYPATH = "$HOME\.ssh\id_ed25519.pub"
    
        $pubKey = (Get-Content "$PUBKEYPATH" | Out-String); ssh "$USER_AT_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '${pubKey}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    }
    
    Write-Host ""
}
