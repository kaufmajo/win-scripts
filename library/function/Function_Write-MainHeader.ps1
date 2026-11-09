# One line: cyan title, gray subtitle.
#   Backup Script (Win)  Version 1.0
function Write-MainHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Subtitle,

        [ConsoleColor]$AccentColor = [ConsoleColor]::Cyan
    )

    Write-Host
    Write-Host $Title -ForegroundColor $AccentColor -NoNewline
    Write-Host "  $Subtitle" -ForegroundColor DarkGray
}
