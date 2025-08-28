# Get current working directory
$baseDirectory = split-path $MyInvocation.MyCommand.Path

# Path to the .env file
$envFilePath = "$($baseDirectory)\..\..\config\.env"

# Read the .env file and process each line
Get-Content $envFilePath | ForEach-Object {
    # Skip empty lines and comments
    if ($_ -and $_ -notmatch '^\s*#') {
        # Split on the first '='
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) {
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            # Set environment variable in current session
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

# View loaded environment variables
# Get-ChildItem Env: