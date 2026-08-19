# ---------------------------------------------------
# Script Parameters

param(
    [Parameter(Position = 0)] [string] $openUrl
)

# ---------------------------------------------------
# Site Definitions

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$jsonPath = Join-Path -Path $scriptDir -ChildPath 'config/open-browser.json'

if (-not (Test-Path -LiteralPath $jsonPath)) {
    Write-Error "Site config file not found: $jsonPath"
    exit 1
}

try {
    $json = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Could not read JSON site config file: $($_.Exception.Message)"
    exit 1
}

$sites = @(
    $json.PSObject.Properties | ForEach-Object {
        @{ site = $_.Name; query = [string]$_.Value }
    }
)

if ($sites.Count -eq 0) {
    Write-Error "No sites found in $jsonPath"
    exit 1
}

# ---------------------------------------------------
# Function: Show-Menu
# Description: Displays an interactive menu in the console for user selection.
#              Supports typing characters to filter entries by regex (spaces/dots match anything between parts).

function ConvertTo-FlexibleRegexPattern {
    param([string]$Pattern)

    return ($Pattern.Trim() -replace '[\s.]+', '.*')
}

function Get-MatchingMenuOptions {
    param(
        [object[]]$Options,
        [string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        return [pscustomobject]@{
            Options = @($Options)
            Error   = $null
        }
    }

    $flexiblePattern = ConvertTo-FlexibleRegexPattern -Pattern $Pattern

    try {
        [regex]::new($flexiblePattern) | Out-Null

        return [pscustomobject]@{
            Options = @($Options | Where-Object { $_["site"] -match $flexiblePattern })
            Error   = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Options = @()
            Error   = $_.Exception.Message
        }
    }
}

function Show-Menu {
    param(
        [Parameter(Mandatory)]
        [string]  $Title,
        [Parameter(Mandatory)]
        [object[]] $Options
    )

    $index = 0
    $pattern = ''

    while ($true) {

        $result = Get-MatchingMenuOptions -Options $Options -Pattern $pattern
        $matchingOptions = @($result.Options)

        if ($matchingOptions.Count -eq 0) {
            $index = 0
        }
        elseif ($index -ge $matchingOptions.Count) {
            $index = $matchingOptions.Count - 1
        }

        Clear-Host
        Write-Host $Title
        Write-Host "Type to filter, Up/Down to navigate, Enter to select, Esc to cancel."
        Write-Host

        Write-Host -NoNewline "Filter: "
        if ([string]::IsNullOrEmpty($pattern)) {
            Write-Host "<all>" -ForegroundColor DarkGray
        }
        else {
            Write-Host $pattern -ForegroundColor Yellow
        }

        if ($result.Error) {
            Write-Host "Invalid regex: $($result.Error)" -ForegroundColor Red
        }
        elseif ($matchingOptions.Count -eq 0) {
            Write-Host "No matching entries." -ForegroundColor Red
        }

        Write-Host

        for ($i = 0; $i -lt $matchingOptions.Count; $i++) {
            $site = $matchingOptions[$i]["site"]
            if ($i -eq $index) {
                Write-Host (" > {0}" -f $site) -ForegroundColor Cyan
            }
            else {
                Write-Host ("   {0}" -f $site)
            }
        }

        $keyInfo = [Console]::ReadKey($true)

        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($matchingOptions.Count -gt 0) {
                    $index = if ($index -gt 0) { $index - 1 } else { $matchingOptions.Count - 1 }
                }
            }
            'DownArrow' {
                if ($matchingOptions.Count -gt 0) {
                    $index = if ($index -lt $matchingOptions.Count - 1) { $index + 1 } else { 0 }
                }
            }
            'Enter' {
                if ($matchingOptions.Count -gt 0 -and -not $result.Error) {
                    return $matchingOptions[$index]
                }
            }
            'Escape' { return $null }
            'Backspace' {
                if ($pattern.Length -gt 0) {
                    $pattern = $pattern.Substring(0, $pattern.Length - 1)
                    $index = 0
                }
            }
            'Delete' {
                $pattern = ''
                $index = 0
            }
            default {
                if (-not [char]::IsControl($keyInfo.KeyChar)) {
                    $pattern += [string]$keyInfo.KeyChar
                    $index = 0
                }
            }
        }
    }
}

# ---------------------------------------------------
# Helpers

function Resolve-Url {

    param([Parameter(Mandatory)][string] $UrlOrHost)

    if ($UrlOrHost -match '^[a-zA-Z][a-zA-Z0-9+\-.]*://') { $UrlOrHost } else { "https://$UrlOrHost" }
}

function Open-Url {

    param([Parameter(Mandatory)][string] $Url, [switch] $PreferEdge)

    try {
        
        if ($PreferEdge) {
            $edge = Get-Command msedge.exe -ErrorAction SilentlyContinue
            if ($edge) { Start-Process -FilePath $edge.Source -ArgumentList $Url; return }
        }

        Start-Process $Url
    }
    catch {

        Write-Warning "Failed to open URL: $Url"
        Write-Warning $_.Exception.Message
    }
}

# ---------------------------------------------------
# Open URL directly if provided

if ([string]::IsNullOrWhiteSpace($openUrl) -eq $false) {

    $finalUrl = Resolve-Url -UrlOrHost $openUrl.Trim()

    Write-Host
    Write-Host "Opening URL: $finalUrl"
    Write-Host

    Open-Url -Url $finalUrl  # add -PreferEdge if you want to force Edge

    exit
}

# ---------------------------------------------------
# Show menu and get selection

$site = Show-Menu -Title "Please select a site:" -Options $sites

Write-Host

if (-not $site) {

    Write-Host "Cancelled."
    exit
}

# ---------------------------------------------------
# Handle Custom URL case

if ($site.site -eq "Custom") {

    $customUrl = Read-Host "URL"

    if (![string]::IsNullOrWhiteSpace($customUrl)) {

        $finalUrl = Resolve-Url -UrlOrHost $customUrl.Trim()
        
        Write-Host
        Write-Host "You selected: $finalUrl"
        Write-Host

        Open-Url -Url $finalUrl  # add -PreferEdge if you want to force Edge

        exit

    }
    else {

        Write-Host
        Write-Host "No URL entered. Exiting."
        Write-Host
        
        exit
    }
}

# ---------------------------------------------------
# Handle selected URL case

$url = $site.site

if ($site.query -ne "") {
    
    $searchTerm = Read-Host "Search"
    
    if (![string]::IsNullOrWhiteSpace($searchTerm)) {
    
        $encoded = [Uri]::EscapeDataString($searchTerm)
        $url = "{0}{1}{2}" -f $url, $site.query, $encoded
    }
}

Write-Host
Write-Host "You selected: $url"
Write-Host

Open-Url -Url $url  # add -PreferEdge if you want to force Edge

exit
