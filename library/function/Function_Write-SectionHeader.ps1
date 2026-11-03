function Write-SectionHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [ConsoleColor]$Color = [ConsoleColor]::DarkGray,

        [ValidateRange(24, 120)]
        [int]$Width = 64
    )

    $text = $Title
    $line = ("=" * $Width)

    Write-Host
    Write-Host $line -ForegroundColor DarkGray
    Write-Host $text -ForegroundColor $Color
    Write-Host $line -ForegroundColor DarkGray
    Write-Host
}