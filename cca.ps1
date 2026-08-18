<#
.SYNOPSIS
    Converts volume folders/.rar/.cbr/.zip into .cbz comic archives. Output is always
    .cbz, even from a .rar/.cbr source - Kobo/KOReader doesn't support panel zoom on
    .cbr, which is the reason this never produces one.

.DESCRIPTION
    Default: walks the whole tree under -Path looking for "final" volumes, at
    whatever depth each one happens to sit, and writes one .cbz per volume into a
    single "<Path's own name>_output" folder created next to -Path. A folder counts as
    a final volume as soon as it contains at least one page file directly inside it,
    or has no subfolders left to descend into - so a folder with only loose pages (no
    subfolders) is final immediately, a folder mixing loose pages with subfolders
    (e.g. a Doraemon "Vol 01" holding both its own cover pages and "Story 001",
    "Story 002", ... subfolders) is final as a whole (everything nested included in one
    archive), and a folder holding *only* more folders and no pages of its own (e.g. a
    "v01-05" pack with zero loose pages, just five volume subfolders) is not final -
    the script descends into it and repeats the check on each subfolder instead. This
    is what lets one run correctly turn a "v01-05" pack into 5 separate volume .cbz
    files while also converting a standalone "v13" into its own single .cbz, in the
    same pass.

    A folder holding one .rar/.cbr/.zip per issue instead of pages (e.g. a
    "Peter Parker 001-006" folder with six separate .cbr files, no subfolders) is
    recognized as that shape too - each archive is converted on its own rather than
    the whole folder being wrapped raw into one .cbz, which would just embed the
    unextracted archive bytes instead of actual comic pages.

    If -Path itself contains no subfolders (i.e. it's a volume folder itself, holding
    pages directly - like "v13" sitting next to a "v01-05" pack folder), it is converted
    on its own into a single .cbz - into the "_output" folder by default, or next to
    -Path's parent with -NoRecurse, same as everything else below.

    With -NoRecurse: one level only. Scans just the immediate children of -Path and
    converts each:
      - Folder  -> sibling .cbz, containing the whole folder subtree (including any
                   nested subfolders, at any depth) zipped with the folder name kept
                   as the root entry. Nested folders are NOT split into their own
                   separate archives - only this first level of subfolders is treated
                   as one unit each, so a folder that packs several volumes together
                   (e.g. a "v01-05" folder holding five volume subfolders) becomes one
                   .cbz containing all of them, not one .cbz per volume. Written next
                   to wherever that folder naturally sits, not into an "_output" folder.
                   Exception: a folder holding nothing but .rar/.cbr/.zip files (one
                   per issue, no subfolders) is still converted archive-by-archive
                   even here, never wrapped raw into one .cbz - see above.
      - .rar/.cbr file -> sibling .cbz. Extracted with 7-Zip or WinRAR (whichever is
                     found - see Requirements) into a temp folder, then re-zipped from
                     there with the same layout .cbz would otherwise have gotten,
                     including the ComicInfo.xml reading-direction entry. Never
                     produces a .cbr - see Requirements if neither tool is found.
      - .zip file -> sibling .cbz (container copied, then a ComicInfo.xml reading-direction
                     entry is added/replaced at the archive root)

    Every generated .cbz gets a ComicInfo.xml file written at the root of the archive
    (a sibling of the top-level folder entry, not nested inside it) so readers like
    KOReader pick up the reading direction automatically. Right-to-left (manga order)
    is the default; pass -LeftToRight to tag it as normal left-to-right reading order
    instead.

    Existing output files are skipped unless -Force is given. Source
    folders/files are never modified or deleted.

.PARAMETER Path
    Directory to scan for volume folders/archives (e.g. ".\Digital" or ".\Scan").

.PARAMETER NoRecurse
    Only look one level deep under -Path instead of auto-detecting final volume
    folders at any depth (see above), writing each result next to wherever it
    naturally sits instead of into an "<Path's own name>_output" folder.

.PARAMETER LeftToRight
    Tag the generated ComicInfo.xml as left-to-right reading order instead of the
    default right-to-left (manga) order.

.PARAMETER Force
    Overwrite an existing .cbz/.cbr output if one is already present.

.PARAMETER WhatIf
    Show what would be done without writing anything.

.EXAMPLE
    cca -Path '.\13DL.me_Yotsubato vol 01-15'

.EXAMPLE
    cca -Path .\Digital -Force

.EXAMPLE
    cca -Path .\SomeWesternComic -LeftToRight

