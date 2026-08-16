<#
.SYNOPSIS
    Converts volume folders/.rar/.zip files into .cbz/.cbr comic archives.

.DESCRIPTION
    Scans the immediate children of -Path (one level only) and converts each:
      - Folder  -> sibling .cbz, containing the whole folder subtree (including any
                   nested subfolders, at any depth) zipped with the folder name kept
                   as the root entry. Nested folders are NOT split into their own
                   separate archives - only this first level of subfolders is treated
                   as one unit each, so a folder that packs several volumes together
                   (e.g. a "v01-05" folder holding five volume subfolders) becomes one
                   .cbz containing all of them, not one .cbz per volume.
      - .rar file -> sibling .cbr (container rename only, RAR data is untouched -
                     reading-direction metadata is NOT embedded for this case, see below)
      - .zip file -> sibling .cbz (container copied, then a ComicInfo.xml reading-direction
                     entry is added/replaced at the archive root)

    Every generated .cbz gets a ComicInfo.xml file written at the root of the archive
    (a sibling of the top-level folder entry, not nested inside it) so readers like
    KOReader pick up the reading direction automatically. Right-to-left (manga order)
    is the default; pass -LeftToRight to tag it as normal left-to-right reading order
    instead. This cannot be done for a plain .rar->.cbr container rename, since there's
    no built-in .NET support for writing RAR archives.

    Existing output files are skipped unless -Force is given. Source
    folders/files are never modified or deleted.

.PARAMETER Path
    Directory whose immediate children should be converted (e.g. ".\Digital" or ".\Scan").

.PARAMETER LeftToRight
    Tag the generated ComicInfo.xml as left-to-right reading order instead of the
    default right-to-left (manga) order.

.PARAMETER Force
    Overwrite an existing .cbz/.cbr output if one is already present.

.PARAMETER WhatIf
    Show what would be done without writing anything.

.EXAMPLE
    .\Convert-ToComicArchive.ps1 -Path .\Scan

.EXAMPLE
    .\Convert-ToComicArchive.ps1 -Path .\Digital -Force

.EXAMPLE
    .\Convert-ToComicArchive.ps1 -Path .\SomeWesternComic -LeftToRight
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

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

function New-ComicZip {
    param(
        [string]$SourceDir,
        [string]$DestZip,
        [string]$Manga
    )

    $rootName = Split-Path -Leaf $SourceDir
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

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Path not found: $Path"
}
$Path = (Resolve-Path -LiteralPath $Path).Path

$items = Get-ChildItem -LiteralPath $Path
if (-not $items) {
    Write-Warning "No items found directly inside '$Path'."
    return
}

foreach ($item in $items) {

    if ($item.PSIsContainer) {
        $dest = Join-Path $Path "$($item.Name).cbz"
        if ((Test-Path -LiteralPath $dest) -and -not $Force) {
            Write-Host "SKIP  (exists) $dest"
            continue
        }
        if ($PSCmdlet.ShouldProcess($dest, "Create CBZ from folder '$($item.Name)'")) {
            try {
                New-ComicZip -SourceDir $item.FullName -DestZip $dest -Manga $MangaValue
                Write-Host "CBZ   $($item.Name) -> $(Split-Path -Leaf $dest)"
            }
            catch {
                Write-Host "FAIL  $($item.Name): $($_.Exception.Message)" -ForegroundColor Red
                $tmp = "$dest.tmp"
                if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
            }
        }
    }
    elseif ($item.Extension -ieq '.rar') {
        $dest = Join-Path $Path ([System.IO.Path]::GetFileNameWithoutExtension($item.Name) + '.cbr')
        if ((Test-Path -LiteralPath $dest) -and -not $Force) {
            Write-Host "SKIP  (exists) $dest"
            continue
        }
        if ($PSCmdlet.ShouldProcess($dest, "Copy RAR to CBR '$($item.Name)'")) {
            try {
                Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
                Write-Host "CBR   $($item.Name) -> $(Split-Path -Leaf $dest)  (reading direction NOT embedded - RAR)"
            }
            catch {
                Write-Host "FAIL  $($item.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    elseif ($item.Extension -ieq '.zip') {
        $dest = Join-Path $Path ([System.IO.Path]::GetFileNameWithoutExtension($item.Name) + '.cbz')
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
