# cb-format-packer

A small PowerShell script that packs comic folders/archives into the `.cbz`/`.cbr` formats used by comic readers (Kobo, ComicRack, KOReader, etc.), with right-to-left (manga) reading order set by default.

## What it does

Given a directory, it looks at that directory's **immediate children only** (one level deep — it never recurses further to look for more things to convert) and converts each one:

| Input | Output | How |
|---|---|---|
| Folder | `<name>.cbz` | Whole folder zipped as one archive, with the folder name kept as the root entry inside the zip. Anything nested further down (e.g. per-story subfolders, or a folder that packs several volumes together like `v01-05/`) is included as-is — it does **not** get split into separate archives. |
| `.rar` file | `<name>.cbr` | Copied and renamed — a CBR *is* a RAR file, so no recompression happens. Reading-direction metadata is **not** embedded for this case (no built-in .NET support for writing RAR archives). |
| `.zip` file | `<name>.cbz` | Copied and renamed — a CBZ *is* a ZIP file — then a `ComicInfo.xml` reading-direction entry is added/replaced at the archive root. |
| Anything else | ignored | left untouched |

Source folders/files are **never modified or deleted** — outputs are written as new sibling files.

### Why only one level deep?

A "volume" (or a bundle of volumes released together, e.g. a `v01-05/` folder) is one folder, and everything under it belongs inside that single archive. Comic readers sort by full path within the archive, so nested subfolders read in order fine without needing their own separate files. If you want a folder that bundles several volumes to become one `.cbz` per volume instead, point the script at that bundling folder's *parent* so each volume folder is what gets scanned at the top level — the script won't split a bundle for you.

### Pointing -Path directly at a single volume folder

If `-Path` itself has no subfolders (it holds pages directly rather than being a container of volume/pack folders — e.g. you run the script from inside a folder of volume folders and point it straight at one specific volume, `.\v13\`), that folder is converted on its own into one `.cbz` written next to its parent. This only kicks in when `-Path` has zero subfolders, so it never changes how a container folder is handled — pointing `-Path` at a folder that holds several volume/pack folders still converts each of *those* into its own `.cbz`, same as always.

### Reading direction (ComicInfo.xml)

Every generated `.cbz` gets a `ComicInfo.xml` written at the root of the archive (a sibling of the top-level folder entry, not nested inside it), e.g.:

```xml
<?xml version="1.0" encoding="utf-8"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Manga>YesAndRightToLeft</Manga>
</ComicInfo>
```

Readers that support it (KOReader, Kavita, Komga, ComicRack, ...) pick up the direction automatically instead of defaulting to left-to-right. Pass `-LeftToRight` to tag a batch as normal left-to-right order (`<Manga>No</Manga>`) instead.

## Usage

```powershell
.\Convert-ToComicArchive.ps1 -Path .\Scan
```

Converts every folder/.rar/.zip directly inside `.\Scan` into a matching `.cbz`/`.cbr` next to it, tagged right-to-left by default.

### Options

- `-LeftToRight` — tag the batch as left-to-right instead of the default right-to-left
- `-Force` — overwrite an output file that already exists (default: skip it)
- `-WhatIf` — preview what would be created/overwritten without writing anything

```powershell
# Preview only
.\Convert-ToComicArchive.ps1 -Path .\Digital -WhatIf

# A Western comic that should read left-to-right
.\Convert-ToComicArchive.ps1 -Path .\SomeWesternComic -LeftToRight

# Re-convert everything, overwriting existing .cbz/.cbr files
.\Convert-ToComicArchive.ps1 -Path .\Digital -Force
```

## Requirements

Windows PowerShell 5.1+ (uses the built-in `System.IO.Compression` assemblies — no external tools like 7-Zip or WinRAR needed).

## Notes on folder names with `[`, `]`, or other wildcard characters

Internally the script always resolves paths with `-LiteralPath` rather than `-Path`, since PowerShell treats `[`/`]` in a `-Path` argument as a wildcard character class rather than literal characters — a source folder named e.g. `[Author] Some Manga` would otherwise silently match zero files and produce an empty archive. If a run ever fails, it now prints a `FAIL <name>: <reason>` line and moves on to the next item rather than reporting a false success.
