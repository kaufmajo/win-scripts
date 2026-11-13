#Requires -Version 7.0
<#
.SYNOPSIS
    Interactively organize images and videos into year-and-description folders.
.DESCRIPTION
    Preview is the default. Only -Apply moves files, on the same local drive.
    Each source folder is approved separately; subfolders get their own prompt.
    Metadata and media contents are never edited.
    The sanitized original basename is appended unless it exceeds the 255-byte
    filename or 259-character full-path limit. The extension is kept only once.
    Filename sections are marked with __dir_ and __orig_ for later removal.

    For undated media, enter a fallback year, choose unknown, or skip until the
    next run. The answer applies only to undated media directly in that folder.
    Override dates in the folder menu to ignore embedded dates for naming only.
    Ambiguous QuickTime timestamps and filesystem dates are not used.

    Unsupported files (including XMP sidecars) stay in place. Approved source
    subfolders are removed if empty after moving; the source root is always kept.
    Keep a backup before using -Apply. The destination journal
    records moves and supports interrupted-run recovery; it is not a backup.
.EXAMPLE
    .\Streamline-Bilderpool.ps1
.EXAMPLE
    .\Streamline-Bilderpool.ps1 -SourcePath C:\Test\Original -DestinationPath C:\Test\Streamlined -Apply
.EXAMPLE
    .\Streamline-Bilderpool.ps1 -PassThru | Export-Csv C:\Temp\preview.csv
#>
[CmdletBinding()]
# USER SETTINGS: edit these defaults here, or override them on the command line.
param (
    [ValidateNotNullOrEmpty()]
    [string]$SourcePath = 'D:\__Master\Bilderpool',

    [ValidateNotNullOrEmpty()]
    [string]$DestinationPath = 'D:\__Master\Bilderpool_Streamlined',

    [ValidateNotNullOrEmpty()]
    [string]$ExifToolPath = 'C:\Users\joachim.kaufmann\Joachim\___Applikation\exiftool-13.63_64\exiftool.exe',

    # Maximum length of the sanitized folder description.
    [ValidateRange(1, 80)]
    [int]$DescriptionMaxLength = 80,

    [ValidateRange(1, 9999)]
    [int]$MinimumYear = 1800,

    [ValidateRange(1, 9999)]
    [int]$MaximumYear = ((Get-Date).Year + 1),

    # Include the leading dot; use lowercase extensions.
    [string[]]$ImageExtensions = @(
        '.jpg', '.jpeg', '.heic', '.heif', '.png', '.tif', '.tiff', '.webp',
        '.gif', '.bmp', '.avif', '.dng', '.cr2', '.cr3', '.nef', '.arw', '.orf', '.rw2', '.raf'
    ),

    [string[]]$VideoExtensions = @(
        '.mov', '.mp4', '.m4v', '.avi', '.mts', '.m2ts', '.3gp', '.mkv', '.wmv'
    ),

    # Leave disabled for preview. Prefer passing -Apply explicitly when ready.
    [switch]$Apply,

    # Return result objects instead of displaying colored file details.
    [switch]$PassThru
)

# IMPLEMENTATION: normal configuration changes belong in the settings above.
$ErrorActionPreference = 'Stop'
if ($MinimumYear -gt $MaximumYear) { throw 'MinimumYear must not exceed MaximumYear.' }

. "$PSScriptRoot\library\function\Function_Write-MainHeader.ps1"
. "$PSScriptRoot\library\function\Function_Write-SectionHeader.ps1"

