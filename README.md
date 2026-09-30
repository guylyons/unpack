# Unpack

A drag-and-drop archive extractor for macOS, with a SwiftUI + Liquid Glass front end.

Drop archives on the window or the Dock icon (or use **Open With → Unpack** in Finder)
and they're expanded next to the original. RAR/RAR5, 7z, zip, tar, gz, bz2, xz, zstd, ISO,
DMG, CAB, LZH, ARJ and ~50 other formats are supported via a bundled copy of 7-Zip.

## What it does

- **Smart folders**: if an archive holds a single item it goes straight into the
  destination, otherwise everything lands in a folder named after the archive. Name clashes
  become "Photos 2", "Photos 3", and so on, like Finder.
- **Tarballs in one step**: `.tar.gz`, `.tgz`, `.tar.xz` and similar come out as files, not a `.tar`.
- **Multi-part archives**: drop the whole set (`.part1.rar`, `.part2.rar`, …, `.7z.001`, …)
  and only the first volume is extracted. The others are pulled in automatically.
- **Passwords**: encrypted archives prompt for a password. A password that works is tried
  automatically on the next locked archive in the session.
- **Safe on failure**: extraction happens in a hidden staging folder, so a cancelled or
  failed run leaves nothing behind.
- **Settings**: destination (beside the archive, a fixed folder, or ask each time),
  reveal in Finder, move the archive to the Trash, and quit when done.

## Building

Requires Xcode 26+ and macOS 26+ (Liquid Glass APIs).

```sh
xcodegen generate          # only needed after editing project.yml
open Unpack.xcodeproj
```

or from the command line:

```sh
xcodebuild -project Unpack.xcodeproj -scheme Unpack build
xcodebuild -project Unpack.xcodeproj -scheme Unpack test
```

The project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The generated `Unpack.xcodeproj` is checked in so it opens without XcodeGen installed.

## Layout

| Path | What's there |
| --- | --- |
| `Unpack/Engine` | Backends (`SevenZipEngine`, `LibarchiveEngine` fallback), the `Extractor` staging/placement logic, filename and volume rules |
| `Unpack/Model` | `JobQueue` (runs 2 jobs at a time, passwords, post-actions), `ExtractionJob`, preferences |
| `Unpack/Views` | Drop zone, job list, password sheet, settings |
| `Unpack/Resources` | `AppIcon.icon` (Icon Composer), asset catalog, Info.plist with archive document types |
| `Vendor/7zip` | The 7-Zip console binary (`7zz`, universal) and its license |
| `UnpackTests` | Swift Testing: naming rules, output parsing, and end-to-end extraction through real archives |

## The engine

`Engines.preferred()` picks, in order: the `7zz` bundled in `Unpack.app/Contents/MacOS`,
a Homebrew `7zz`, then `/usr/bin/bsdtar` (libarchive, built into macOS, with no progress reporting).
Swap or add backends by conforming to `ArchiveEngine`.

To update the bundled 7-Zip: `scripts/update-7zip.sh 2603` (for 26.03).

## Distribution notes

- The app is **not sandboxed**: writing next to a dropped archive needs access to its folder,
  and the sandbox only grants access to the file itself. That rules out the Mac App Store as-is.
  Distribute with a Developer ID and notarization instead. Set `DEVELOPMENT_TEAM` in `project.yml`.
- 7-Zip is LGPL with the unRAR restriction: redistribution is fine, and `License.txt` ships
  inside the app. The unRAR code may not be used to *create* RAR archives.
