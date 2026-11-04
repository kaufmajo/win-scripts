# Blue marker and title (like Homebrew), optional detail (e.g. a path) on the
# next line:
#   ==> Backup
#       D:\host\win\user\
function Write-SectionHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [string]$Detail,

        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    Write-Host
    Write-Host "==> " -ForegroundColor Blue -NoNewline
    Write-Host $Title -ForegroundColor $Color
    if ($Detail) {
        Write-Host "    $Detail"
    }
}
