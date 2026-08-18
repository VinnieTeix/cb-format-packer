# cb-format-packer

A small PowerShell script that packs comic folders/archives into `.cbz`, with right-to-left (manga) reading order set by default.

**Output is always `.cbz`, never `.cbr` — even when the source is a `.rar`/`.cbr`.** This is deliberate: Kobo (and KOReader on it) doesn't support zooming in on panels for `.cbr` files, only `.cbz`. A `.rar`/`.cbr` source is extracted and re-zipped into a proper `.cbz` rather than just renamed.

## Installation

Run once, from inside a clone of this repo:

```powershell
.\install.ps1
```

This adds a `cca` command to your User `PATH` (default location: `%LOCALAPPDATA%\cca`). It's a small `cca.cmd` shim that always calls this repo's `cca.ps1` by its full path, so pulling updates to the repo takes effect immediately — no need to rerun `install.ps1` unless you move the repo. (A bare `.ps1` file can't be run by typing its name alone — Windows `PATHEXT` doesn't include `.PS1` by design — hence the `.cmd` shim, which resolves from PowerShell, `cmd.exe`, or Win+R alike.)

Open a **new** terminal after installing (already-open ones won't see the `PATH` change). From then on, run it as `cca` from anywhere, e.g. `cca -Path .\Scan`. Without installing, you can still always run it directly as `.\cca.ps1` with the same parameters.

## What it does

Given a directory, by default it walks the **whole tree** underneath looking for real volume folders/archives at whatever depth they happen to sit, and converts each one:

| Input | Output | How |
|---|---|---|
| Folder | `<name>.cbz` | Whole folder zipped as one archive, with the folder name kept as the root entry inside the zip. |
| `.rar`/`.cbr` file | `<name>.cbz` — **never `.cbr`** | Extracted with 7-Zip or WinRAR (whichever is found — see Requirements) into a temp folder, then re-zipped from there exactly like a folder source would be, `ComicInfo.xml` included. See "Why always `.cbz`, even from RAR" below. |
| `.zip` file | `<name>.cbz` | Copied and renamed — a CBZ *is* a ZIP file — then a `ComicInfo.xml` reading-direction entry is added/replaced at the archive root. |
| Anything else | ignored | left untouched |

Source folders/files are **never modified or deleted** — outputs are written as new files, collected into one `<Path's own name>_output` folder next to `-Path`.

### Auto-detecting real volume folders at any depth

A folder counts as a real, convertible volume as soon as it has at least one page file directly inside it, or has no subfolders left to descend into. A folder holding *only* more folders and no pages of its own is **not** a real volume — the script descends into it and repeats the check on each subfolder instead. This tells apart a folder that mixes loose pages with subfolders (a real single volume, like a Doraemon `Vol 01` holding both its own cover pages and `Story 001`, `Story 002`, ... subfolders — zipped whole, as one unit) from a folder that's *purely* a container bundling several volumes together (a `v01-05` pack with no pages of its own, just five volume subfolders — not zipped as-is, descended into instead).

This means one run over a mixed tree — a `v01-05` pack sitting next to a standalone `v13` — correctly turns the pack into 5 separate volume `.cbz` files while also converting `v13` into its own single `.cbz`, all in the same pass, regardless of how deep each one happens to be nested:

```powershell
cca -Path '.\13DL.me_Yotsubato vol 01-15'
# -> .\13DL.me_Yotsubato vol 01-15_output\<volume>.cbz for all 15 volumes
```

(`.cbz`/`.cbr` files already sitting inside a folder are ignored when deciding whether that folder "has its own pages" — otherwise re-running this after a partial run, or after converting a pack folder with `-NoRecurse` once, would leave its own prior output looking like real page content and stop it from being descended into correctly next time.)

**Watch out for genuinely overlapping releases.** Auto-detection assumes each real volume appears exactly once somewhere in the tree — it has no way to know that, say, a `v01-05` omnibus pack and a separately-provided standalone `v01` folder both contain the same volume 1. If a release provides the same content multiple ways (a full pack *and* individual/partial packs of the same volumes, or a `v06` next to a corrected `v06 fix`), running this as-is converts *all* of them, duplicates included. Sort out which folder to keep per volume first in cases like that, rather than pointing this at the whole tree blind.

### -NoRecurse: one level only, no auto-detection

Scans just the immediate children of `-Path` and converts each as one archive, without looking inside them for real volume boundaries — so a folder that packs several volumes together (e.g. a `v01-05` folder holding five volume subfolders) becomes **one** `.cbz` containing all of them, not one `.cbz` per volume. Each result is written next to wherever that folder naturally sits, not collected into an `_output` folder:

```powershell
cca -Path .\Scan -NoRecurse
```

Useful when a release's folders don't map one-to-one with real volumes in a way auto-detection can't safely resolve on its own (see "overlapping releases" above) — convert the group as a single bundle instead of guessing.

### Why always .cbz, even from RAR

A `.rar`/`.cbr` source is never just renamed to `.cbr` — it's extracted and re-zipped into `.cbz`, because Kobo (and KOReader running on it) can't zoom in on individual panels in a `.cbr` file, only `.cbz`. That's the entire reason this repo exists in its current form, so it's worth keeping in mind if you ever add a source type: the "just rename the container" shortcut that works for `.zip → .cbz` (same underlying format, no recompression needed) does **not** apply to RAR, both because RAR and ZIP are different formats and because a `.cbr` output would defeat the point.

Since RAR has no built-in .NET support (unlike ZIP), this requires **7-Zip or WinRAR to already be installed** — checked on `PATH` and in their default `Program Files` locations, 7-Zip preferred if both are present. If neither is found, that `.rar`/`.cbr` is reported as `FAIL` and skipped; everything else in the same run still proceeds normally.

### Pointing -Path directly at a single volume folder

If `-Path` itself has no subfolders *and* isn't just a folder of `.rar`/`.cbr`/`.zip`/`.cbz` files either (it holds pages directly rather than being a container of volume/pack folders or archive files — e.g. you run the script from inside a folder of volume folders and point it straight at one specific volume, `.\v13\`), that folder is converted on its own into one `.cbz` — into an `_output` folder next to it by default, or next to its parent with `-NoRecurse`, same as everywhere else. Pointing `-Path` straight at a folder containing nothing but a handful of `.rar`/`.cbr` files (no subfolders) still converts each of them individually rather than wrapping them all into one `.cbz` together. This only kicks in when `-Path` has zero subfolders and zero archive files directly inside it, so it never changes how a container folder is handled — pointing `-Path` at a folder that holds several volume/pack folders still gets scanned normally, same as always.

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
cca -Path .\Scan
```

Converts every real volume folder/.rar/.cbr/.zip found anywhere under `.\Scan` into a matching `.cbz` (never `.cbr`) in `.\Scan_output`, tagged right-to-left by default.

### Options

- `-NoRecurse` — only look one level deep, converting each top-level folder as a single bundle rather than auto-detecting volume boundaries inside it; see above
- `-LeftToRight` — tag the batch as left-to-right instead of the default right-to-left
- `-Force` — overwrite an output file that already exists (default: skip it)
- `-WhatIf` — preview what would be created/overwritten without writing anything

```powershell
# Preview only
cca -Path .\Digital -WhatIf

# A Western comic that should read left-to-right
cca -Path .\SomeWesternComic -LeftToRight

# Re-convert everything, overwriting existing .cbz files
cca -Path .\Digital -Force
```

## Requirements

- Windows PowerShell 5.1+ (uses the built-in `System.IO.Compression` assemblies for the `.cbz` side — no external tool needed for folder/`.zip` sources).
- **7-Zip or WinRAR**, only if you have `.rar`/`.cbr` sources to convert — RAR has no built-in .NET support for reading it, so one of these has to do the actual extraction. Not needed at all if your sources are only folders or `.zip` files.

## Notes on folder names with `[`, `]`, or other wildcard characters

Internally the script always resolves paths with `-LiteralPath` rather than `-Path`, since PowerShell treats `[`/`]` in a `-Path` argument as a wildcard character class rather than literal characters — a source folder named e.g. `[Author] Some Manga` would otherwise silently match zero files and produce an empty archive. If a run ever fails, it now prints a `FAIL <name>: <reason>` line and moves on to the next item rather than reporting a false success.

## Note on a trailing backslash in `-Path` (e.g. tab-completed paths)

Calling `cca` (the installed command) always crosses a native process boundary — that's what the `cca.cmd` shim is. If `-Path` ends in a backslash (`'.\Some Folder\'`, which is exactly what PowerShell tab-completion produces for a directory) *and* something else follows it on the command line, Windows argv parsing treats that trailing `\"` as an escaped literal quote instead of the string terminator, silently absorbing whatever comes next into the same `-Path` value — which could mean a flag like `-WhatIf` never actually takes effect. `cca` detects that specific shape and fails loudly with the fix (put `-Path` last: `cca -Force -Path '...\Some Folder\'` instead of `cca -Path '...\Some Folder\' -Force`) rather than silently dropping the flag. With `-Path` as the only or last argument, a trailing backslash is handled fine either way. Running `.\cca.ps1` directly (no shim) is never affected by this at all, since there's no process boundary to cross.
