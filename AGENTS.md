# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## What is Din

Din is a minimal macOS audio player built with SwiftUI and Swift Package Manager. It targets macOS 14+. There is no Xcode project — it builds entirely via SPM with Info.plist embedded via linker flags.

## Build & Run

```bash
make build     # swift build
make run       # build + run .build/debug/Din
make app       # build + create .app bundle at .build/Din.app
make clean     # swift package clean + remove .app bundle
```

## App Icon

The icon is generated programmatically. Requires `uv` and macOS `sips`/`iconutil`.

```bash
scripts/generate_icon.py      # renders scripts/build/icon_1024.png (uses uv run --script)
scripts/generate_assets.sh     # converts PNG → Din/Assets/Din.icns via sips + iconutil
```

## Architecture

**Single-singleton model:** `PlaylistManager.shared` is the central `@MainActor ObservableObject` that owns all state — playlist, playback (via `AVQueuePlayer` for gapless playback), persistence (`UserDefaults`), undo, and macOS media key integration (`MPRemoteCommandCenter`).

**Performance pattern:** `currentTime` is intentionally NOT `@Published` to avoid re-rendering the entire view tree every 0.25s. Instead, `ControlsView` uses `TimelineView(.animation)` to poll `displayTime` (which reads directly from `AVQueuePlayer.currentTime()`) only for the progress bar.

**Key files:**
- `Din/DinApp.swift` — App entry point, `NSOpenPanel` file handling, `AppDelegate` with keyboard shortcuts (space, `[]`, `{}`, enter) and double-click-to-play via `NSEvent` monitors
- `Din/Models/PlaylistManager.swift` — All playback, playlist mutation, persistence, undo, and media key logic
- `Din/Models/Track.swift` — Simple value type with metadata fields
- `Din/Utilities/MetadataLoader.swift` — Async AVAsset metadata extraction; also handles directory recursion for audio file discovery
- `Din/Views/` — `ContentView` (root layout + status bar), `ControlsView` (transport + volume + progress), `PlaylistView` (list with drag/drop/reorder/context menus), `ProgressBar` (seekable progress with drag gesture)

**Drag & drop:** Supported in both `ControlsView` (replaces playlist) and `PlaylistView` (adds to playlist, supports positional insert via `onInsert`).

**Persistence:** Playlist URLs, current track index, playback position, volume, and repeat state are saved to `UserDefaults` with `Din.*` keys. State auto-saves every 5 seconds during playback and on app termination.

## Checklist

When implementing new features or making significant changes, update the feature list in `README.md` to keep it in sync with the actual capabilities of the app.
