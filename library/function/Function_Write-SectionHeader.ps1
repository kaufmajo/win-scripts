function Write-SectionHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [ConsoleColor]$Color = [ConsoleColor]::Cyan,

        [ValidateRange(24, 120)]
        [int]$Width = 64
    )

    $text = "[ $Title ]"
    $lineLength = [Math]::Max($text.Length + 2, $Width)
    $line = ("=" * $lineLength)

    Write-Host
    Write-Host $line -ForegroundColor DarkGray
    Write-Host $text -ForegroundColor $Color
    Write-Host $line -ForegroundColor DarkGray
    Write-Host
}