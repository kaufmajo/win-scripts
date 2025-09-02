wt -p "PowerShell" -d "." `
`; split-pane -V -p "PowerShell" -d ".\log\" -- pwsh -NoExit -Command "Get-Content -Path .\stdout.log -Wait" `
`; move-focus right `; split-pane -H -p "PowerShell" -d ".\log\"  -- pwsh -NoExit -Command "Get-Content -Path .\stderr.log -Wait" `
`; move-focus down `; split-pane -H -p "PowerShell" -d ".\log\"  -- pwsh -NoExit -Command "Get-Content -Path .\stdout_evaluated.log -Wait" `
`; move-focus down `; split-pane -H -p "PowerShell" -d ".\log\"  -- pwsh -NoExit -Command "Get-Content -Path .\stderr_evaluated.log -Wait" `
