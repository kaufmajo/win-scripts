# ---------------------------------------------------
# Function: Show-Menu
# Description: Displays an interactive menu in the console for user selection.

function Show-Menu {
    param(
        [Parameter(Mandatory)]
        [string]  $Title,
        [Parameter(Mandatory)]
        [object[]] $Options
    )

    $index = 0

    while ($true) {

        Clear-Host
        Write-Host $Title
        Write-Host "Use up-down to navigate, Enter to select, Esc to cancel."
        Write-Host

        for ($i = 0; $i -lt $Options.Count; $i++) {
            $site = $Options[$i]["site"]
            if ($i -eq $index) {
                Write-Host (" > {0}" -f $site) -ForegroundColor Cyan
            }
            else {
                Write-Host ("   {0}" -f $site)
            }
        }

        $keyInfo = [Console]::ReadKey($true)

        switch ($keyInfo.Key) {
            'UpArrow' { $index = if ($index -gt 0) { $index - 1 } else { $Options.Count - 1 } }
            'DownArrow' { $index = if ($index -lt $Options.Count - 1) { $index + 1 } else { 0 } }
            'Enter' { return $Options[$index] }
            'Escape' { return $null }
        }
    }
} # <— schließende Klammer der Funktion

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
# Main Script

$sites = @(
    @{ site = "Custom"; query = "" },
    @{ site = "https://www.google.com"; query = "/search?q=" },
    @{ site = "https://www.bing.com"; query = "/search?q=" },
    @{ site = "https://chatgpt.com"; query = "" }
)

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

        $final = Resolve-Url -UrlOrHost $customUrl.Trim()
        Write-Host
        Write-Host "You selected: $final"
        Write-Host
        Open-Url -Url $final  # add -PreferEdge if you want to force Edge

        exit

    }
    else {
        
        Write-Host "No URL entered. Exiting."
        
        exit
    }
}

# ---------------------------------------------------
# Handle Search Query case

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