.EXAMPLE
    cca -Path .\Scan -NoRecurse

.NOTES
    Run once after cloning: .\install.ps1 - adds a "cca" command to your user PATH
    that always calls this file directly, so edits here take effect immediately.
    Without installing, run it as .\cca.ps1 (same parameters).

    Converting a .rar/.cbr source requires 7-Zip or WinRAR to already be installed
    (checked on PATH and in their default Program Files locations) - unlike .zip,
    RAR has no built-in .NET support for reading it, so this script can't do it alone.
    A .rar/.cbr encountered with neither tool available is reported as FAIL and
    skipped; everything else in the same run still proceeds.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$NoRecurse,

    [switch]$LeftToRight,

    [switch]$Force
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ErrorActionPreference = 'Stop'

$MangaValue = if ($LeftToRight) { 'No' } else { 'YesAndRightToLeft' }

# Extensions that need converting on their own rather than ever being bundled raw
# into a wrapper .cbz - doing that would just embed the unextracted archive bytes,
# not actual comic pages. Deliberately excludes .cbz: an existing .cbz needs no
# conversion, and might be this tool's own leftover output from an earlier run.
$ArchiveExtensions = @('.rar', '.cbr', '.zip')

function Get-ComicInfoXml {
    param([string]$Manga)

    return @"
<?xml version="1.0" encoding="utf-8"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Manga>$Manga</Manga>
</ComicInfo>
"@
}

function Write-ComicInfoEntry {
    param(
        [System.IO.Compression.ZipArchive]$Zip,
        [string]$Manga
    )

    # Remove any existing root-level ComicInfo.xml (case-insensitive, root only -
    # a nested "SomeFolder/ComicInfo.xml" from the source content is left alone).
    $existing = $Zip.Entries | Where-Object { $_.FullName -ieq 'ComicInfo.xml' }
    foreach ($entry in $existing) { $entry.Delete() }

    $newEntry = $Zip.CreateEntry('ComicInfo.xml', [System.IO.Compression.CompressionLevel]::Optimal)
    $writer = New-Object System.IO.StreamWriter($newEntry.Open(), [System.Text.Encoding]::UTF8)
    try {
        $writer.Write((Get-ComicInfoXml -Manga $Manga))
    }
    finally {
        $writer.Dispose()
    }
}

function Get-ArchiveOnlyChildren {
    # Returns the archive files directly inside $Dir if it contains only archives
    # and no subfolders (e.g. a folder of one .cbr per issue) - meaning every item
    # in it should be converted on its own rather than the whole folder being
    # wrapped as one .cbz. Returns $null if $Dir doesn't have that shape.
    param([string]$Dir)

    $children = Get-ChildItem -LiteralPath $Dir
    $subDirs = $children | Where-Object { $_.PSIsContainer }
    $archives = $children | Where-Object { -not $_.PSIsContainer -and $_.Extension -in $ArchiveExtensions }
    if ($archives -and -not $subDirs) { return $archives }
    return $null
}

function Resolve-ConversionItems {
    # Walks $Dir looking for real, convertible volumes at whatever depth they sit,
    # returning one work item per volume: a folder (to be zipped whole) or an
    # individual archive file (to be extracted/converted on its own - a folder
    # holding one .cbr per issue must never be wrapped raw into a single .cbz,
    # since that would just embed the unextracted archive bytes rather than actual
    # pages). A folder holding only more folders and no pages/archives of its own
    # is not final - descended into instead.
    param([string]$Dir)

    $children = Get-ChildItem -LiteralPath $Dir
    $subDirs = $children | Where-Object { $_.PSIsContainer }
    $archiveFiles = $children | Where-Object { -not $_.PSIsContainer -and $_.Extension -in $ArchiveExtensions }
    # .cbz is excluded here on purpose: a pack folder re-scanned after a partial
    # earlier run (or after someone points -Path directly at it with -NoRecurse,
    # which writes each volume's .cbz right back inside the pack folder itself)
    # would otherwise look like it has real content and stop being descended into,
    # even though those .cbz files are our own prior output, not source pages.
    $pageFiles = $children | Where-Object { -not $_.PSIsContainer -and $_.Extension -notin $ArchiveExtensions -and $_.Extension -ne '.cbz' }

    if ($pageFiles) {
        # Real pages directly in this folder make it one volume as a whole -
        # everything nested under it (including any further subfolders) is bundled
        # into this one archive, same as a Doraemon "Vol 01" mixing cover pages
        # with "Story ##" subfolders.
        return , [PSCustomObject]@{ Type = 'Folder'; Item = (Get-Item -LiteralPath $Dir) }
    }

    $result = @()
    if ($archiveFiles) {
        $result += $archiveFiles | ForEach-Object { [PSCustomObject]@{ Type = 'Archive'; Item = $_ } }
    }

    if ($subDirs) {
        # Recurse regardless of whether archives were also found directly in this
        # folder, so a folder mixing loose archives with subfolders doesn't silently
        # drop whichever wasn't found first.
        foreach ($sub in $subDirs) {
            $result += Resolve-ConversionItems -Dir $sub.FullName
        }
    }
    elseif (-not $archiveFiles) {
        # Dead-end leaf with nothing recognizable inside (or only a stray .cbz) -
        # still report it as a folder so the normal "no files found" failure
        # explains why, rather than silently producing nothing for it.
        $result += [PSCustomObject]@{ Type = 'Folder'; Item = (Get-Item -LiteralPath $Dir) }
    }

    return $result
}

