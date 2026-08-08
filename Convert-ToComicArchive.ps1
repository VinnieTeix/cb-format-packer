<#
.SYNOPSIS
    Converts volume folders/.rar/.zip files into .cbz/.cbr comic archives.

.DESCRIPTION
    Scans the immediate children of -Path (one level only) and converts each:
      - Folder  -> sibling .cbz, containing the whole folder subtree (including any
                   nested "Story ##" subfolders) zipped with the folder name kept as
                   the root entry, exactly like the hand-made Digital\Vol 00.cbz etc.
                   Nested folders are NOT split into their own separate archives -
                   only this first level of subfolders is treated as one unit each.
      - .rar file -> sibling .cbr (container rename only, RAR data is untouched)
      - .zip file -> sibling .cbz (container rename only, ZIP data is untouched)

    Existing output files are skipped unless -Force is given. Source
    folders/files are never modified or deleted.

.PARAMETER Path
    Directory whose immediate children should be converted (e.g. ".\Digital" or ".\Scan").

.PARAMETER Force
    Overwrite an existing .cbz/.cbr output if one is already present.

.PARAMETER WhatIf
    Show what would be done without writing anything.

.EXAMPLE
    .\Convert-ToComicArchive.ps1 -Path .\Scan

.EXAMPLE
    .\Convert-ToComicArchive.ps1 -Path .\Digital -Force
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$Force
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-ComicZip {
    param(
        [string]$SourceDir,
        [string]$DestZip
    )

    $rootName = Split-Path -Leaf $SourceDir
    $tempZip = "$DestZip.tmp"
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }

    $zip = [System.IO.Compression.ZipFile]::Open($tempZip, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $files = Get-ChildItem -Path $SourceDir -Recurse -File
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($SourceDir.Length + 1) -replace '\\', '/'
            $entryName = "$rootName/$relative"
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $file.FullName, $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    }
    finally {
        $zip.Dispose()
    }

    Move-Item -Path $tempZip -Destination $DestZip -Force
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
            Write-Host "CBZ   $($item.Name) -> $(Split-Path -Leaf $dest)"
            New-ComicZip -SourceDir $item.FullName -DestZip $dest
        }
    }
    elseif ($item.Extension -ieq '.rar') {
        $dest = Join-Path $Path ([System.IO.Path]::GetFileNameWithoutExtension($item.Name) + '.cbr')
        if ((Test-Path -LiteralPath $dest) -and -not $Force) {
            Write-Host "SKIP  (exists) $dest"
            continue
        }
        if ($PSCmdlet.ShouldProcess($dest, "Copy RAR to CBR '$($item.Name)'")) {
            Write-Host "CBR   $($item.Name) -> $(Split-Path -Leaf $dest)"
            Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
        }
    }
    elseif ($item.Extension -ieq '.zip') {
        $dest = Join-Path $Path ([System.IO.Path]::GetFileNameWithoutExtension($item.Name) + '.cbz')
        if ((Test-Path -LiteralPath $dest) -and -not $Force) {
            Write-Host "SKIP  (exists) $dest"
            continue
        }
        if ($PSCmdlet.ShouldProcess($dest, "Copy ZIP to CBZ '$($item.Name)'")) {
            Write-Host "CBZ   $($item.Name) -> $(Split-Path -Leaf $dest)"
            Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
        }
    }
    else {
        Write-Verbose "Ignoring unrelated file: $($item.Name)"
    }
}