function Test-WithinPath {
    param ([string]$Path, [string]$Parent)
    $Path.Equals($Parent, [StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith("$($Parent.TrimEnd('\'))\", [StringComparison]::OrdinalIgnoreCase)
}

function Assert-UnlinkedPath {
    param ([string]$Path)
    $current = $Path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked files, folders and mount points are not supported: $current"
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function ConvertTo-SafeName {
    param ([string]$Text, [int]$MaxLength = $DescriptionMaxLength)
    foreach ($pair in @(
        @('ä', 'ae'), @('ö', 'oe'), @('ü', 'ue'),
        @('Ä', 'Ae'), @('Ö', 'Oe'), @('Ü', 'Ue'), @('ß', 'ss'), @('ẞ', 'ss')
    )) {
        $Text = $Text.Replace($pair[0], $pair[1])
    }
    $Text = $Text.Replace('&', '_and_').Replace('(', '').Replace(')', '')
    $plain = -join ($Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray() |
        Where-Object {
            [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne
                [Globalization.UnicodeCategory]::NonSpacingMark
        })
    $plain = [regex]::Replace($plain.ToLowerInvariant(), '[^a-z0-9]+', '_').Trim('_')
    if ($MaxLength -gt 0 -and $plain.Length -gt $MaxLength) {
        $plain = $plain.Substring(0, $MaxLength).TrimEnd('_')
    }
    $plain
}

function Get-DestinationFileName {
    param ([string]$Folder, [string]$Stem, [string]$Extension, [string]$OriginalBaseName)

    # Keep legacy Windows path compatibility even when long paths are enabled.
    # ASCII generated names also satisfy common Linux filesystems' 255-byte limit.
    $baseName = "$Stem$Extension"
    foreach ($component in ($Folder -split '[\\/]')) {
        if ([Text.Encoding]::UTF8.GetByteCount($component) -gt 255) {
            throw 'A destination directory exceeds the 255-byte Linux component limit; use a shorter destination root.'
        }
    }
    if ([Text.Encoding]::UTF8.GetByteCount($baseName) -gt 255 -or
        $Folder.Length -gt 247 -or (Join-Path $Folder $baseName).Length -gt 259) {
        throw 'Computed destination exceeds filename/path limits; use a shorter description or destination root.'
    }
    $original = ConvertTo-SafeName $OriginalBaseName -MaxLength 0
    if ($original) {
        $candidate = "${Stem}__orig_$original$Extension"
        if ([Text.Encoding]::UTF8.GetByteCount($candidate) -le 255 -and
            (Join-Path $Folder $candidate).Length -le 259) {
            return $candidate
        }
    }
    $baseName
}

function Get-DestinationFolder {
    param ([string]$Root, [string]$Year, [string]$Description)
    $name = if (-not $Description) { $Year }
        else { "${Year}_$Description" }
    Join-Path $Root $name
}

function Get-MediaDestination {
    param ($Item, [string]$Root, [string]$Description, [long]$Id, $Date = $Item.Date)
    $section = if ($Description) { "__dir_$Description" } else { '' }
    $prefix = if ($Item.IsVideo) { 'video' } else { 'image' }
    $stem = '{0}_{1:000000000}_{2}{3}' -f $prefix, $Id, $Date.Stamp, $section
    $folder = Get-DestinationFolder $Root $Date.Year $Description
    $name = Get-DestinationFileName $folder $stem `
        $Item.File.Extension.ToLowerInvariant() $Item.File.BaseName
    Join-Path $folder $name
}

function Read-Metadata {
    param ([string[]]$Paths)
    # UTF-8 stdin avoids Windows command-line encoding issues with German paths.
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $exifTool
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in @('-json', '-G1', '-s', '-charset', 'filename=UTF8',
            '-DateTimeOriginal', '-CreateDate', '-CreationDate', '-MIMEType', '-Error', '-Warning', '-@', '-')) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $process.Start() | Out-Null
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        foreach ($path in $Paths) { $process.StandardInput.WriteLine($path) }
        $process.StandardInput.Close()
        $process.WaitForExit()
        $errorText = $errors.GetAwaiter().GetResult()
        if ($process.ExitCode -notin @(0, 1)) {
            throw "ExifTool failed ($($process.ExitCode)): $errorText"
        }
        if ($errorText) { Write-Verbose $errorText }
        $records = @{}
        foreach ($record in (ConvertFrom-Json ($output.GetAwaiter().GetResult()) -AsHashtable)) {
            $records[[IO.Path]::GetFullPath($record.SourceFile)] = $record
        }
        $records
    }
    finally { $process.Dispose() }
}

function Get-BlockingMetadataWarnings {
    param ([string[]]$Warnings)
    $Warnings | Where-Object {
        $_ -and $_ -cne 'Invalid EXIF text encoding for UserComment'
    }
}

function Get-MediaDate {
    param ($Metadata, [bool]$IsVideo)
    $tags = @('ExifIFD:DateTimeOriginal', 'XMP-exif:DateTimeOriginal')
    if (-not $IsVideo) { $tags += @('ExifIFD:CreateDate', 'XMP-xmp:CreateDate') }
    $tags += @('Keys:CreationDate', 'UserData:DateTimeOriginal')
    foreach ($tag in $tags) {
        $value = [string]$Metadata[$tag]
        # These video fields are accepted only with an explicit timezone.
        if ($tag -in @('Keys:CreationDate', 'UserData:DateTimeOriginal') -and
            $value -notmatch '(Z|[+-]\d{2}:?\d{2})$') { continue }
        $date = [datetime]::MinValue
        if ($value -match '^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?$') {
            $text = '{0}-{1}-{2} {3}:{4}:{5}' -f $Matches[1], $Matches[2], $Matches[3],
                $Matches[4], $Matches[5], $Matches[6]
            if ([datetime]::TryParseExact($text, 'yyyy-MM-dd HH:mm:ss',
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::None, [ref]$date) -and
                $date.Year -ge $MinimumYear -and $date.Year -le $MaximumYear) {
                return [pscustomobject]@{
                    Year = $date.ToString('yyyy')
                    Stamp = $date.ToString('yyyy-MM-dd_HH-mm-ss')
                    Source = $tag
                }
            }
        }
    }
}

function Read-MenuChoice {
    param ([System.Collections.IDictionary]$Options, [string]$Default = 's')
    $prompt = ($Options.Keys | ForEach-Object {
        $defaultLabel = if ($_ -eq $Default) { ' (default)' } else { '' }
        '[{0}] {1}{2}' -f $_.ToUpperInvariant(), $Options[$_], $defaultLabel
    }) -join ', '
    while ($true) {
        $choice = (Read-Host $prompt).Trim().ToLowerInvariant()
        if (-not $choice) { return $Default }
        if ($Options.Contains($choice)) { return $choice }
        Write-Warning "Choose one of: $($Options.Keys -join ', '). Enter = $Default."
    }
}

function Read-FallbackYear {
    param ([int]$Count, [switch]$Override)
    Write-Host
    $heading = if ($Override) { 'Capture dates: override' } else { 'Capture dates: "unknown"' }
    $skipLabel = if ($Override) { 'Cancel override (keep current dates)' } else { 'Skip until next run' }
    $enterLabel = if ($Override) { 'cancel override' } else { 'skip until next run' }
    Write-Host $heading -ForegroundColor Cyan
    Write-Host ('  Need year decision : {0,5}' -f $Count)
    $scope = if ($Override) { '  Applies to ALL eligible media directly in this folder. Metadata stays unchanged.' }
        else { '  Applies to readable undated files in this folder only.' }
    Write-Host $scope -ForegroundColor DarkGray
    Write-Host
    $choice = Read-MenuChoice ([ordered]@{
        y = 'Enter year'; u = 'Unknown folder'; s = $skipLabel
    })
    if ($choice -eq 's') { return }
    if ($choice -eq 'u') {
        return [pscustomobject]@{ Year = 'unknown'; Stamp = 'unknown'; Source = 'User: unknown' }
    }
    Write-Host
    while ($true) {
        $answer = (Read-Host "Year ($MinimumYear-$MaximumYear; Enter = $enterLabel)").Trim()
        if (-not $answer) { return }
        if ($answer -match '^\d{4}$' -and [int]$answer -ge $MinimumYear -and
            [int]$answer -le $MaximumYear) {
            return [pscustomobject]@{
                Year = $answer; Stamp = $answer; Source = 'User: year'
            }
        }
        Write-Warning "Enter a valid four-digit year, or press Enter to $enterLabel."
    }
}

function Write-MediaResult {
    param ($Result, [bool]$IsVideo)
    if ($PassThru) {
        $Result
        return
    }
    Write-Host
    foreach ($name in @('Source', 'Destination', 'Status', 'Description', 'DateSource', 'Reason')) {
        $label = '{0,-12}: ' -f $name
        if ($IsVideo) { Write-Host $label -ForegroundColor Blue -NoNewline }
        else { Write-Host $label -NoNewline }
        if ($name -eq 'Reason' -and $Result.Reason) {
            $color = if ($Result.Status -eq 'Failed') { 'Red' } else { 'Yellow' }
            Write-Host $Result.Reason -ForegroundColor $color
        }
        else { Write-Host ([string]$Result.$name) }
    }
    Write-Host
}

function Write-MoveRecord {
    param ($Entry)
    $Entry | Export-Csv -LiteralPath $journalPath -Append -Encoding utf8
}

$source = [IO.Path]::GetFullPath($SourcePath).TrimEnd('\')
$destination = [IO.Path]::GetFullPath($DestinationPath).TrimEnd('\')
$exifTool = [IO.Path]::GetFullPath($ExifToolPath)
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Source not found: $source" }
if (-not (Test-Path -LiteralPath $exifTool -PathType Leaf)) { throw "ExifTool not found: $exifTool" }
if ((Test-WithinPath $destination $source) -or (Test-WithinPath $source $destination)) {
    throw 'Source and destination must be separate, non-nested folders.'
}
Assert-UnlinkedPath $source
Assert-UnlinkedPath $destination
if ((Test-Path -LiteralPath $destination) -and
    -not (Test-Path -LiteralPath $destination -PathType Container)) { throw 'Destination is not a folder.' }
if ($Apply) {
    $drive = [IO.Path]::GetPathRoot($source)
    if ($source -notmatch '^[a-zA-Z]:\\' -or
        -not $drive.Equals([IO.Path]::GetPathRoot($destination), [StringComparison]::OrdinalIgnoreCase) -or
        [IO.DriveInfo]::new($drive).DriveType -eq [IO.DriveType]::Network) {
        throw 'Apply requires source and destination on the same local drive.'
    }
}

$mediaExtensions = $imageExtensions + $videoExtensions
$journalPath = Join-Path $destination '_streamline-journal.csv'
$lock = $null
$results = [Collections.Generic.List[object]]::new()
$approvedFolders = [Collections.Generic.List[string]]::new()
$files = @()
try {
    if ($Apply) {
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        # Keep the lock file: deleting it can race with another run opening it.
        $lock = [IO.File]::Open((Join-Path $destination '_streamline.lock'),
            [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    [long]$nextId = 0
    if (Test-Path -LiteralPath $journalPath) {
        Assert-UnlinkedPath $journalPath
        $journal = @(Import-Csv -LiteralPath $journalPath)
        foreach ($entry in $journal) {
            if ($entry.Id -notmatch '^\d+$' -or
                $entry.Status -notin @('Planned', 'Moved', 'Failed', 'Recovered', 'Interrupted') -or
                $entry.SHA256 -notmatch '^[a-fA-F0-9]{64}$' -or
                -not (Test-WithinPath $entry.Source $source) -or
                -not (Test-WithinPath $entry.Destination $destination)) {
                throw 'Invalid journal entry. Review the journal before continuing.'
            }
            $nextId = [Math]::Max($nextId, [long]$entry.Id)
        }
        foreach ($group in ($journal | Group-Object Id)) {
            $entry = $group.Group[-1]
            if ($entry.Status -ne 'Planned') { continue }
            Assert-UnlinkedPath $entry.Source
            Assert-UnlinkedPath $entry.Destination
            $sourceExists = Test-Path -LiteralPath $entry.Source
            $targetExists = Test-Path -LiteralPath $entry.Destination
            if (-not $sourceExists -and $targetExists -and
                (Get-FileHash -LiteralPath $entry.Destination -Algorithm SHA256).Hash -eq $entry.SHA256) {
                $entry.Status = 'Recovered'
            }
            elseif ($sourceExists -and -not $targetExists) { $entry.Status = 'Interrupted' }
            else { throw "Unresolved interrupted move for ID $($entry.Id). Inspect both paths in the journal." }
            if ($Apply) {
                $entry.Timestamp = (Get-Date).ToString('o')
                Write-MoveRecord $entry
            }
            else { Write-Warning "ID $($entry.Id): $($entry.Status); Apply will record recovery." }
        }
    }
    if (Test-Path -LiteralPath $destination) {
        Get-ChildItem -LiteralPath $destination -File -Recurse -Force | ForEach-Object {
            if ($_.Name -match '^(image|video)_(\d+)_') {
                $nextId = [Math]::Max($nextId, [long]$Matches[2])
            }
        }
    }
    Write-MainHeader -Title 'Streamline Bilderpool' -Subtitle $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })
    Write-Host $(if ($Apply) { 'APPLY: approved files will be moved.' }
        else { 'PREVIEW: no files or folders will be changed. IDs are provisional.' })
    $files = @(Get-ChildItem -LiteralPath $source -File -Recurse -Force |
        Where-Object { $_.Extension.ToLowerInvariant() -in $mediaExtensions } |
        Sort-Object FullName)
    foreach ($folder in ($files | Group-Object DirectoryName)) {
        $plans = @(foreach ($file in $folder.Group) {
            try { Assert-UnlinkedPath $file.FullName; $file }
            catch { Write-Warning $_.Exception.Message }
        })
        if (-not $plans.Count) { continue }
        $metadata = Read-Metadata @($plans.FullName)
        $items = @(foreach ($file in $plans) {
            $record = $metadata[$file.FullName]
            $date = $null
            $reason = ''
            $isVideo = $file.Extension.ToLowerInvariant() -in $videoExtensions
            $warnings = if ($record) { @($record['ExifTool:Warning']) } else { @() }
            $blockingWarnings = @(Get-BlockingMetadataWarnings $warnings)
            if ($warnings -ccontains 'Invalid EXIF text encoding for UserComment') {
                Write-Warning "$($file.FullName): Invalid EXIF text encoding for UserComment (allowed; metadata left unchanged)."
            }
            if (-not $record -or $record['ExifTool:Error'] -or $blockingWarnings.Count -or
                $record['File:MIMEType'] -notmatch '^(image|video)/') {
                $reason = "Unreadable/unsupported media or metadata warning (type: $($record['File:MIMEType'])): $($record['ExifTool:Error']) $($blockingWarnings -join '; ')"
            }
            else {
                $date = Get-MediaDate $record $isVideo
            }
            [pscustomobject]@{ File = $file; Date = $date; IsVideo = $isVideo; Reason = $reason }
        })
        $description = if ($folder.Name -eq $source) { '' }
            else { ConvertTo-SafeName ([IO.Path]::GetFileName($folder.Name)) }
        Write-SectionHeader -Title 'Source folder' -Detail $folder.Name -Color Cyan
        $sidecars = @(Get-ChildItem -LiteralPath $folder.Name -File -Force |
            Where-Object Extension -In @('.xmp', '.aae', '.thm', '.lrv'))
        if ($sidecars.Count) {
            Write-Warning "$($sidecars.Count) companion/sidecar file(s) will stay in source. Matching media will also be skipped for later review."
        }
        foreach ($item in $items) {
            $matchingSidecars = @($sidecars | Where-Object {
                $_.BaseName -eq $item.File.BaseName -or $_.BaseName -eq $item.File.Name
            })
            if ($matchingSidecars.Count) {
                $item.Reason = "Companion/sidecar detected ($($matchingSidecars.Name -join ', ')); media and companion files left untouched for review."
            }
        }
        $pairs = @($items | Group-Object { $_.File.BaseName } | Where-Object {
            @($_.Group | Where-Object IsVideo).Count -and
            @($_.Group | Where-Object { -not $_.IsVideo }).Count
        })
        if ($pairs.Count) {
            Write-Warning "$($pairs.Count) matching image/video basename pair(s) detected (possibly Live Photos). All members will be skipped for later review."
            foreach ($pair in $pairs) {
                foreach ($item in $pair.Group) {
                    $item.Reason = 'Matching image/video basename (possibly Live Photo); all members left untouched for review.'
                }
            }
        }
        $blockedCount = @($items | Where-Object Reason).Count
        $undated = @($items | Where-Object { -not $_.Date -and -not $_.Reason })
        Write-Host ('  Media total        : {0,5}' -f $items.Count)
        Write-Host ('  Dated              : {0,5}' -f ($items.Count - $blockedCount - $undated.Count))
        Write-Host ('  Need year decision : {0,5}' -f $undated.Count)
        Write-Host ('  Blocked / review   : {0,5}' -f $blockedCount)
        if ($blockedCount) {
            Write-Host '  Skipped-file details follow after your selection.' -ForegroundColor DarkGray
        }
        $choice = ''
        while ($choice -notin @('y', 'n', 's', 'q')) {
            Write-Host
            Write-Host "Description: `"$description`"" -ForegroundColor Cyan
            $years = @($items | Where-Object { $_.Date -and -not $_.Reason } |
                ForEach-Object { $_.Date.Year } | Sort-Object -Unique)
            if ($years.Count) { Write-Host 'Destinations:' }
            foreach ($year in $years) {
                Write-Host "  $(Get-DestinationFolder $destination $year $description)"
            }
            $sample = $items | Where-Object { -not $_.Reason } | Select-Object -First 1
            if ($sample) {
                $sampleDate = if ($sample.Date) { $sample.Date }
                    else { [pscustomobject]@{ Year = 'unknown'; Stamp = 'unknown' } }
                try {
                    $samplePath = Get-MediaDestination $sample $destination $description ($nextId + 1) $sampleDate
                    Write-Host
                    Write-Host 'Sample (provisional ID/year; N omits description):' -ForegroundColor DarkGray
                    Write-Host "  $([IO.Path]::GetFileName($samplePath))"
                }
                catch { Write-Warning "Sample destination cannot be built: $($_.Exception.Message)" }
            }
            Write-Host
            $choice = Read-MenuChoice ([ordered]@{
                y = 'Accept'; e = 'Edit description'; n = 'No description'
                o = 'Override dates'; s = 'Skip'; q = 'Quit'
            })
            if ($choice -eq 'e') { $description = ConvertTo-SafeName (Read-Host 'Description') }
            if ($choice -eq 'o') {
                $eligible = @($items | Where-Object { -not $_.Reason })
                if ($eligible.Count) {
                    $overrideDate = Read-FallbackYear $eligible.Count -Override
                    if ($overrideDate) {
                        $overrideDate.Source = "User: override $($overrideDate.Year)"
                        foreach ($item in $eligible) { $item.Date = $overrideDate }
                        $undated = @()
                    }
                }
                else { Write-Warning 'No eligible media to override; blocked files remain untouched.' }
            }
        }
        if ($choice -eq 'q') { break }
        if ($choice -eq 'n') { $description = '' }
        if ($choice -ne 's') {
            if ($folder.Name -ne $source) { $approvedFolders.Add($folder.Name) }
            Write-Host
            Write-Host "description: `"$description`""
            if ($undated.Count) {
                $fallback = Read-FallbackYear $undated.Count
                foreach ($item in $undated) {
                    if ($fallback) { $item.Date = $fallback }
                    else {
                        $item.Reason = 'No reliable capture date. Year decision skipped by user; file stays in source and will be asked about next run.'
                    }
                }
                if ($fallback) {
                    Write-Host
                    Write-Host 'Destination:' -ForegroundColor Cyan
                    Write-Host "  $(Get-DestinationFolder $destination $fallback.Year $description)"
                    Write-Host
                }
            }
            if (@($items | Where-Object { $_.Date -and -not $_.Reason }).Count -eq 0) {
                Write-Warning 'No files in this folder are eligible. All will remain in the source; no destination can be computed. See each file''s Reason.'
            }
        }
        foreach ($item in $items) {
            $result = [pscustomobject]@{
                Source = $item.File.FullName; Destination = ''; Status = 'Skipped'
                Description = $description; DateSource = ''; Reason = $item.Reason
            }
            $results.Add($result)
            if ($choice -eq 's') { $result.Reason = 'Folder skipped by user.'; Write-MediaResult $result $item.IsVideo; continue }
            if ($item.Reason -or -not $item.Date) { Write-MediaResult $result $item.IsVideo; continue }
            $nextId++
            $date = $item.Date
            $result.DateSource = $date.Source
            try {
                $target = Get-MediaDestination $item $destination $description $nextId
                $targetFolder = [IO.Path]::GetDirectoryName($target)
                $result.Destination = $target
                Assert-UnlinkedPath $target
                if (Test-Path -LiteralPath $target) { throw 'Destination already exists; nothing overwritten.' }
            }
            catch { $result.Reason = $_.Exception.Message; Write-MediaResult $result $item.IsVideo; continue }
            if (-not $Apply) { $result.Status = 'Preview'; Write-MediaResult $result $item.IsVideo; continue }

            try {
                $hash = (Get-FileHash -LiteralPath $item.File.FullName -Algorithm SHA256).Hash
                if (-not $hash) { throw 'No file hash was returned.' }
            }
            catch {
                $result.Status = 'Failed'
                $result.Reason = "Cannot read/hash source file; left untouched: $($_.Exception.Message)"
                Write-MediaResult $result $item.IsVideo
                continue
            }
            # A journal failure aborts the run; never move without a recorded plan.
            $entry = [pscustomobject]@{
                Timestamp = (Get-Date).ToString('o'); Id = $nextId; Status = 'Planned'
                Source = $item.File.FullName; Destination = $target
                SHA256 = $hash
                DateSource = $date.Source
            }
            Write-MoveRecord $entry
            try {
                [IO.Directory]::CreateDirectory($targetFolder) | Out-Null
                [IO.File]::Move($item.File.FullName, $target)
                $entry.Status = 'Moved'
                $result.Status = 'Moved'
            }
            catch {
                $entry.Status = 'Failed'
                $result.Status = 'Failed'
                $result.Reason = $_.Exception.Message
            }
            $entry.Timestamp = (Get-Date).ToString('o')
            Write-MoveRecord $entry
            Write-MediaResult $result $item.IsVideo
        }
    }
    $previewRemovals = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (-not $Apply) {
        foreach ($result in $results) {
            if ($result.Status -eq 'Preview') { $previewRemovals.Add($result.Source) | Out-Null }
        }
    }
    foreach ($folderPath in ($approvedFolders | Sort-Object { $_.Length } -Descending)) {
        try {
            Assert-UnlinkedPath $folderPath
            $remaining = @(Get-ChildItem -LiteralPath $folderPath -Force |
                Where-Object { -not $previewRemovals.Contains($_.FullName) })
            if ($remaining.Count) { continue }
            if ($Apply) {
                # Non-recursive deletion fails safely if new content appears meanwhile.
                [IO.Directory]::Delete($folderPath, $false)
                Write-Host "Removed empty source folder: $folderPath"
            }
            else {
                $previewRemovals.Add($folderPath) | Out-Null
                Write-Host "Would remove empty source folder: $folderPath"
            }
        }
        catch { Write-Warning "Source folder kept: $folderPath -- $($_.Exception.Message)" }
    }
}
finally {
    if ($lock) { $lock.Dispose() }
    Write-SectionHeader -Title 'Summary'
    Write-Host ("Previewed: {0}; moved: {1}; skipped: {2}; failed: {3}; not processed: {4}" -f
        @($results | Where-Object Status -EQ 'Preview').Count,
        @($results | Where-Object Status -EQ 'Moved').Count,
        @($results | Where-Object Status -EQ 'Skipped').Count,
        @($results | Where-Object Status -EQ 'Failed').Count,
        ($files.Count - $results.Count))
    if (Test-Path -LiteralPath $journalPath) { Write-Host "Journal: $journalPath" }
    else { Write-Host 'Journal: not created (only written when applying moves).' }
}