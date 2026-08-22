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

The icon is `AppIconArtwork`, a SwiftUI view, so the app and its icon are drawn by the same code.

```bash
scripts/render_readme.swift    # writes scripts/build/icon_1024.png and meta/Screenshot.png
scripts/generate_assets.sh     # converts the PNG → Din/Assets/Din.icns via sips + iconutil
```

Both need a Mac. `.github/workflows/assets.yml` runs them and commits the results, so neither image
has to be produced by hand.

The README screenshot is captured from the real interface, not assembled from mockups: the two
windows are hosted in an `NSWindow` and their display cached into a bitmap. `ImageRenderer` cannot
be used for it — the playlist is a `List`, which is NSTableView-backed on macOS, and `ImageRenderer`
draws a "not supported" placeholder in its place. `PlaylistManager.poseForScreenshot` supplies the
fixed state, and exists only for this.

## Seeing SwiftUI views without a Mac

SwiftUI only renders on Apple platforms, so a view cannot be looked at from a Linux or Windows
checkout. `scripts/render_readme.swift` already does the work on a macOS runner; adding a view to it
temporarily is the way to see one. Two things are worth knowing before trying:

- `ImageRenderer` renders SwiftUI only. Anything AppKit-backed — `List` most importantly — comes out
  as a "not supported" placeholder. Host it in an `NSWindow` and cache the window's display instead.
- A runner has no retina display and no pointing device, so a capture is 1x and gets legacy
  always-visible scrollbars unless both are corrected. `render_readme.swift` shows how.

`ArtworkPlaceholder` is drawn rather than shipped as a bitmap so it follows the appearance live: the
ground and the rim are `Color.primary` at low alpha, never a fixed grey, so the tile takes its cast
from whatever the chrome resolves to. What the light does is fixed — highlights white, occlusion
black, in both appearances — because a lit edge that inverted with the appearance would move the
light source with it.

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

## Pull requests

`master` only accepts squash merges — the branch's commits are collapsed into one, so the pull
request title becomes the commit message. Individual commit messages on a branch are working notes;
put the explanation that has to survive in the pull request description.

## Checklist

When implementing new features or making significant changes, update the feature list in `README.md` to keep it in sync with the actual capabilities of the app.