function Find-RarExtractor {
    # Checks PATH and the default install locations for 7-Zip (preferred - scriptable,
    # predictable flags) and WinRAR's UnRAR, since neither is reliably on PATH by
    # default even when installed. Returns $null if neither is found.
    $candidates = @(
        (Get-Command '7z.exe' -ErrorAction SilentlyContinue).Source
        (Get-Command '7za.exe' -ErrorAction SilentlyContinue).Source
        "$env:ProgramFiles\7-Zip\7z.exe"
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
        (Get-Command 'UnRAR.exe' -ErrorAction SilentlyContinue).Source
        "$env:ProgramFiles\WinRAR\UnRAR.exe"
        "${env:ProgramFiles(x86)}\WinRAR\UnRAR.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    if ($candidates) { return $candidates[0] }
    return $null
}

function Expand-RarArchive {
    # Extracts $RarPath (full paths preserved) into $DestDir, which must already exist.
    param(
        [string]$RarPath,
        [string]$DestDir,
        [string]$ExtractorPath
    )

    if ($ExtractorPath -match '\\7za?\.exe$') {
        & $ExtractorPath x $RarPath "-o$DestDir" -y -bso0 -bsp0 -bse0
    }
    else {
        # UnRAR.exe: "x" keeps the archive's folder structure; needs a trailing
        # backslash to be treated as a destination directory rather than a file mask.
        & $ExtractorPath x -y $RarPath "$DestDir\"
    }

    if ($LASTEXITCODE -ne 0) {
        throw "'$ExtractorPath' exited with code $LASTEXITCODE while extracting '$RarPath'."
    }
}

function New-ComicZip {
    param(
        [string]$SourceDir,
        [string]$DestZip,
        [string]$Manga,
        [string]$RootName = (Split-Path -Leaf $SourceDir)
    )

    $rootName = $RootName
    $tempZip = "$DestZip.tmp"
    if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force }

    # -LiteralPath everywhere below: folder names here can contain [ ], which
    # -Path/positional path parameters treat as wildcard characters, silently
    # matching zero files instead of the literal folder.
    $files = Get-ChildItem -LiteralPath $SourceDir -Recurse -File
    if (-not $files) {
        throw "No files found under '$SourceDir' - refusing to write an empty archive."
    }

    $zip = [System.IO.Compression.ZipFile]::Open($tempZip, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($SourceDir.Length + 1) -replace '\\', '/'
            $entryName = "$rootName/$relative"
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $file.FullName, $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
        Write-ComicInfoEntry -Zip $zip -Manga $Manga
    }
    finally {
        $zip.Dispose()
    }

    Move-Item -LiteralPath $tempZip -Destination $DestZip -Force
}

function Set-CbzReadingDirection {
    param(
        [string]$ZipPath,
        [string]$Manga
    )

    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        Write-ComicInfoEntry -Zip $zip -Manga $Manga
    }
    finally {
        $zip.Dispose()
    }
}

