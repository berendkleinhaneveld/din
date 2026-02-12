# Din 

A minimal macOS audio player.

![Din](/meta/Screenshot.png?raw=true "Screenshot of the app")

Download latest release **[here](https://github.com/berendkleinhaneveld/din/releases/latest)**

## Features

- Drag-and-drop or open audio files (MP3, M4A, AIFF, WAV, FLAC)
- Waveform visualization with playback progress
- M3U8 playlist save/load
- Open Recent menu for quick access to previous files and playlists
- Media key support (play/pause, next, previous)
- Undo/redo for playlist changes
- Lightweight — no external dependencies

## Requirements

- macOS 14+

## Keyboard Shortcuts

| Key         | Action                |
| ----------- | --------------------- |
| Space       | Play / Pause          |
| `[` / `]`   | Previous / Next track |
| `{` / `}`   | Skip back / forward   |
| Enter       | Play selected         |
| Cmd+O       | Open files            |
| Cmd+Shift+O | Append files          |

## Build

```sh
# Build
make build

# Build and run
make run

# Build .app bundle
make app
```
