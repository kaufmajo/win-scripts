# Win scripts

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
| [Streamline-Bilderpool.ps1](#streamline-bilderpoolps1) | Interactively organize images and videos by capture year and folder description. |

## Streamline-Bilderpool.ps1

Reads metadata with ExifTool and proposes moves from `D:\__Master\Bilderpool`
to `D:\__Master\Bilderpool_Streamlined`. Requires PowerShell 7 and ExifTool.
Keep the `library` folder alongside the script for its shared console headers.
The default ExifTool path is configured in the script's parameter block; override
it with `-ExifToolPath` if needed.

All user settings are grouped in the `USER SETTINGS` parameter block at the top:
paths, maximum description length, accepted year range, and supported image/video
extensions. Edit the defaults there or override them with command-line parameters.
Filesystem safety limits and journal filenames are internal, not user settings.

```powershell
.\Streamline-Bilderpool.ps1          # Preview only
.\Streamline-Bilderpool.ps1 -Apply   # Move approved files
```

For each source folder, accept or edit its suggested description, choose no
description, skip (the default), or quit. Subfolders get their own prompt.
Folder approval shows a sample filename with a provisional ID (and `unknown` as a
placeholder if its year has not yet been chosen). Sidecars (`.xmp`, `.aae`, `.thm`,
`.lrv`) stay in the source; media matching their basename or full filename
(for example `IMG_1234.xmp` or `IMG_1234.JPG.xmp`) is also skipped.
All members of matching image/video basename groups (possibly Live Photos) are
skipped too. They remain untouched for later review, even if a year is supplied.
Other media in the folder is processed normally.
Files are placed in flat folders such as `2023_urlaub_muenchen`, with lowercase
names such as `image_000000123_2023-08-14_15-32-07__dir_urlaub_muenchen__orig_img_4321.jpg`.
Videos use `video_` and share the same ID sequence. No description means a
year-only folder and no description in the filename.

`__dir_` marks the folder description; `__orig_` marks the original basename.
Sanitized content contains no double underscores, so the sections can be removed
unambiguously later while keeping the extension. Absent sections have no marker.
Destination folder names remain unchanged (for example `2023_urlaub_muenchen`).

The sanitized original filename (without its extension) is appended before the
extension. The entire original-name suffix, including `__orig_`, is omitted if it would exceed 255 UTF-8
bytes per filename (common Linux filesystem limit) or 259 characters for the full
Windows path. These conservative Windows limits work without enabling long paths;
destination directories are also limited to 247 characters. If the computed name
without that suffix still exceeds the limits, the file stays untouched with an
explanation. Moving the collection under a longer root later may exceed path limits.

Embedded capture dates take priority. After approving a folder, choose once for
all its readable undated media: `[Y] Enter year`, `[U] Unknown folder`, or
`[S] Skip until next run` (the default on Enter). Choose `Y` to enter a year
(by default, 1800 through next year; configurable with `-MinimumYear` and
`-MaximumYear`); Enter at the year prompt also skips. A supplied year appears
alone in the filename, without an invented capture time. `unknown` uses a shared
destination folder named `unknown` and the filename date section `unknown`,
retaining any approved description and original-name sections. Skipped files stay
in the source and prompt again next run. Preview decisions are not saved.
Year marker files such as `_year_2018.txt` are no longer read.
Filesystem dates and ambiguous video timestamps are not used; timezone-qualified
video creation dates retain their recorded local time.

Normal runs display file details with blue labels for videos, default labels for
images, yellow skip reasons, and red failure reasons. Use `-PassThru` to return
structured result objects instead of displaying those details. Headers, prompts
and summaries remain console output and are not included in CSV exports.

Preview creates no files or folders. Export its results if desired:

```powershell
.\Streamline-Bilderpool.ps1 -PassThru | Export-Csv C:\Temp\bilderpool-preview.csv
```

`-Apply` requires separate, non-nested folders on the same local drive.
Existing destination files are never overwritten. The destination contains
`_streamline-journal.csv` for traceability and interrupted-run recovery, plus a
lock file preventing simultaneous apply runs. Keep these files. Repeat runs
process only media remaining in the source and continue the numeric sequence.
Unreadable media, unsupported files (including XMP sidecars and old year markers) and
empty folders stay in place. Metadata is never modified.
An unreadable/locked source encountered during hashing is reported as failed and
left untouched; processing continues with the next file. Journal errors still
stop the run. A console-only final summary shows previewed, moved, skipped, failed,
and not-processed totals plus journal location, including when you choose Quit.

**Keep a backup before moving originals.** Try a small copied sample first:

```powershell
.\Streamline-Bilderpool.ps1 -SourcePath C:\Temp\Pictures-Test -DestinationPath C:\Temp\Pictures-Result
```

The isolated synthetic-file checks do not access the picture collection:

```powershell
.\tests\Streamline-Bilderpool.Tests.ps1 -ExifToolPath 'C:\Tools\exiftool.exe'
```

## Backup.ps1

Reads [config/backup.xml](config/backup.xml) and mirrors the Windows root folder
to the available master and slave backup drives. Files inside WSL are backed up
by `backup.sh` from the [linux-scripts](https://github.com/kaufmajo/linux-scripts)
repository; start it afterwards with `-WithLinux`. The other way round,
`backup.sh --with-windows` starts this script afterwards.

Layout on each backup drive (`targetFolder` is `win` in the default config):

```text
X:\<COMPUTERNAME>\<targetFolder>\<USERNAME>\            mirror
X:\<COMPUTERNAME>\<targetFolder>\<USERNAME>.history\    history: old versions of changed and deleted files
```

**Run with the default configuration:**

```powershell
.\Backup.ps1
```

**Run the WSL backup afterwards:**

```powershell
.\Backup.ps1 -WithLinux
```

**Choose another configuration and skip the history:**

```powershell
.\Backup.ps1 -ConfigFile '.\config\backup.xml' -SkipHistory
```

| Option | Effect |
| --- | --- |
| `-ConfigFile <path>` | Use another XML configuration file. |
| `-ExportHyperV` | Export the configured Hyper-V virtual machines. |
| `-ExportWsl` | Export the configured WSL distributions to `<name>.tar`. |
| `-SkipHistory` | Do not move old versions to the history folder. |
| `-WithLinux` | Run the WSL backup script (`<linux>` in the XML) afterwards. |

**Before running:**

- Check source paths, destination drive letters, and volume labels in the XML.
- Config files outside the root folder (`<config>` paths) are copied into
  `configFolder` first, keeping the full path
  (`C:\Users\me\.gitconfig` becomes `___Config\C\Users\me\.gitconfig`). Only
  new and changed files are copied and listed. Copies whose source no longer
  exists or whose path was removed from the XML are deleted (their old version
  goes to the history), so the folder must be a subfolder of the root folder
  and not contain anything else. Nothing is ever copied back.
- Mirroring uses `robocopy /MIR`, which deletes destination files that no longer
  exist in the source. Before that, their old versions are moved to the history
  folder. The newest `historyKeep` history folders are kept per drive.
- BitLocker drives are unlocked only when they are locked; this asks for
  administrator access (UAC).
- If a configured drive is not found, the script asks for its drive letter and
  continues without that drive after 10 seconds without input.
- Hyper-V exports require the Hyper-V tools and appropriate permissions. Each
  export replaces only the previous export of the same VM or distribution.
- Run `-ExportWsl` from Windows, not via `backup.sh --with-windows`: it would
  export the distribution the calling script is running in.

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