function Convert-FolderToCbz {
    # Shared skip/force/-WhatIf/try-catch wrapper around New-ComicZip, used by every
    # folder-conversion call site (direct-leaf -Path, -NoRecurse's one-level container
    # children, and the default's resolved volume folders) so they report identically.
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [string]$Name
    )

    $dest = Join-Path $DestDir "$Name.cbz"
    if ((Test-Path -LiteralPath $dest) -and -not $Force) {
        Write-Host "SKIP  (exists) $dest"
        return
    }
    if ($PSCmdlet.ShouldProcess($dest, "Create CBZ from folder '$Name'")) {
        try {
            New-ComicZip -SourceDir $SourceDir -DestZip $dest -Manga $MangaValue
            Write-Host "CBZ   $Name -> $(Split-Path -Leaf $dest)"
        }
        catch {
            Write-Host "FAIL  $($Name): $($_.Exception.Message)" -ForegroundColor Red
            $tmp = "$dest.tmp"
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        }
    }
}

# Looked up lazily, the first time a .rar/.cbr is actually encountered, since most
# runs won't have one and this touches PATH/Program Files each time it's needed.
# Cached at script scope so every Convert-RarCbrToCbz call (top-level items and
# anything found while descending the tree) shares one lookup.
$script:RarExtractor = $null
$script:RarExtractorChecked = $false

