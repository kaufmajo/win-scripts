# win-scripts

PowerShell helpers for Windows setup, access, and backup.

## Scripts at a Glance

| Script                       | Description                                                                       |
| ---------------------------- | --------------------------------------------------------------------------------- |
| Backup.ps1                   | Runs backup and optional timeline, Hyper-V, and WSL export tasks from XML config. |
| Enable-BitlockerDrive.ps1    | Unlocks configured BitLocker drives using environment-based secrets.              |
| Enable-NetworkForwarding.ps1 | Checks and enables IPv4 forwarding on configured interfaces.                      |
| Install-Software.ps1         | Interactive winget installer for common development and desktop tools.            |
| Install-SshAccess.ps1        | Adds your local SSH public key to remote hosts listed in config.                  |
| Open-Browser.ps1             | Opens a selected site from JSON config with a filterable terminal menu.           |
| Start-Terminal.ps1           | Runs preconfigured terminal commands from JSON via interactive selection.         |
