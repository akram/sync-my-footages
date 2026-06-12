# Sync My Footages — User Guide

## Overview

Sync My Footages is a macOS menu bar app that automatically detects DJI cameras and SD cards, then syncs your video rushes to external drives with full integrity tracking.

## Menu Bar Popover

Click the app icon in the menu bar to open the popover:

- **Connected devices** — each detected DJI device with its volume name and storage type
- **Sync button** — click to start syncing, or click the dropdown arrow for options:
  - **Configure sync** — open the full sync configuration window
  - **Saved destinations** — sync to a specific destination
  - **Eject** — safely eject the device
- **Active Syncs** — progress of running syncs with cancel button
- **Clear** — remove completed/failed syncs from the list
- **More** — access Dashboard, Duplicates, Projects, Settings, Demo Mode, Quit

## Sync Flow

1. The app scans the device's DCIM folders for DJI files
2. Checks each file against the destination (by filename + size)
3. Files already present in titled folders (e.g. `20251222 - Morocco Trip/videos/`) are recognized and skipped
4. New files are copied using `FileManager.copyItem` (fastest possible)
5. For files > 500 MB, progress is displayed in real-time by polling the destination file size
6. After copying, SHA256 checksums are computed and cached
7. PROJECT.md titles are applied to date folders
8. Finder is refreshed to show the changes

## File Organization

### Pattern Tokens

Configure the organization pattern in Settings > Sync:

| Token | Example | Description |
|-------|---------|-------------|
| `{device}` | `OsmoPocket3` | Camera model name |
| `{year}` | `2025` | Capture year |
| `{month}` | `12` | Capture month |
| `{day}` | `22` | Capture day |
| `{type}` | `videos` | File type folder |

Default pattern: `{device}/{year}{month}{day}/{type}`

Example result:
```
OsmoPocket3/
  20251222/
    videos/
      DJI_20251222073342_0001_D.MP4
    audios/
      DJI_20251222073342_0001_D.WAV
    lowres/
      DJI_20251222073342_0001_D.LRF
    photos/
      DJI_20251222073342_0007_D.JPG
```

### File Type Mapping

Configure which extensions go to which folder in Settings > File Types:

| Folder | Extensions |
|--------|-----------|
| `videos` | MP4, MOV |
| `lowres` | LRF |
| `audios` | WAV, AAC, MP3 |
| `photos` | JPG, JPEG, DNG, PNG, TIFF |

You can rename folders (e.g. `videos` to `rushes`), add new types, and move extensions between categories.

### Reorganize

Click **Reorganize folder** in Settings > Sync to move existing files to match a new pattern. This only renames/moves files on the same disk — no data is copied.

The reorganize is idempotent: running it multiple times produces the same result.

## PROJECT.md

Create a `PROJECT.md` file in any date folder to give it a project name:

```markdown
---
title: Morocco Trip
client: Personal
tags: travel, drone
---
Optional notes about the project.
```

### How it works

1. Place `PROJECT.md` in a date folder (e.g. `OsmoPocket3/20251222/PROJECT.md`)
2. Run **Reorganize** (Settings > Sync) or **Sync** a device
3. The folder is renamed: `20251222` becomes `20251222 - Morocco Trip`
4. The rename is idempotent — running again won't break anything
5. Files inside titled folders are recognized as correctly placed

### Apply Projects

Use More > Projects to scan a destination and apply all PROJECT.md titles at once. You can also configure the separator (default: ` - `).

## Journal System

Every synced file is tracked by SHA256 checksum in two places:

### Centralized Journal

SQLite database at `~/.sync-my-footages/journal.db` (via SwiftData). Provides:
- Global view of all files across all disks
- Redundancy tracking (which files exist on which disks)
- Duplicate detection

### Decentralized Journal

JSON file `.rsync-footages.journal` at the root of each destination disk. Contains:
- SHA256, filename, size, capture date, sync timestamp
- Relative paths (portable across mount points)
- Human-readable format

### Hash Cache

Persistent cache at `~/.sync-my-footages/hash-cache.json`. Maps `filename|size|moddate` to SHA256. Avoids re-hashing files that haven't changed.

## Performance

- **Source change detection** — if the DCIM folder hasn't been modified since last sync (tracked by Volume UUID + modification timestamp), the sync is skipped instantly
- **Directory cache** — the destination is scanned once at sync start and indexed in memory
- **Hash cache** — SHA256 checksums are cached persistently, no re-computation
- **Direct copy** — uses `FileManager.copyItem` (kernel-optimized `fcopyfile`) instead of rsync
- **Large file progress** — for files > 500 MB, polls destination file size every 500ms for live progress

## Duplicate Scanner

Access via More > Duplicates:

1. Select a folder to scan
2. Files are grouped by name + size (fast)
3. Only potential duplicates are hashed with SHA256 (targeted)
4. Results show duplicate groups with wasted space
5. Select duplicates to delete, keeping the first copy

## Destinations

Configure in Settings > Destinations:

- Add multiple destination disks
- Mark disks as "Backup" for parallel sync
- Open in Finder button for each destination
- Destinations are persisted between app restarts
- Selected destinations per device type are remembered

## Device Detection

The app detects DJI devices by:

1. Monitoring volume mounts via DiskArbitration framework
2. Checking for `DCIM/DJI_xxx/` folder structure
3. Reading the encoder tag (`@too`) from the first MP4 file to identify the camera model
4. Volumes with a `.rsync-footages.journal` file are recognized as destinations, not sources

## Demo Mode

Access via More > Demo Mode. Creates fake DJI files in `~/.sync-my-footages/demo/` for testing without real hardware. Includes:
- Simulated device with DJI files across multiple dates
- Simulated destination with some pre-existing files
- A sample PROJECT.md

## Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run tests
swift test

# Package as .app + DMG
bash scripts/package.sh
```
