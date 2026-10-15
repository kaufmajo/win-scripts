# win-scripts

PowerShell helpers for Windows setup, access, and backup.

## Before You Start

Run the examples from this repository's root folder in PowerShell. Use PowerShell
7 (`pwsh`); for `Backup.ps1`, use version 7.4 or later. Keep the `library` and
`config` folders alongside the scripts, since several scripts load helpers and
settings from them.

Configuration paths, drive letters, and host names need to match your own setup.
In the paths below, `~` means your user profile directory, usually `C:\Users\<username>`.

## Scripts at a Glance

| Script | Purpose |
| --- | --- |
| [Backup.ps1](#backupps1) | Mirror files to backup drives and optionally export Hyper-V and WSL data. |
| [Deploy-AiInstructions.ps1](#deploy-aiinstructionsps1) | Deploy shared user instructions for Codex, Copilot CLI, and Claude Code. |
| [Deploy-AiSkills.ps1](#deploy-aiskillsps1) | Deploy personal skills for Codex, Copilot, and Claude Code. |
| [Enable-BitlockerDrive.ps1](#enable-bitlockerdriveps1) | Unlock BitLocker drives using passwords from environment variables. |
| [Enable-NetworkForwarding.ps1](#enable-networkforwardingps1) | Enable IPv4 forwarding on configured network interfaces. |
| [Install-Software.ps1](#install-softwareps1) | Choose software to install using winget. |
| [Install-SshAccess.ps1](#install-sshaccessps1) | Add your local SSH public key to configured remote hosts. |
| [Open-Browser.ps1](#open-browserps1) | Open a URL directly or choose a site from a searchable menu. |
| [Start-Terminal.ps1](#start-terminalps1) | Choose and run a configured terminal command. |

## Backup.ps1

Reads [config/backup.xml](config/backup.xml) and mirrors the configured root folder
to the available master and slave backup drives. Timeline snapshots are enabled
by default.

**Run with the default configuration:**

```powershell
.\Backup.ps1
```

**Include the extra backup and configuration jobs:**

```powershell
.\Backup.ps1 -IncludeBackup -IncludeConfig
```

**Choose another configuration and skip timeline processing:**

```powershell
.\Backup.ps1 -ConfigFile '.\config\backup.xml' -SkipTimeline
```

| Option | Effect |
| --- | --- |
| `-ConfigFile <path>` | Use another XML configuration file. |
| `-IncludeBackup` | Include configured jobs with type `backup`. |
| `-IncludeConfig` | Include configured jobs with type `config`. |
| `-IncludeHyperV` | Export the configured Hyper-V virtual machines. |
| `-IncludeWsl` | Export the configured WSL distributions. |
| `-SkipTimeline` | Skip both timeline cleanup and snapshot creation. |

**Before running:**

- Check source paths, destination drive letters, and volume labels in the XML.
  The main drive mirrors run even without `-IncludeBackup`.
- Mirroring uses `robocopy /MIR`, which can delete destination files that no
  longer exist in the source.
- Timeline cleanup keeps the 30 newest existing folders before creating the next
  snapshot. Hyper-V and WSL export steps clear their configured export folders
  before each job; use dedicated export folders.
- Hyper-V exports require the Hyper-V tools and appropriate permissions. Rsync
  jobs require WSL with `rsync`. Configured BitLocker and network setup steps
  request administrator access.

## Deploy-AiInstructions.ps1

Copies [samples/ai-instructions.md](samples/ai-instructions.md) to the user-level
instruction files for all three assistants.

**Preview the destinations:**

```powershell
.\Deploy-AiInstructions.ps1 -WhatIf
```

**Deploy the instructions:**

```powershell
.\Deploy-AiInstructions.ps1
```

**Use another source file:**

```powershell
.\Deploy-AiInstructions.ps1 -SourceFile '.\samples\ai-instructions.md'
```

| Assistant | Default destination |
| --- | --- |
| Codex | `~/.codex/AGENTS.md` |
| GitHub Copilot CLI | `~/.copilot/copilot-instructions.md` |
| Claude Code | `~/.claude/CLAUDE.md` |

Existing files are replaced, with timestamped `.bak` copies saved beside them.
Identical files are skipped. Keep your maintained version in the source file;
edits made directly to deployed files will be overwritten on the next deployment.

Use `-UserProfilePath <path>` to target a different profile. Otherwise,
`COPILOT_HOME` and `CODEX_HOME` override their respective default directories.
The Claude destination in this script is always under the selected profile's
`.claude` directory. The Copilot instruction destination applies to Copilot CLI;
other Copilot environments may use different instruction settings.

## Deploy-AiSkills.ps1

Installs the skills maintained in [samples/skills](samples/skills) for use across
your projects. Each skill has its own folder containing `SKILL.md` and any
supporting files.

**Preview the deployment:**

```powershell
.\Deploy-AiSkills.ps1 -WhatIf
```

**Deploy all source skills:**

```powershell
.\Deploy-AiSkills.ps1
```

**Deploy only the mentoring skill:**

```powershell
.\Deploy-AiSkills.ps1 -SkillName code-mentor
```

| Assistants | Default destination |
| --- | --- |
| Codex and GitHub Copilot | `~/.agents/skills/<skill-name>/` |
| Claude Code | `~/.claude/skills/<skill-name>/` |

**What happens when you redeploy:**

- Identical skills are skipped.
- Changed skills are replaced as complete folders. Files and subfolders removed
  from the source do not remain in the installed copy.
- Previous versions are retained under `~/.ai-skill-backups`, outside the skill
  discovery folders. The script prints each backup location.
- Other installed skills remain untouched. Removing an entire skill from
  `samples/skills` does not uninstall its global copies.

Use `-SourceDirectory <path>` for a different collection, or `-UserProfilePath <path>`
for a different profile. When no profile is supplied, `CLAUDE_CONFIG_DIR` can
override Claude's directory. Linked files and directories are rejected.

The included `code-mentor` skill requires explicit invocation. After deployment,
use one of these prompts in your assistant's chat:

**Codex:**

```text
$code-mentor Help me understand the bug fix in this PR.
```

**Claude Code or Copilot:**

```text
/code-mentor Help me understand this security finding.
```

## Enable-BitlockerDrive.ps1

Unlocks one or two existing BitLocker-protected drives. Despite its name, this
script does not turn on encryption.

**Unlock one drive using a named password environment variable:**

```powershell
.\Enable-BitlockerDrive.ps1 -MasterDriveLetter E -MasterDriveEnvvar BACKUP_DRIVE_PASSWORD
```

**Unlock two drives:**

```powershell
$driveOptions = @{
    MasterDriveLetter = 'E'
    MasterDriveEnvvar = 'BACKUP_MASTER_PASSWORD'
    SlaveDriveLetter  = 'F'
    SlaveDriveEnvvar  = 'BACKUP_SLAVE_PASSWORD'
}

.\Enable-BitlockerDrive.ps1 @driveOptions
```

Replace the example letters and environment variable names with your own.
Supply drive letters without a colon. The script loads `config/.env`; the named
variables must contain the BitLocker passwords, not recovery keys. Keep that
file private and out of version control.

BitLocker cmdlets must be available. The script requests administrator access
and skips drives that are already unlocked.

## Enable-NetworkForwarding.ps1

Enables IPv4 forwarding on the interface aliases listed in
[config/network.xml](config/network.xml).

```powershell
.\Enable-NetworkForwarding.ps1
```

Check the interface aliases in the XML before running. The script requests
administrator access and changes Windows network settings; already enabled
interfaces are left as they are.

When started without administrator rights, it first runs
`wsl -d Debian hostname -i` to activate/check the WSL network. That step assumes
a WSL distribution named `Debian`. There are no script-specific parameters.

## Install-Software.ps1

Offers an interactive list of applications to install with winget.

**Open PowerShell as administrator, then run:**

```powershell
.\Install-Software.ps1
```

The script requires `winget` and exits if the shell is not elevated. It first
asks whether to change PowerShell's execution policy to `RemoteSigned`, then
asks about each application. Type `yes` to accept a prompt; other answers skip it.

The application list is defined in the script's `$winget` collection. Review it
before starting if you want to change the choices. There are no script-specific
parameters.

## Install-SshAccess.ps1

Adds your Windows user's `~/.ssh/id_ed25519.pub` public key to the remote accounts
listed in [config/sshsetup.xml](config/sshsetup.xml).

```powershell
.\Install-SshAccess.ps1
```

**Before running:**

- Make sure the public key exists and the Windows `ssh` command is available.
- Review the host/account entries in the XML. Jobs marked `done=true` are skipped.
- You must already be able to authenticate to each remote account, for example
  using its password. Remote hosts need a shell with `mkdir` and `chmod`.

The script offers optional local elevation and asks for confirmation for each
host. It appends the key to `~/.ssh/authorized_keys` without checking for
duplicates, and does not mark completed jobs as done in the XML. Update those
flags yourself to avoid repeating setup. WSL has its own keys and needs separate
setup. There are no script-specific parameters.

## Open-Browser.ps1

Opens a site from [config/open-browser.json](config/open-browser.json), or opens
a URL supplied on the command line.

**Browse the site menu:**

```powershell
.\Open-Browser.ps1
```

**Open a URL directly:**

```powershell
.\Open-Browser.ps1 'https://github.com'
```

You can also use the named parameter:

```powershell
.\Open-Browser.ps1 -openUrl 'github.com'
```

Addresses without a scheme receive an `https://` prefix. The JSON configuration
must exist and contain at least one site, even when opening a URL directly.

In the menu, type to filter, use **Up/Down** to choose, **Enter** to open, and
**Esc** to cancel. **Backspace** removes a character; **Delete** clears the filter.
Filters support regular expressions, with spaces and dots acting as wildcards.
Search-enabled sites prompt for a search term, and the `Custom` entry prompts for
a URL. Links open through Windows' default URL handler.

## Start-Terminal.ps1

Displays commands from [config/start-terminal.json](config/start-terminal.json)
and runs the one you select.

```powershell
.\Start-Terminal.ps1
```

Type to filter, use **Up/Down** to choose, **Enter** to run, and **Esc** to cancel.
**Backspace** removes a character; **Delete** clears the filter. The selected
command is shown beneath the list before you run it.

Filters support regular expressions. Space-separated terms can match in any
order; dots act as wildcards within a term.

Review the JSON commands before using the menu: selecting an entry executes its
configured command. Required applications and any absolute executable paths must
exist on your machine. Windows Terminal (`wt`) is needed for entries that call it.
There are no script-specific parameters.
