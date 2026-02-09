# Din

A minimal macOS audio player built with Swift and SwiftUI.

![Din](/meta/Screenshot.png?raw=true "Screenshot of the app"){height=270}

## Features

- Drag-and-drop or open audio files (MP3, M4A, AIFF, WAV, FLAC)
- M3U8 playlist save/load
- Media key support (play/pause, next, previous)
- Undo/redo for playlist changes
- Lightweight — no external dependencies

## Requirements

- macOS 14+
- Swift 5.9+

## Build

```sh
# Build
make build

# Build and run
make run

# Build .app bundle
make app
```

## Keyboard Shortcuts

| Key         | Action                |
| ----------- | --------------------- |
| Space       | Play / Pause          |
| `[` / `]`   | Previous / Next track |
| `{` / `}`   | Skip back / forward   |
| Enter       | Play selected         |
| Cmd+O       | Open files            |
| Cmd+Shift+O | Append files          |

## License

[MIT](LICENSE)
