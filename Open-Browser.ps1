# ---------------------------------------------------
# Function: Show-Menu
# Description: Displays an interactive menu in the console for user selection.

function Show-Menu {
    
    param(
        [string] $Title,
        [object[]] $Options
    )

    $index = 0
    
    while ($true) {
        
        Clear-Host
        
        Write-Host $Title
        Write-Host "Use ↑ ↓ to navigate, Enter to select.`n"

        for ($i = 0; $i -lt $Options.Count; $i++) {

            $site = $Options[$i]["site"]

            if ($i -eq $index) {
                Write-Host " > $($site)" -ForegroundColor Cyan
            }
            else {
                Write-Host "   $($site)"
            }
        }

        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode

        switch ($key) {
            
            38 { if ($index -gt 0) { $index-- } } # Up arrow
            40 { if ($index -lt ($Options.Count - 1)) { $index++ } } # Down arrow
            13 { return $Options[$index] } # Enter key
        }
    }
}

# ---------------------------------------------------
# Main Script

$sites = @(
    @{site = "Custom"; query = "" },
    @{site = "https://www.google.com"; query = "/search?q=" },
    @{site = "https://www.bing.com"; query = "/search?q=" }
)

$site = Show-Menu -Title "Please select a site:" -Options $sites

Write-Host

# ---------------------------------------------------
# Handle Custom URL case

if ( $site.site -eq "Custom" ) {

    $customUrl = Read-Host "Custom URL"
    
    if (![string]::IsNullOrWhiteSpace($customUrl)) {
        Write-Host "`nYou selected: $customUrl`n"
        Start-Process microsoft-edge:"https://$customUrl"
        exit
    }
}

# ---------------------------------------------------
# Handle Search Query case

$url = $site.site

if ($site.query -ne "") {

    $searchTerm = Read-Host "Search term"
    
    if (![string]::IsNullOrWhiteSpace($searchTerm)) {
        $encodedTerm = [System.Web.HttpUtility]::UrlEncode($searchTerm)
        $url = "$($url)$($site.query)$encodedTerm"
    }
}

Write-Host "`nYou selected: $($url)`n"

Start-Process microsoft-edge:$url

exit