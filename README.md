# cb-format-packer

A small PowerShell script that packs comic folders/archives into the `.cbz`/`.cbr` formats used by comic readers (Kobo, ComicRack, KOReader, etc.), with right-to-left (manga) reading order set by default.

## What it does

Given a directory, it looks at that directory's **immediate children** and converts each one:

| Input | Output | How |
|---|---|---|
| Folder | one or more `<name>.cbz` | See "Resolving volumes" below. |
| `.rar` file | `<name>.cbr` | Copied and renamed — a CBR *is* a RAR file, so no recompression happens. Reading-direction metadata is **not** embedded for this case (no built-in .NET support for writing RAR archives). |
| `.zip` file | `<name>.cbz` | Copied and renamed — a CBZ *is* a ZIP file — then a `ComicInfo.xml` reading-direction entry is added/replaced at the archive root. |
| Anything else | ignored | left untouched |

Source folders/files are **never modified or deleted** — outputs are written as new sibling files.

### Resolving volumes

A folder is treated as one real "volume" (and zipped whole into a single `.cbz`, folder name kept as the root entry inside the zip) as soon as it contains at least one file directly inside it, or has no subfolders left to descend into. Everything nested further down (e.g. per-story subfolders) is included as-is inside that one archive — it does **not** get split further.

If a folder instead contains *only* subfolders and no files of its own — a pure grouping folder, e.g. a release that bundles `v01-05/` with five volume folders inside and no loose pages at the `v01-05` level — the script descends into it and repeats the check on each subfolder instead. This means a release that mixes flat volumes and grouped volumes under the same parent still resolves to exactly one `.cbz` per real volume. All resulting `.cbz` files are written flat, next to the folder you pointed the script at.

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
