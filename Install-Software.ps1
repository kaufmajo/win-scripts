#---------------------------------------------------------------
# Header

Write-Host ">>> Script started at $(Get-Date) <<<"
Write-Host ""
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host "|               Install script                  |            " -ForegroundColor Cyan
Write-Host "|               Version 2.0                     |            " -ForegroundColor Cyan
Write-Host "|                                               |            " -ForegroundColor Cyan
Write-Host " -----------------------------------------------             " -ForegroundColor Cyan
Write-Host ""

#---------------------------------------------------------------
# Dot Source required Function Libraries

. $baseDirectory\library\function\Function_Test-IsAdmin.ps1

#--------------------------------------------------------------------------
# Init

$winget = [ordered]@{
    Visual_Code                          = 'winget install --id=Microsoft.VisualStudioCode -e'
    VisualStudioCommunity                = 'winget install --id=Microsoft.VisualStudio.2022.Community  -e'
    DockerDesktop                        = 'winget install --id=Docker.DockerDesktop  -e'
    Firefox                              = 'winget install --id Mozilla.Firefox -e'
    Thunderbird                          = 'winget install --id Mozilla.Thunderbird -e'
    DeltaChat                            = 'winget install --id=DeltaChat.DeltaChat -e'
    Total_Commander                      = 'winget install --id Ghisler.TotalCommander -e'
    Notepad_PlusPlus                     = 'winget install --id=Notepad++.Notepad++ -e'
    #LibreOffice                          = 'winget install --id=TheDocumentFoundation.LibreOffice  -e'
    #VLC                                  = 'winget install --id=VideoLAN.VLC  -e'
    Neovim                               = 'winget install --id=Neovim.Neovim -e'
    Git                                  = 'winget install --id=Git.Git -e'
    Nmap                                 = 'winget install --id=Insecure.Nmap -e'
    Python                               = 'winget install --id=Python.Python.3.13 -e'
    NodeJs                               = 'winget install --id=OpenJS.NodeJS.LTS -e'
    Postman                              = 'winget install --id=Postman.Postman  -e'
    OhMyPosh_Styles_for_Windows_Terminal = 'winget install JanDeDobbeleer.OhMyPosh'
    GithubCli                            = 'winget install --id GitHub.cli -e'
    DBeaver                              = 'winget install --id DBeaver.DBeaver.Community -e'
}

#---------------------------------------------------------------
# Check current principal mode

if (-not (Test-IsAdmin)) {

    Write-Host 
    Write-Host "Script must run with administrator privileges: " -NoNewline -ForegroundColor Red
    Write-Host "sudo pwsh -executionpolicy remotesigned -File $($MyInvocation.MyCommand.Definition)" -ForegroundColor Yellow  # https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.invocationinfo?view=powershellsdk-7.4.0
    
    exit 0
}

#---------------------------------------------------------------
# Powershell Execution Policy

$answer = Read-Host "Are you sure you want to proceed [y/n] -> Set Powershell Execution Policy to 'RemoteSigned'"

if ($answer -eq 'y') {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
}

#---------------------------------------------------------------
# Winget Installations

foreach ($h in $winget.GetEnumerator() ) {

    $answer = Read-Host "Are you sure you want to proceed [y/n] -> Install '$($h.Name)'"

    if ($answer -eq 'y') {
        Invoke-Expression $h.Value
        Write-Host ""
    }
}
