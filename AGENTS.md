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

Icon direction studies live in `meta/icon-mockups.html` — open it in a browser. It is a
self-contained mockup board, not part of the build.

## Seeing SwiftUI views without a Mac

`ArtworkPlaceholder` is drawn rather than shipped as a bitmap, because `ContentView` backs the
window with `.ultraThinMaterial`: the chrome's resolved colour depends on the desktop behind the
window, so the view uses `Color.primary`, white and black at low alpha and never a fixed grey.

SwiftUI only renders on Apple platforms. `.github/workflows/render-placeholder.yml` rasterises the
view with `ImageRenderer` on a macOS runner and commits the PNGs to `meta/renders/`, so it can be
reviewed from anywhere. It runs on push to `claude/**` branches, or manually from the Actions tab
once the workflow is on the default branch — `workflow_dispatch` cannot be triggered from a branch
that the default branch does not already have the file on.

The same pattern works for any view: add it to `ContactSheet` in `scripts/render_placeholder.swift`.
The renderer is compiled by `swiftc` directly against the view file, so it needs no changes to
`Package.swift` and never ships in the app.

## Architecture

**Single-singleton model:** `PlaylistManager.shared` is the central `@MainActor ObservableObject` that owns all state — playlist, playback (via `AVQueuePlayer` for gapless playback), persistence (`UserDefaults`), undo, and macOS media key integration (`MPRemoteCommandCenter`).

**Performance pattern:** `currentTime` is intentionally NOT `@Published` to avoid re-rendering the entire view tree every 0.25s. Instead, `ControlsView` uses `TimelineView(.animation)` to poll `displayTime` (which reads directly from `AVQueuePlayer.currentTime()`) only for the progress bar.

**Key files:**
- `Din/DinApp.swift` — App entry point, `NSOpenPanel` file handling, `AppDelegate` with keyboard shortcuts (space, `[]`, `{}`, enter) and double-click-to-play via `NSEvent` monitors
- `Din/Models/PlaylistManager.swift` — All playback, playlist mutation, persistence, undo, and media key logic
- `Din/Models/Track.swift` — Simple value type with metadata fields
- `Din/Utilities/MetadataLoader.swift` — Async AVAsset metadata extraction; also handles directory recursion for audio file discovery
- `Din/Utilities/DropLoader.swift` — Shared drag-and-drop URL collection (order-preserving, thread-safe)
- `Din/Views/` — `ContentView` (root layout + status bar), `ControlsView` (transport + volume + progress), `PlaylistView` (list with drag/drop/reorder/context menus), `WaveformView` (seekable waveform with drag/hover + bar transitions)

**Drag & drop:** Supported in both `ControlsView` (replaces playlist) and `PlaylistView` (adds to playlist, supports positional insert via `onInsert`). Both go through `DropLoader`, which resolves providers concurrently but keeps drop order and never mutates shared state off the main queue.

**Window lifecycle:** The app deliberately outlives its window (`applicationShouldTerminateAfterLastWindowClosed` returns false) so playback continues. `AppDelegate.mainWindow` therefore resolves the content window *lazily* and pins it with `isReleasedWhenClosed = false`; `applicationShouldHandleReopen` must return `true` whenever there is no window to restore, or the app becomes unreachable. `Cmd+0` ("Din Window") is the menu-bar fallback, since the File menu's "New Window" item is replaced.

**Persistence:** Playlist URLs, current track index, playback position, volume, and repeat state are saved to `UserDefaults` with `Din.*` keys. State auto-saves every 5 seconds during playback and on app termination.

## Checklist

When implementing new features or making significant changes, update the feature list in `README.md` to keep it in sync with the actual capabilities of the app.
