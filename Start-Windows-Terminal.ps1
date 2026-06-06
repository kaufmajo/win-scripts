# ----------------------------------------------------------
# INIT
# ----------------------------------------------------------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$jsonPath = Join-Path -Path $scriptDir -ChildPath 'Start-Windows-Terminal.json'

$pattern = ''
$selectedIndex = 0

if (-not (Test-Path -LiteralPath $jsonPath)) {
    Write-Error "Command file not found: $jsonPath"
    exit 1
}

try {
    $json = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Could not read JSON command file: $($_.Exception.Message)"
    exit 1
}

$commands = @(
    $json.PSObject.Properties |
    ForEach-Object {
        [pscustomobject]@{
            Key     = $_.Name
            Command = [string]$_.Value
        }
    }
)

if ($commands.Count -eq 0) {
    Write-Error "No commands found in $jsonPath"
    exit 1
}

# ----------------------------------------------------------
# FUNCTIONS
# ----------------------------------------------------------

function ConvertTo-FlexibleRegexPattern {
    param([string]$Pattern)

    return ($Pattern.Trim() -replace '[\s.]+', '.*')
}

function Get-MatchingCommandItems {
    param(
        [object[]]$Items,
        [string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        return [pscustomobject]@{
            Items = @($Items)
            Error = $null
        }
    }

    $flexiblePattern = ConvertTo-FlexibleRegexPattern -Pattern $Pattern

    try {
        [regex]::new($flexiblePattern) | Out-Null

        return [pscustomobject]@{
            Items = @($Items | Where-Object { $_.Key -match $flexiblePattern })
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Items = @()
            Error = $_.Exception.Message
        }
    }
}

function Show-CommandMenu {
    param(
        [object[]]$Items,
        [string]$Pattern,
        [int]$SelectedIndex,
        [string]$ErrorMessage
    )

    Clear-Host
    Write-Host 'Windows Terminal commands' -ForegroundColor Cyan
    Write-Host 'Type a regex to filter. Spaces and dots match anything between parts. Use Up/Down to choose, Enter to run, Esc to exit.'
    Write-Host ''

    Write-Host -NoNewline 'Regex: '
    if ([string]::IsNullOrEmpty($Pattern)) {
        Write-Host '<all>' -ForegroundColor DarkGray
    }
    else {
        Write-Host $Pattern -ForegroundColor Yellow
    }

    if ($ErrorMessage) {
        Write-Host "Invalid regex: $ErrorMessage" -ForegroundColor Red
    }
    elseif ($Items.Count -eq 0) {
        Write-Host 'No matching commands.' -ForegroundColor Red
    }

    Write-Host ''

    $visibleRows = 12
    try {
        $visibleRows = [Math]::Max(1, [Console]::WindowHeight - 9)
    }
    catch {
        $visibleRows = 12
    }

    $start = 0
    if ($SelectedIndex -ge $visibleRows) {
        $start = $SelectedIndex - $visibleRows + 1
    }

    $end = [Math]::Min($Items.Count - 1, $start + $visibleRows - 1)
    for ($index = $start; $index -le $end; $index++) {
        $item = $Items[$index]
        $prefix = '  '
        $foreground = 'Gray'
        $background = $Host.UI.RawUI.BackgroundColor

        if ($index -eq $SelectedIndex) {
            $prefix = '> '
            $foreground = 'Black'
            $background = 'Gray'
        }

        Write-Host "$prefix$($item.Key)" -ForegroundColor $foreground -BackgroundColor $background
    }

    if ($Items.Count -gt 0) {
        Write-Host ''
        Write-Host 'Command:' -ForegroundColor DarkGray
        Write-Host $Items[$SelectedIndex].Command -ForegroundColor DarkGray
    }
}

function Invoke-SelectedCommand {
    param([string]$Command)

    $trimmedCommand = $Command.Trim()

    if ($trimmedCommand -match '^\s*(split-pane)\b') {
        Start-Process -FilePath 'wt' -ArgumentList "--window 0 $trimmedCommand"
        return 0
    }

    if ($trimmedCommand -match '^(?:"(?<QuotedExecutable>[a-zA-Z]:\\[^"]+?\.exe)"|(?<Executable>[a-zA-Z]:\\.*?\.exe))(?<Arguments>\s+.*)?$') {
        $executable = $Matches.QuotedExecutable
        if ([string]::IsNullOrWhiteSpace($executable)) {
            $executable = $Matches.Executable
        }

        if (-not (Test-Path -LiteralPath $executable)) {
            Write-Error "Executable not found: $executable"
            return 1
        }

        $arguments = ''
        if (-not [string]::IsNullOrWhiteSpace($Matches.Arguments)) {
            $arguments = $Matches.Arguments.Trim()
        }

        if ([string]::IsNullOrWhiteSpace($arguments)) {
            Start-Process -FilePath $executable
        }
        else {
            Start-Process -FilePath $executable -ArgumentList $arguments
        }

        return 0
    }

    $null = Invoke-Expression $trimmedCommand
    if ($null -eq $LASTEXITCODE) {
        return 0
    }

    return $LASTEXITCODE
}

# ----------------------------------------------------------
# MAIN LOOP
# ----------------------------------------------------------

while ($true) {
    
    $result = Get-MatchingCommandItems -Items $commands -Pattern $pattern
    $matchingCommandItems = @($result.Items)

    if ($matchingCommandItems.Count -eq 0) {
        
        $selectedIndex = 0
    }
    elseif ($selectedIndex -ge $matchingCommandItems.Count) {
        
        $selectedIndex = $matchingCommandItems.Count - 1
    }

    Show-CommandMenu -Items $matchingCommandItems -Pattern $pattern -SelectedIndex $selectedIndex -ErrorMessage $result.Error

    $key = [Console]::ReadKey($true)

    if ($key.Key -eq [ConsoleKey]::Escape) {

        Clear-Host
        exit 0
    }

    if ($key.Key -eq [ConsoleKey]::UpArrow) {
        
        if ($matchingCommandItems.Count -gt 0) {
            
            if ($selectedIndex -le 0) {
                $selectedIndex = $matchingCommandItems.Count - 1
            }
            else {
                $selectedIndex--
            }
        }

        continue
    }

    if ($key.Key -eq [ConsoleKey]::DownArrow) {
        
        if ($matchingCommandItems.Count -gt 0) {
            
            if ($selectedIndex -ge ($matchingCommandItems.Count - 1)) {
                $selectedIndex = 0
            }
            else {
                $selectedIndex++
            }
        }

        continue
    }

    if ($key.Key -eq [ConsoleKey]::Enter) {
        
        if ($matchingCommandItems.Count -gt 0 -and -not $result.Error) {
            
            $selected = $matchingCommandItems[$selectedIndex]
            Clear-Host
            Write-Host "Running: $($selected.Key)" -ForegroundColor Cyan
            $exitCode = Invoke-SelectedCommand -Command $selected.Command
            exit $exitCode
        }

        continue
    }

    if ($key.Key -eq [ConsoleKey]::Backspace) {
        
        if ($pattern.Length -gt 0) {
            $pattern = $pattern.Substring(0, $pattern.Length - 1)
            $selectedIndex = 0
        }

        continue
    }

    if ($key.Key -eq [ConsoleKey]::Delete) {
        
        $pattern = ''
        $selectedIndex = 0
        continue
    }

    if (-not [char]::IsControl($key.KeyChar)) {
        
        $pattern += [string]$key.KeyChar
        $selectedIndex = 0
    }
}
