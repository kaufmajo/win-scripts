#Requires -Version 7.0
param (
    [Parameter(Mandatory)]
    [string]$ExifToolPath
)

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\Streamline-Bilderpool.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) "st-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$source = Join-Path $root 'source'
$destination = Join-Path $root 'result'
$answers = [Collections.Generic.Queue[string]]::new()

function Assert-True {
    param ([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Read-Host {
    param ([string]$Prompt)
    if (-not $answers.Count) { throw "Unexpected prompt: $Prompt" }
    $answers.Dequeue()
}

function New-TestImage {
    param ([string]$Folder, [string]$Name)
    [IO.Directory]::CreateDirectory($Folder) | Out-Null
    $path = Join-Path $Folder $Name
    $bitmap = [Drawing.Bitmap]::new(2, 2)
    try { $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Jpeg) }
    finally { $bitmap.Dispose() }
    $path
}

function Set-TestDates {
    param ([string[]]$Paths)
    $arguments = Join-Path $root 'exif-arguments.txt'
    $lines = @('-overwrite_original', '-DateTimeOriginal=2023:08:14 15:32:07') + $Paths
    [IO.File]::WriteAllLines($arguments, $lines, [Text.UTF8Encoding]::new($false))
    & $ExifToolPath -charset filename=UTF8 -@ $arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not set fixture dates.' }
}

function New-TestVideo {
    param ([string]$Folder, [string]$Name)
    # Minimal QuickTime container: tests metadata handling, not video playback.
    function New-Atom {
        param ([string]$Type, [byte[]]$Data)
        $length = [BitConverter]::GetBytes([uint32]($Data.Length + 8))
        [Array]::Reverse($length)
        ,([byte[]]($length + [Text.Encoding]::ASCII.GetBytes($Type) + $Data))
    }
    [IO.Directory]::CreateDirectory($Folder) | Out-Null
    $ftyp = New-Atom 'ftyp' ([byte[]](113, 116, 32, 32, 0, 0, 0, 0, 113, 116, 32, 32))
    $header = [byte[]]::new(100)
    $header[15] = 1
    $moov = New-Atom 'moov' (New-Atom 'mvhd' $header)
    $path = Join-Path $Folder $Name
    $mdat = New-Atom 'mdat' ([byte[]](0, 0, 0, 0))
    [IO.File]::WriteAllBytes($path, [byte[]]($ftyp + $moov + $mdat))
    $path
}

function Invoke-TestRun {
    param ([string[]]$Responses, [switch]$Apply, [switch]$ConsoleOutput)
    $answers.Clear()
    foreach ($answer in $Responses) { $answers.Enqueue($answer) }
    & $scriptPath -SourcePath $source -DestinationPath $destination `
        -ExifToolPath $ExifToolPath -Apply:$Apply -PassThru:(!$ConsoleOutput) `
        -InformationVariable feedback -WarningVariable warnings
    $script:lastFeedback = ($feedback | ForEach-Object { $_.ToString() }) -join "`n"
    $script:lastWarnings = $warnings -join "`n"
    Assert-True ($answers.Count -eq 0) 'all expected folder prompts consumed'
}

try {
    $DescriptionMaxLength = 80
    $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    foreach ($function in $ast.FindAll({
        param ($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -in @('ConvertTo-SafeName', 'Get-DestinationFileName', 'Get-MediaDate', 'Get-OrganizationMetadata')
    }, $true)) {
        . ([scriptblock]::Create($function.Extent.Text))
    }
    $DescriptionMaxLength = 6
    Assert-True ((ConvertTo-SafeName 'Long Description') -eq 'long_d') 'description length uses user setting'
    $DescriptionMaxLength = 80
    $MinimumYear = 1800
    $MaximumYear = (Get-Date).Year + 1
    $record = @{
        'File:MIMEType' = 'image/jpeg'
        'ExifIFD:DateTimeOriginal' = '2023:08:14 15:32:07'
    }
    foreach ($warning in @(
        'Invalid EXIF text encoding for UserComment',
        '[minor] Canon maker note footer may be invalid (ignored)',
        '[minor] Adjusted MakerNotes base by 4012',
        'Previously unseen metadata warning'
    )) {
        $record['ExifTool:Warning'] = $warning
        $organization = Get-OrganizationMetadata $record $false
        Assert-True ($organization.Date.Year -eq '2023' -and -not $organization.Reason) 'unrelated warnings preserve valid organizing date'
    }
    $record['ExifTool:Warning'] = @('Adjusted MakerNotes base', 'Invalid DateTimeOriginal value')
    $organization = Get-OrganizationMetadata $record $false
    Assert-True (-not $organization.Date -and -not $organization.Reason -and
        $organization.HasDateWarning) 'date-related warnings require manual year decision without blocking file'
    $record.Remove('ExifTool:Warning')
    $record['ExifIFD:DateTimeOriginal'] = '2023:99:99 15:32:07'
    Assert-True (-not (Get-OrganizationMetadata $record $false).Date) 'invalid date requires manual decision'
    $record['ExifTool:Error'] = 'Read error'
    Assert-True ([bool](Get-OrganizationMetadata $record $false).Reason) 'actual read errors still block'
    Assert-True ([bool](Get-OrganizationMetadata $null $false).Reason) 'missing metadata still blocks'
    Assert-True ([bool](Get-OrganizationMetadata @{ 'File:MIMEType' = 'text/plain' } $false).Reason) 'unsupported media still blocks'
    Assert-True ((Get-DestinationFileName 'C:\out' 'image_1' '.jpg' 'Ärger (IMG.4321)') -eq
        'image_1__orig_aerger_img_4321.jpg') 'sanitize original basename'
    Assert-True ((Get-DestinationFileName 'C:\out' 'image_1__dir_album' '.jpg' 'test__orig_name') -eq
        'image_1__dir_album__orig_test_orig_name.jpg') 'section markers remain unambiguous'
    Assert-True ((Get-DestinationFileName 'C:\out' 'image_1' '.jpg' '!!!') -eq
        'image_1.jpg') 'empty sanitized original adds no separator'
    $original = 'a' * 238
    $atLimit = Get-DestinationFileName 'C:\' 'image_1' '.jpg' ($original.Substring(0, 237))
    Assert-True ($atLimit.Length -eq 255) '255-byte filename is allowed'
    Assert-True ((Get-DestinationFileName 'C:\' 'image_1' '.jpg' $original) -eq
        'image_1.jpg') 'omit entire suffix above 255 bytes without truncation'
    $folder = 'C:\' + ('d' * 210)
    $atLimit = Get-DestinationFileName $folder 'image_1' '.jpg' ('a' * 27)
    Assert-True ((Join-Path $folder $atLimit).Length -eq 259) '259-character path is allowed'
    Assert-True ((Get-DestinationFileName $folder 'image_1' '.jpg' ('a' * 28)) -eq
        'image_1.jpg') 'omit suffix exceeding full-path limit'
    $rejected = $false
    try { Get-DestinationFileName ('C:\' + ('d' * 243)) 'image_123456789' '.jpg' 'original' | Out-Null }
    catch { $rejected = $true }
    Assert-True $rejected 'reject overlong computed path even without original suffix'
    $rejected = $false
    try { Get-DestinationFileName ('C:\' + ('é' * 128)) 'image_1' '.jpg' 'original' | Out-Null }
    catch { $rejected = $true }
    Assert-True $rejected 'reject directory component above 255 UTF-8 bytes'

    Add-Type -AssemblyName System.Drawing
    $album = Join-Path $source 'a Urlaub München (Sommer 2023). & Café'
    $dated = New-TestImage $album 'IMG_0001.JPG'
    $second = New-TestImage $album 'image_000000001_existing.JPG'
    Set-TestDates @($dated, $second)
    $manual = New-TestImage $album 'no-date.JPG'
    [IO.File]::WriteAllText((Join-Path $album '_year_2018.txt'), '')
    $child = New-TestImage (Join-Path $album 'child') 'undated.JPG'
    $badFolder = Join-Path $source 'b ambiguous'
    $ambiguous = New-TestImage $badFolder 'undated.JPG'
    [IO.File]::WriteAllText((Join-Path $badFolder '_year_2019.txt'), '')
    [IO.File]::WriteAllText((Join-Path $badFolder '_year_2020.txt'), '')
    $invalidFolder = Join-Path $source 'c invalid'
    $invalid = New-TestImage $invalidFolder 'undated.JPG'
    [IO.File]::WriteAllText((Join-Path $invalidFolder '_year_0000.txt'), '')
    $plain = New-TestImage (Join-Path $source 'd no description') 'plain.JPG'
    Set-TestDates @($plain)
    $skipped = New-TestImage (Join-Path $source 'e skip') 'skip.JPG'
    Set-TestDates @($skipped)
    $videoFolder = Join-Path $source 'f videos'
    $video = New-TestVideo $videoFolder 'dated.MOV'
    & $ExifToolPath -overwrite_original '-Keys:CreationDate=2024:06:02 10:15:00+02:00' -- $video | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not write video fixture metadata.' }
    $videoManual = New-TestVideo $videoFolder 'manual.MOV'
    [IO.File]::WriteAllText((Join-Path $videoFolder '_year_2017.txt'), '')
    $videoAmbiguous = New-TestVideo (Join-Path $source 'g video ambiguous') 'ambiguous.MOV'
    & $ExifToolPath -overwrite_original '-QuickTime:CreateDate=2021:05:06 10:00:00' -- $videoAmbiguous | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not write ambiguous video metadata.' }
    $broken = Join-Path $album 'broken.JPG'
    [IO.File]::WriteAllText($broken, 'Not an image')
    [IO.File]::WriteAllText((Join-Path $album 'orphan.xmp'), 'sidecar placeholder')

    $before = @{}
    Get-ChildItem -LiteralPath $source -File -Recurse | ForEach-Object {
        $before[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName).Hash
    }
    $responses = @('invalid', 'y', 'invalid', ' Y ', '0000', '2018', 'y', 's', 'y', 's', 'y', '', 'n', 's', 'y', 'y', '2017', 'y', ' U ')
    $preview = @(Invoke-TestRun $responses)
    Assert-True ($lastFeedback.Contains('Sample (provisional') -and
        $lastFeedback.Contains('Previewed: 7; moved: 0; skipped: 5; failed: 0; not processed: 0')) 'filename samples and preview summary'
    Assert-True ($lastWarnings.Contains('companion/sidecar')) 'sidecar warning'
    Assert-True (-not (Test-Path -LiteralPath $destination)) 'preview creates no destination'
    Assert-True (@($preview | Where-Object Status -eq Preview).Count -eq 7) 'four images and three videos ready'
    Assert-True (($preview | Where-Object Source -eq $dated).Destination -match
        '\\2023_a_urlaub_muenchen_sommer_2023_and_cafe\\image_\d+_2023-08-14_15-32-07__dir_a_urlaub_muenchen_sommer_2023_and_cafe__orig_img_0001\.jpg$') 'folder and filename sanitized with original basename'
    Assert-True (($preview | Where-Object Source -eq $manual).Destination -match
        '\\2018_a_urlaub.*\\image_\d+_2018__dir_a_urlaub') 'manual year does not invent a full date'
    Assert-True (($preview | Where-Object Source -eq $plain).Destination -match
        '\\2023\\image_\d+_2023-08-14_15-32-07__orig_plain\.jpg$') 'no-description year-only folder'
    Assert-True (($preview | Where-Object Source -eq $video).Destination -match
        '\\2024_f_videos\\video_\d+_2024-06-02_10-15-00__dir_f_videos__orig_dated\.mov$') 'video local timestamp retained'
    Assert-True (($preview | Where-Object Source -eq $videoManual).Destination -match
        '\\2017_f_videos\\video_\d+_2017__dir_f_videos__orig_manual\.mov$') 'video manual-year fallback'
    Assert-True (($preview | Where-Object Source -eq $videoAmbiguous).Destination -match
        '\\unknown_g_video_ambiguous\\video_\d+_unknown__dir_g_video_ambiguous__orig_ambiguous\.mov$') 'unknown folder includes description'
    Assert-True (($preview | Where-Object Source -eq $dated).DateSource -eq
        'ExifIFD:DateTimeOriginal') 'manual year never replaces embedded date'
    foreach ($path in @($child, $ambiguous, $invalid, $broken, $skipped)) {
        Assert-True (($preview | Where-Object Source -eq $path).Status -eq 'Skipped') "leave $path"
    }
    $undatedResult = $preview | Where-Object Source -eq $child
    Assert-True ($undatedResult.Description -eq 'child') 'skipped file retains accepted description in output'
    Assert-True ($undatedResult.Reason.Contains('Year decision skipped by user') -and
        $undatedResult.Reason.Contains('next run')) 'skip feedback explains retry'
    Assert-True (($preview | Where-Object Source -eq $ambiguous).DateSource -eq '') 'old year markers ignored'
    Assert-True (($preview | Where-Object Source -eq $skipped).Reason -eq
        'Folder skipped by user.') 'distinguish user skip from missing-date skip'
    foreach ($path in $before.Keys) {
        Assert-True ((Get-FileHash -LiteralPath $path).Hash -eq $before[$path]) 'preview preserves files'
    }
    [IO.Directory]::CreateDirectory((Join-Path $destination '2023')) | Out-Null
    $existing = Join-Path $destination '2023\image_000000900_existing.jpg'
    [IO.File]::WriteAllText($existing, 'Existing destination file must never be overwritten.')
    $existingHash = (Get-FileHash -LiteralPath $existing).Hash
    $applied = @(Invoke-TestRun $responses -Apply)
    $moved = @($applied | Where-Object Status -eq Moved)
    Assert-True ($moved.Count -eq 7) 'apply moves seven files'
    foreach ($item in $moved) {
        Assert-True (-not (Test-Path -LiteralPath $item.Source)) 'moved source gone'
        Assert-True ((Get-FileHash -LiteralPath $item.Destination).Hash -eq
            $before[$item.Source]) 'moved contents unchanged'
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $album '_year_2018.txt')) 'retain marker'
    Assert-True (Test-Path -LiteralPath (Join-Path $album 'orphan.xmp')) 'retain sidecar'
    Assert-True ((Get-FileHash -LiteralPath $existing).Hash -eq $existingHash) 'retain existing destination'
    foreach ($item in $moved) {
        $id = [regex]::Match([IO.Path]::GetFileName($item.Destination), '_(\d+)_').Groups[1].Value
        Assert-True ([long]$id -gt 900) 'avoid IDs already present in destination'
    }
    $rerun = @(Invoke-TestRun @('y', 'y', 's', 'y', 's', 'y', 'y', '', 's') -Apply)
    Assert-True (@($rerun | Where-Object Status -eq Moved).Count -eq 0) 'repeat run does not reprocess'

    $journalPath = Join-Path $destination '_streamline-journal.csv'
    $journal = @(Import-Csv -LiteralPath $journalPath)
    $lastId = [long]($journal | Measure-Object Id -Maximum).Maximum
    $new = New-TestImage $album 'new.JPG'
    Set-TestDates @($new)
    $added = @(Invoke-TestRun @('e', 'Neuer Urlaub!', 'y', 'y', 's', 'y', 's', 'y', 's', 's') -Apply |
        Where-Object Status -eq Moved)
    Assert-True ($added.Count -eq 1) 'new arrival moves'
    Assert-True ([IO.Path]::GetFileName($added[0].Destination) -match
        '^image_(\d+)_.*__dir_neuer_urlaub__orig_new\.jpg$') 'custom description used'
    Assert-True ([long]$Matches[1] -gt $lastId) 'IDs continue across runs'
    $ids = @(Get-ChildItem -LiteralPath $destination -File -Recurse |
        Where-Object Name -Match '^(image|video)_\d+_' | ForEach-Object {
            [regex]::Match($_.Name, '_(\d+)_').Groups[1].Value
        })
    Assert-True (@($ids | Sort-Object -Unique).Count -eq $ids.Count) 'IDs unique'

    # Simulate interruption after the move but before the completion record.
    $journal = @(Import-Csv -LiteralPath $journalPath)
    $journal[0..($journal.Count - 2)] |
        Export-Csv -LiteralPath $journalPath -Encoding utf8
    Invoke-TestRun @('q') -Apply | Out-Null
    Assert-True ($lastFeedback.Contains('not processed: 5') -and
        $lastFeedback.Contains("Journal: $journalPath")) 'quit summary includes remaining files and journal'
    Assert-True (@(Import-Csv -LiteralPath $journalPath)[-1].Status -eq 'Recovered') 'recover interrupted move'
    Assert-True (Test-Path -LiteralPath $skipped) 'quit leaves remaining media untouched'

    # A recorded plan without a move can be retried under a new ID.
    $retry = New-TestImage $album 'retry.JPG'
    $pending = @(Import-Csv -LiteralPath $journalPath)[-1].PSObject.Copy()
    $pending.Id = ([long]$pending.Id + 1).ToString()
    $pending.Source = $retry
    $pending.Destination = Join-Path $destination '2018\not-yet-moved.jpg'
    $pending.SHA256 = (Get-FileHash -LiteralPath $retry).Hash
    $pending.Status = 'Planned'
    $pending | Export-Csv -LiteralPath $journalPath -Append -Encoding utf8
    $retried = @(Invoke-TestRun @('y', 'y', '2018', 'q') -Apply | Where-Object Status -eq Moved)
    Assert-True ($retried.Count -eq 1) 'retry interrupted plan'
    Assert-True (@(Import-Csv -LiteralPath $journalPath |
        Where-Object Status -eq Interrupted).Count -eq 1) 'record interruption'

    $source = Join-Path $root 'hash-source'
    $destination = Join-Path $root 'hash-result'
    $locked = New-TestImage $source 'a-locked.JPG'
    $paired = New-TestImage $source 'pair.JPG'
    Set-TestDates @($locked, $paired)
    $pairedVideo = New-TestVideo $source 'pair.MOV'
    $normal = New-TestImage $source 'normal.JPG'
    $withSidecar = New-TestImage $source 'sidecar.JPG'
    $withFullNameSidecar = New-TestImage $source 'full-name.JPG'
    Set-TestDates @($normal, $withSidecar, $withFullNameSidecar)
    $xmp = Join-Path $source 'sidecar.XMP'
    $aae = Join-Path $source 'full-name.JPG.aae'
    [IO.File]::WriteAllText($xmp, 'sidecar placeholder')
    [IO.File]::WriteAllText($aae, 'sidecar placeholder')
    $protected = @($paired, $pairedVideo, $withSidecar, $withFullNameSidecar, $xmp, $aae)
    $protectedHashes = @{}
    foreach ($path in $protected) { $protectedHashes[$path] = (Get-FileHash -LiteralPath $path).Hash }
    $protectedPreview = @(Invoke-TestRun @('y'))
    $consoleResults = @(Invoke-TestRun @('y') -ConsoleOutput)
    Assert-True ($consoleResults.Count -eq 0) 'console output emits no duplicate result objects'
    Assert-True ($lastFeedback.Contains('Source      : ') -and
        $lastFeedback.Contains('Reason      : ') -and
        $lastFeedback.Contains('left untouched for review')) 'custom console output includes file details and skip reasons'
    $exported = @($protectedPreview | ConvertTo-Csv)
    Assert-True ($exported.Count -eq $protectedPreview.Count + 1 -and
        $exported[0].Contains('"Reason"')) 'PassThru results remain CSV-compatible'
    foreach ($path in @($paired, $pairedVideo, $withSidecar, $withFullNameSidecar)) {
        $result = $protectedPreview | Where-Object Source -EQ $path
        Assert-True ($result.Status -eq 'Skipped' -and $result.Reason.Contains('review') -and
            -not $result.Destination) 'preview skips related media without assigning a destination'
    }
    function Get-FileHash {
        param ([string]$LiteralPath, [string]$Algorithm = 'SHA256')
        if ($LiteralPath -eq $locked) { throw 'Simulated sharing violation.' }
        Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
    }
    try { $hashRun = @(Invoke-TestRun @('y') -Apply) }
    finally { Remove-Item -LiteralPath Function:\Get-FileHash }
    Assert-True (@($hashRun | Where-Object Status -EQ 'Moved').Count -eq 1) 'continue after per-file hash failure'
    Assert-True (($hashRun | Where-Object Source -EQ $locked).Reason.Contains(
        'Cannot read/hash source file; left untouched')) 'explain hash failure'
    Assert-True (Test-Path -LiteralPath $locked) 'hash failure preserves source'
    Assert-True ($lastWarnings.Contains('possibly Live Photos')) 'warn about matching image/video basenames'
    Assert-True ($lastFeedback.Contains('moved: 1; skipped: 4; failed: 1; not processed: 0')) 'summary counts protected media and hash failure'
    foreach ($path in $protected) {
        Assert-True ((Get-FileHash -LiteralPath $path).Hash -eq $protectedHashes[$path]) 'related media and companions remain unchanged'
    }
    $retryHash = @(Invoke-TestRun @('y') -Apply)
    Assert-True (@($retryHash | Where-Object Status -EQ 'Moved').Count -eq 1) 'retry previously unreadable file'

    $source = Join-Path $root 'override-source'
    $destination = Join-Path $root 'override-result'
    $album = Join-Path $source 'Family scans'
    $scan = New-TestImage $album 'scan.JPG'
    $undatedScan = New-TestImage $album 'undated.JPG'
    $protectedScan = New-TestImage $album 'protected.JPG'
    Set-TestDates @($scan, $protectedScan)
    [IO.File]::WriteAllText((Join-Path $album 'protected.xmp'), 'sidecar placeholder')
    $originalHash = (Get-FileHash -LiteralPath $scan).Hash
    $unknownRun = @(Invoke-TestRun @('o', 'u', 'y'))
    foreach ($path in @($scan, $undatedScan)) {
        $result = $unknownRun | Where-Object Source -EQ $path
        Assert-True ($result.Status -eq 'Preview' -and $result.Destination -match
            '\\unknown_family_scans\\image_\d+_unknown__dir_family_scans__orig_' -and
            $result.DateSource -eq 'User: override unknown') 'override dated and undated scans to unknown'
    }
    Assert-True (($unknownRun | Where-Object Source -EQ $protectedScan).Status -eq 'Skipped') 'override respects companion protection'
    $cancelRun = @(Invoke-TestRun @('o', '', 'y', 's'))
    Assert-True (($cancelRun | Where-Object Source -EQ $scan).DateSource -eq
        'ExifIFD:DateTimeOriginal') 'cancel retains embedded date'
    Assert-True (($cancelRun | Where-Object Source -EQ $undatedScan).Status -eq 'Skipped') 'cancel leaves normal undated prompt active'
    $yearRun = @(Invoke-TestRun @('o', 'y', '1950', 'y'))
    Assert-True (($yearRun | Where-Object Source -EQ $scan).Destination -match
        '\\1950_family_scans\\image_\d+_1950__dir_') 'year override uses no invented month or day'
    $overrideApply = @(Invoke-TestRun @('o', 'u', 'y') -Apply)
    $movedScan = $overrideApply | Where-Object Source -EQ $scan
    Assert-True ($movedScan.Status -eq 'Moved' -and
        (Get-FileHash -LiteralPath $movedScan.Destination).Hash -eq $originalHash) 'override moves without changing embedded metadata'

    $source = Join-Path $root 'cleanup-source'
    $destination = Join-Path $root 'cleanup-result'
    $parent = Join-Path $source 'a-parent'
    $childFolder = Join-Path $parent 'child'
    $hiddenFolder = Join-Path $source 'b-hidden'
    $skipFolder = Join-Path $source 'c-skipped'
    $cleanupImages = @(
        (New-TestImage $parent 'parent.JPG'),
        (New-TestImage $childFolder 'child.JPG'),
        (New-TestImage $hiddenFolder 'hidden.JPG'),
        (New-TestImage $skipFolder 'skip.JPG'),
        (New-TestImage $source 'root.JPG')
    )
    Set-TestDates $cleanupImages
    $hiddenFile = Join-Path $hiddenFolder 'keep.txt'
    [IO.File]::WriteAllText($hiddenFile, 'Keep hidden content')
    [IO.File]::SetAttributes($hiddenFile, [IO.FileAttributes]::Hidden)
    Invoke-TestRun @('y', 'y', 'y', 'y', 's') | Out-Null
    Assert-True ($lastFeedback.Contains("Would remove empty source folder: $parent") -and
        $lastFeedback.Contains("Would remove empty source folder: $childFolder")) 'preview predicts nested cleanup'
    Assert-True ((Test-Path -LiteralPath $childFolder) -and
        (Test-Path -LiteralPath $cleanupImages[0])) 'preview cleanup changes nothing'
    Invoke-TestRun @('y', 'y', 'y', 'y', 's') -Apply | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $parent)) 'remove emptied parent and child deepest first'
    Assert-True ((Test-Path -LiteralPath $source) -and
        (Test-Path -LiteralPath $hiddenFile) -and
        (Test-Path -LiteralPath $cleanupImages[3])) 'retain source root, hidden content and skipped folder'

    $rejected = $false
    try {
        & $scriptPath -SourcePath $source -DestinationPath (Join-Path $source 'nested') `
            -ExifToolPath $ExifToolPath | Out-Null
    }
    catch { $rejected = $true }
    Assert-True $rejected 'reject nested destination'
    Write-Host 'All synthetic image/video integration checks passed.'
}
finally {
    # Remove only this test's newly created, uniquely named temporary directory.
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