function Convert-RarCbrToCbz {
    # Always produces .cbz, never .cbr - Kobo/KOReader doesn't support panel zoom on
    # .cbr, which is the whole reason this path exists. RAR has no built-in .NET
    # support, so this needs 7-Zip or WinRAR to extract it first.
    param(
        [System.IO.FileSystemInfo]$Item,
        [string]$DestDir
    )

    $dest = Join-Path $DestDir ([System.IO.Path]::GetFileNameWithoutExtension($Item.Name) + '.cbz')
    if ((Test-Path -LiteralPath $dest) -and -not $Force) {
        Write-Host "SKIP  (exists) $dest"
        return
    }
    if (-not $script:RarExtractorChecked) {
        $script:RarExtractor = Find-RarExtractor
        $script:RarExtractorChecked = $true
    }
    if (-not $PSCmdlet.ShouldProcess($dest, "Extract RAR/CBR to CBZ '$($Item.Name)'")) {
        return
    }
    if (-not $script:RarExtractor) {
        Write-Host "FAIL  $($Item.Name): no RAR extractor found (checked PATH and default install locations for 7-Zip and WinRAR) - install one to convert .rar/.cbr sources." -ForegroundColor Red
        return
    }
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('cca_' + [System.Guid]::NewGuid().ToString('N'))
    try {
        [System.IO.Directory]::CreateDirectory($tempDir) | Out-Null
        Expand-RarArchive -RarPath $Item.FullName -DestDir $tempDir -ExtractorPath $script:RarExtractor
        New-ComicZip -SourceDir $tempDir -DestZip $dest -Manga $MangaValue `
            -RootName ([System.IO.Path]::GetFileNameWithoutExtension($Item.Name))
        Write-Host "CBZ   $($Item.Name) -> $(Split-Path -Leaf $dest)  (extracted from RAR)"
    }
    catch {
        Write-Host "FAIL  $($Item.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    }
}

function Convert-ZipToCbz {
    param(
        [System.IO.FileSystemInfo]$Item,
        [string]$DestDir
    )

    $dest = Join-Path $DestDir ([System.IO.Path]::GetFileNameWithoutExtension($Item.Name) + '.cbz')
    if ((Test-Path -LiteralPath $dest) -and -not $Force) {
        Write-Host "SKIP  (exists) $dest"
        return
    }
    if (-not $PSCmdlet.ShouldProcess($dest, "Copy ZIP to CBZ '$($Item.Name)'")) {
        return
    }
    try {
        Copy-Item -LiteralPath $Item.FullName -Destination $dest -Force
        Set-CbzReadingDirection -ZipPath $dest -Manga $MangaValue
        Write-Host "CBZ   $($Item.Name) -> $(Split-Path -Leaf $dest)"
    }
    catch {
        Write-Host "FAIL  $($Item.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Convert-ArchiveItem {
    # Dispatches to the right converter for $Item's extension. Shared by the
    # top-level per-item loop, -NoRecurse's archive-only container children, and
    # the default's resolved archive work items, so all three report identically.
    param(
        [System.IO.FileSystemInfo]$Item,
        [string]$DestDir
    )

    if ($Item.Extension -ieq '.rar' -or $Item.Extension -ieq '.cbr') {
        Convert-RarCbrToCbz -Item $Item -DestDir $DestDir
    }
    else {
        Convert-ZipToCbz -Item $Item -DestDir $DestDir
    }
}

# A -Path ending in a trailing backslash (e.g. '.\Some Folder\') gets mangled once it
# crosses a native process boundary - which calling through the cca.cmd shim always
# does - because Windows argv parsing treats a backslash immediately before the
# closing quote as an escaped literal quote rather than the string terminator, so the
# quote doesn't close the argument. When -Path is the *last* token on the line, the
# only damage is a stray trailing '"' - stripped below so it self-heals. But when
# something follows it (another flag), that text gets absorbed into this same $Path
# value instead of being parsed as its own argument - which could silently swallow
# -WhatIf without the caller noticing. Detect that shape and fail loudly with the fix
# (reorder so -Path is last) rather than either a cryptic .NET exception or silently
# dropping a flag the caller thought they'd passed.
if ($Path -match '^(?<path>.*)"\s+-(?<flag>\w+)\s*$') {
    throw "-Path '$($Matches.path)' has a trailing backslash and was followed by -$($Matches.flag) on the command line. " +
        "A native process boundary (the cca.cmd shim) mangles that combination and would silently drop -$($Matches.flag) - " +
        "move -Path to the end of the command instead, e.g.: cca -$($Matches.flag) -Path '$($Matches.path)\'"
}
$Path = $Path.TrimEnd('"', '\', '/')

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Path not found: $Path"
}
$Path = (Resolve-Path -LiteralPath $Path).Path

# By default, every result - no matter how deep the volume folder it came from - is
# collected flat into one output folder next to -Path, so a mixed tree of packs and
# standalone volumes doesn't scatter output across every nesting level it was found
# at. With -NoRecurse, each converted folder is instead written next to wherever it
# naturally sits (see the two call sites below), matching the old default behavior.
$OutDir = $Path
if (-not $NoRecurse) {
    $OutDir = Join-Path (Split-Path -Parent $Path) "$(Split-Path -Leaf $Path)_output"
    if ((-not (Test-Path -LiteralPath $OutDir)) -and $PSCmdlet.ShouldProcess($OutDir, 'Create output folder')) {
        # New-Item has no -LiteralPath in Windows PowerShell 5.1; use the .NET API
        # directly so an output folder name containing [ ] is never misread as a
        # wildcard pattern.
        [System.IO.Directory]::CreateDirectory($OutDir) | Out-Null
    }
}

$topChildren = Get-ChildItem -LiteralPath $Path
$topHasSubDirs = $topChildren | Where-Object { $_.PSIsContainer }
$topHasArchives = $topChildren | Where-Object { -not $_.PSIsContainer -and $_.Extension -in @('.rar', '.cbr', '.zip', '.cbz') }

if ($topChildren -and -not $topHasSubDirs -and -not $topHasArchives) {
    # -Path itself has no subfolders and isn't just a folder of archive files either,
    # i.e. it holds pages directly rather than being a container of volume/pack
    # folders or a folder of .rar/.zip files - convert -Path itself as a single volume.
    $leafDestDir = if ($NoRecurse) { Split-Path -Parent $Path } else { $OutDir }
    Convert-FolderToCbz -SourceDir $Path -DestDir $leafDestDir -Name (Split-Path -Leaf $Path)
    return
}

$items = $topChildren
if (-not $items) {
    Write-Warning "No items found directly inside '$Path'."
    return
}

foreach ($item in $items) {

    if ($item.PSIsContainer) {
        if ($NoRecurse) {
            $archiveChildren = Get-ArchiveOnlyChildren -Dir $item.FullName
            if ($archiveChildren) {
                # This folder is really just a set of individual archives (e.g. one
                # .cbr per issue), not a volume/pack folder to bundle whole - convert
                # each on its own even under -NoRecurse, since wrapping raw archive
                # bytes into a .cbz would never produce a working comic archive.
                foreach ($archiveItem in $archiveChildren) {
                    Convert-ArchiveItem -Item $archiveItem -DestDir $Path
                }
            }
            else {
                Convert-FolderToCbz -SourceDir $item.FullName -DestDir $Path -Name $item.Name
            }
        }
        else {
            foreach ($work in (Resolve-ConversionItems -Dir $item.FullName)) {
                if ($work.Type -eq 'Folder') {
                    Convert-FolderToCbz -SourceDir $work.Item.FullName -DestDir $OutDir -Name $work.Item.Name
                }
                else {
                    Convert-ArchiveItem -Item $work.Item -DestDir $OutDir
                }
            }
        }
    }
    elseif ($item.Extension -in $ArchiveExtensions) {
        Convert-ArchiveItem -Item $item -DestDir $OutDir
    }
    else {
        Write-Verbose "Ignoring unrelated file: $($item.Name)"
    }
}
