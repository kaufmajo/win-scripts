function Wait-ForInput {

  param(
    [Parameter(Mandatory = $false)]
    [string] $Message = "",

    [Parameter(Mandatory = $false)]
    [string] $ForegroundColor = "White",

    [Parameter(Mandatory = $false)]
    [int] $Timeout = 10,

    [Parameter(Mandatory = $false)]
    [string] $DefaultValue = ""
  )
  
  # Write prompt without newline
  Write-Host "$Message (Timeout in $($Timeout)Sec)" -ForegroundColor $ForegroundColor -NoNewline

  # Read characters until Enter or timeout
  $sb = [System.Text.StringBuilder]::new()
  $deadline = [DateTime]::UtcNow.AddSeconds($Timeout)

  while ([DateTime]::UtcNow -lt $deadline) {

    if ([Console]::KeyAvailable) {
      
      $deadline = [DateTime]::UtcNow.AddMinutes(10) # extend deadline to avoid timeout during input
      $key = [Console]::ReadKey($true)

      switch ($key.Key) {
        'Enter' {
          # finish input
          Write-Host ""  # newline
          return ($sb.Length -eq 0) ? $DefaultValue : $sb.ToString()
        }
        'Backspace' {
          if ($sb.Length -gt 0) {
            $sb.Length -= 1
            # erase one char visually
            Write-Host "`b `b" -NoNewline
          }
        }
        default {
          # append printable characters
          if ($key.KeyChar -ne [char]0) {
            [void]$sb.Append($key.KeyChar)
            Write-Host -NoNewline $key.KeyChar
          }
        }
      }
    }
    else {
      Start-Sleep -Milliseconds 50
    }
  }

  # timed out
  Write-Host ""  # move to next line for cleanliness
  Write-Host "No input received within $Timeout seconds, proceeding..." -ForegroundColor Yellow
  return $DefaultValue
}

#Wait-ForInput -Message "Function Wait-ForInput loaded." -ForegroundColor Green -Timeout 10
