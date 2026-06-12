# Sync My Footages

## Overview

Native macOS menu bar app (SwiftUI) for syncing DJI video rushes to external drives with SHA256 tracking.

## Build & Run

```bash
swift build && .build/debug/RsyncMyFootages
```

## Test

```bash
swift test
```

## Architecture

- **SwiftUI MenuBarExtra** — menu bar app with popover, no dock icon
- **Windows opened via AppKit** (`WindowManager`) — SwiftUI `openWindow` doesn't work from MenuBarExtra
- **Swift Package Manager** — no Xcode project needed
- **Target**: macOS 15+, Swift 6.0

## Key Design Decisions

- **rsync is additive only** — no `--delete` flag, files are never removed from destinations
- **Journal system** — centralized SQLite (SwiftData) + decentralized JSON per disk (`.rsync-footages.journal`)
- **Files tracked by SHA256**, not by path — supports reorganization without losing tracking
- **Device detection** — reads MP4 metadata (`©too` encoder tag) via AVFoundation to identify camera model (DJI OsmoPocket3, etc.)
- **PROJECT.md** — place in a date folder to rename it with the project title (e.g. `20251222` → `20251222 - RC Car Vlog`). Applied during Reorganize, idempotent.
- **File type mapping** — configurable extension→folder mapping (`{type}` token: videos, audios, lowres, photos)
- **Pattern tokens** — `{device}`, `{year}`, `{month}`, `{day}`, `{type}` for file organization
- **Reorganize is idempotent** — files in titled folders (e.g. `20251222 - RC Car Vlog/videos/`) are recognized as correctly placed even when the pattern says `20251222/videos/`
- **DestinationAnalyzer** uses the same date-prefix matching — files in titled folders count as "already synced"
- **DiskArbitration** for volume detection, with fallback to `/Volumes/` polling
- **Demo mode** creates fake DJI device + destination in `~/.sync-my-footages/demo/`

## File Structure

```
Sources/RsyncMyFootages/
├── App/           — RsyncMyFootagesApp, AppState, WindowManager
├── Models/        — DJIDevice, FootageFile, SyncJob, JournalEntry, etc.
├── Services/      — Core logic (FileOrganizer, RsyncEngine, DeviceIdentifier, etc.)
├── Views/         — SwiftUI views (MenuBar, Settings, Sync, Redundancy, etc.)
└── Utilities/     — DJIFilenameParser, Constants
```

## Common Pitfalls

- `openWindow` / `showSettingsWindow:` don't work from MenuBarExtra — use `WindowManager.shared.open*()` instead
- `NSDirectoryEnumerator` can't be used in async contexts — extract to synchronous function
- `Regex` static properties need `nonisolated(unsafe)` for Swift 6 concurrency
- `AVFoundation.load(.metadata)` is async — use `DispatchSemaphore` on background thread, never on main thread
- exFAT volumes: no hardlinks, no file locking → use atomic writes (temp + rename) for journal JSON
- When reorganizing, strip `{device}/` from pattern if the selected directory IS already the device folder
- `startAccessingSecurityScopedResource()` must be called before any file operations on picker-selected URLs
