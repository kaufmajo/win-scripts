function Write-MainHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Subtitle,

        [ConsoleColor]$AccentColor = [ConsoleColor]::Cyan,

        [ValidateRange(36, 120)]
        [int]$Width = 64
    )

    $innerWidth = $Width - 2
    $outerBorder = "//" + ("=" * ($Width - 2)) + "\\"
    $emptyLine = "| " + (" " * $innerWidth) + " |"
    $titleText = "[ $Title ]"
    $subtitleText = "< $Subtitle >"
    $titleLine = "| " + $titleText.PadLeft([Math]::Floor(($innerWidth + $titleText.Length) / 2)).PadRight($innerWidth) + " |"
    $subtitleLine = "| " + $subtitleText.PadLeft([Math]::Floor(($innerWidth + $subtitleText.Length) / 2)).PadRight($innerWidth) + " |"
    $footerBorder = "\\" + ("=" * ($Width - 2)) + "//"

    Write-Host
    Write-Host $outerBorder -ForegroundColor $AccentColor
    Write-Host $emptyLine -ForegroundColor $AccentColor
    Write-Host $titleLine -ForegroundColor $AccentColor
    Write-Host $subtitleLine -ForegroundColor $AccentColor
    Write-Host $emptyLine -ForegroundColor $AccentColor
    Write-Host $footerBorder -ForegroundColor $AccentColor
    Write-Host
}