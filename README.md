# cb-format-packer

A small PowerShell script that packs comic folders/archives into the `.cbz`/`.cbr` formats used by comic readers (Kobo, ComicRack, etc.).

## What it does

Given a directory, it looks at that directory's **immediate children only** (one level deep — it never recurses further to look for more things to convert) and converts each one:

| Input | Output | How |
|---|---|---|
| Folder | `<name>.cbz` | Whole folder zipped as one archive, with the folder name kept as the root entry inside the zip. Anything nested further down (e.g. per-story subfolders) is included as-is — it does **not** get split into separate archives. |
| `.rar` file | `<name>.cbr` | Copied and renamed — a CBR *is* a RAR file, so no recompression happens. |
| `.zip` file | `<name>.cbz` | Copied and renamed — a CBZ *is* a ZIP file, so no recompression happens. |
| Anything else | ignored | left untouched |

Source folders/files are **never modified or deleted** — outputs are written as new sibling files.

### Why only one level deep?

This matches how these archives are meant to be read: a "volume" is one folder, and everything under it (chapters, story subfolders, cover scans, etc.) belongs inside that single archive. Comic readers sort by full path within the archive, so nested subfolders read in order fine without needing their own separate files. Splitting on every nested folder would instead produce one archive per chapter, which is not what you want when you're archiving whole volumes.

## Usage

```powershell
.\Convert-ToComicArchive.ps1 -Path .\Scan
```

Converts every folder/.rar/.zip directly inside `.\Scan` into a matching `.cbz`/`.cbr` next to it.

### Options

- `-Force` — overwrite an output file that already exists (default: skip it)
- `-WhatIf` — preview what would be created/overwritten without writing anything

```powershell
# Preview only
.\Convert-ToComicArchive.ps1 -Path .\Digital -WhatIf

# Re-convert everything, overwriting existing .cbz/.cbr files
.\Convert-ToComicArchive.ps1 -Path .\Digital -Force
```

## Requirements

Windows PowerShell 5.1+ (uses the built-in `System.IO.Compression` assemblies — no external tools like 7-Zip or WinRAR needed).
