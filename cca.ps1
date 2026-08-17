<#
.SYNOPSIS
    Converts volume folders/.rar/.cbr/.zip into .cbz comic archives. Output is always
    .cbz, even from a .rar/.cbr source - Kobo/KOReader doesn't support panel zoom on
    .cbr, which is the reason this never produces one.

.DESCRIPTION
    Default (no -Recurse): one level only.

    If -Path itself contains no subfolders (i.e. it's a volume folder itself, holding
    pages directly - like "v13" sitting next to a "v01-05" pack folder), it is converted
    on its own into a single sibling .cbz, written next to -Path's parent.

    Otherwise, scans the immediate children of -Path (one level only) and converts each:
      - Folder  -> sibling .cbz, containing the whole folder subtree (including any
                   nested subfolders, at any depth) zipped with the folder name kept
                   as the root entry. Nested folders are NOT split into their own
                   separate archives - only this first level of subfolders is treated
                   as one unit each, so a folder that packs several volumes together
                   (e.g. a "v01-05" folder holding five volume subfolders) becomes one
                   .cbz containing all of them, not one .cbz per volume.
      - .rar/.cbr file -> sibling .cbz. Extracted with 7-Zip or WinRAR (whichever is
                     found - see Requirements) into a temp folder, then re-zipped from
                     there with the same layout .cbz would otherwise have gotten,
                     including the ComicInfo.xml reading-direction entry. Never
                     produces a .cbr - see Requirements if neither tool is found.
      - .zip file -> sibling .cbz (container copied, then a ComicInfo.xml reading-direction
                     entry is added/replaced at the archive root)

    With -Recurse: walks the whole tree under -Path looking for "final" volume folders,
    at whatever depth each one happens to sit, and writes one .cbz per volume into a
    single "<Path's own name>_output" folder created next to -Path. A folder counts as
    a final volume as soon as it contains at least one file directly inside it, or has
    no subfolders left to descend into - so a folder with only loose pages (no
    subfolders) is final immediately, a folder mixing loose pages with subfolders
    (e.g. a Doraemon "Vol 01" holding both its own cover pages and "Story 001",
    "Story 002", ... subfolders) is final as a whole (everything nested included in one
    archive, matching how it's zipped without -Recurse), and a folder holding *only*
    more folders and no files of its own (e.g. a "v01-05" pack with zero loose pages,
    just five volume subfolders) is not final - the script descends into it and repeats
    the check on each subfolder instead. This is what lets one -Recurse run correctly
    turn a "v01-05" pack into 5 separate volume .cbz files while also converting a
    standalone "v13" into its own single .cbz, in the same pass.

    Every generated .cbz gets a ComicInfo.xml file written at the root of the archive
    (a sibling of the top-level folder entry, not nested inside it) so readers like
    KOReader pick up the reading direction automatically. Right-to-left (manga order)
    is the default; pass -LeftToRight to tag it as normal left-to-right reading order
    instead.

    Existing output files are skipped unless -Force is given. Source
    folders/files are never modified or deleted.

.PARAMETER Path
    Directory whose immediate children should be converted (e.g. ".\Digital" or ".\Scan").

.PARAMETER Recurse
    Walk the whole tree under -Path for final volume folders (see above) instead of
    only looking one level deep, writing every resulting .cbz into a single
    "<Path's own name>_output" folder created next to -Path.

.PARAMETER LeftToRight
    Tag the generated ComicInfo.xml as left-to-right reading order instead of the
    default right-to-left (manga) order.

.PARAMETER Force
    Overwrite an existing .cbz/.cbr output if one is already present.

.PARAMETER WhatIf
    Show what would be done without writing anything.

.EXAMPLE
    cca -Path .\Scan

.EXAMPLE
    cca -Path .\Digital -Force

.EXAMPLE
    cca -Path .\SomeWesternComic -LeftToRight

.EXAMPLE
    cca -Path '.\13DL.me_Yotsubato vol 01-15' -Recurse

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

    [switch]$Recurse,

    [switch]$LeftToRight,

    [switch]$Force
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ErrorActionPreference = 'Stop'

$MangaValue = if ($LeftToRight) { 'No' } else { 'YesAndRightToLeft' }

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

function Resolve-VolumeFolders {
    # Descends through folders that contain nothing but more folders (no pages of
    # their own), returning the actual volume folder(s) found at whatever depth
    # each branch bottoms out at. A folder with any non-archive file directly inside
    # it, or with no subfolders at all, is treated as final and not descended into.
    param([string]$Dir)

    $children = Get-ChildItem -LiteralPath $Dir
    # .cbz/.cbr are ignored here on purpose: a pack folder re-scanned after a partial
    # earlier run (or after someone points -Path directly at it, which - without
    # -Recurse - writes each volume's .cbz right back inside the pack folder itself)
    # would otherwise look like it "has its own files" and stop being descended into,
    # even though those files are our own prior output, not source pages.
    $hasFiles = $children | Where-Object { -not $_.PSIsContainer -and $_.Extension -notin @('.cbz', '.cbr') }
    $subDirs = $children | Where-Object { $_.PSIsContainer }

    if ($hasFiles -or -not $subDirs) {
        return , (Get-Item -LiteralPath $Dir)
    }

    $result = @()
    foreach ($sub in $subDirs) {
        $result += Resolve-VolumeFolders -Dir $sub.FullName
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
    # folder-conversion call site (direct-leaf -Path, one-level container children,
    # and -Recurse's resolved volume folders) so they report identically.
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

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Path not found: $Path"
}
$Path = (Resolve-Path -LiteralPath $Path).Path

# Without -Recurse, each converted folder is written next to wherever it naturally
# sits (see the two call sites below). With -Recurse, every result - no matter how
# deep the volume folder it came from - is collected flat into one output folder
# next to -Path, so a mixed tree of packs and standalone volumes doesn't scatter
# output across every nesting level it was found at.
$OutDir = $Path
if ($Recurse) {
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
    $leafDestDir = if ($Recurse) { $OutDir } else { Split-Path -Parent $Path }
    Convert-FolderToCbz -SourceDir $Path -DestDir $leafDestDir -Name (Split-Path -Leaf $Path)
    return
}

$items = $topChildren
if (-not $items) {
    Write-Warning "No items found directly inside '$Path'."
    return
}

# Only looked up if a .rar/.cbr is actually encountered below, since most runs won't
# have one and this touches PATH/Program Files each time it's needed.
$RarExtractor = $null
$RarExtractorChecked = $false

foreach ($item in $items) {

    if ($item.PSIsContainer) {
        if ($Recurse) {
            foreach ($volDir in (Resolve-VolumeFolders -Dir $item.FullName)) {
                Convert-FolderToCbz -SourceDir $volDir.FullName -DestDir $OutDir -Name $volDir.Name
            }
        }
        else {
            Convert-FolderToCbz -SourceDir $item.FullName -DestDir $Path -Name $item.Name
        }
    }
    elseif ($item.Extension -ieq '.rar' -or $item.Extension -ieq '.cbr') {
        # Always converted to .cbz, never .cbr - Kobo/KOReader doesn't support panel
        # zoom on .cbr, which is the whole reason this path exists. RAR has no
        # built-in .NET support, so this needs 7-Zip or WinRAR to extract it first.
        $dest = Join-Path $OutDir ([System.IO.Path]::GetFileNameWithoutExtension($item.Name) + '.cbz')
        if ((Test-Path -LiteralPath $dest) -and -not $Force) {
            Write-Host "SKIP  (exists) $dest"
            continue
        }
        if (-not $RarExtractorChecked) {
            $RarExtractor = Find-RarExtractor
            $RarExtractorChecked = $true
        }
        if ($PSCmdlet.ShouldProcess($dest, "Extract RAR/CBR to CBZ '$($item.Name)'")) {
            if (-not $RarExtractor) {
                Write-Host "FAIL  $($item.Name): no RAR extractor found (checked PATH and default install locations for 7-Zip and WinRAR) - install one to convert .rar/.cbr sources." -ForegroundColor Red
                continue
            }
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('cca_' + [System.Guid]::NewGuid().ToString('N'))
            try {
                [System.IO.Directory]::CreateDirectory($tempDir) | Out-Null
                Expand-RarArchive -RarPath $item.FullName -DestDir $tempDir -ExtractorPath $RarExtractor
                New-ComicZip -SourceDir $tempDir -DestZip $dest -Manga $MangaValue `
                    -RootName ([System.IO.Path]::GetFileNameWithoutExtension($item.Name))
                Write-Host "CBZ   $($item.Name) -> $(Split-Path -Leaf $dest)  (extracted from RAR)"
            }
            catch {
                Write-Host "FAIL  $($item.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
            finally {
                if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
            }
        }
    }
    elseif ($item.Extension -ieq '.zip') {
        $dest = Join-Path $OutDir ([System.IO.Path]::GetFileNameWithoutExtension($item.Name) + '.cbz')
        if ((Test-Path -LiteralPath $dest) -and -not $Force) {
            Write-Host "SKIP  (exists) $dest"
            continue
        }
        if ($PSCmdlet.ShouldProcess($dest, "Copy ZIP to CBZ '$($item.Name)'")) {
            try {
                Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
                Set-CbzReadingDirection -ZipPath $dest -Manga $MangaValue
                Write-Host "CBZ   $($item.Name) -> $(Split-Path -Leaf $dest)"
            }
            catch {
                Write-Host "FAIL  $($item.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Verbose "Ignoring unrelated file: $($item.Name)"
    }
}
