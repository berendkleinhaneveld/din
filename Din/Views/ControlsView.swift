import SwiftUI
import UniformTypeIdentifiers

struct ControlsView: View {
    @ObservedObject var manager: PlaylistManager
    @State private var isDropTargeted = false
    @FocusState private var focus: PlayerControl?

    var body: some View {
        VStack(spacing: 6) {
            // Now playing info — fixed height so controls don't shift
            VStack(alignment: .leading, spacing: 1) {
                Text(manager.currentTrack?.title ?? "Din")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if let subtitle = manager.currentTrack?.subtitle {
                        Text(subtitle)
                    } else {
                        Text(" ")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The column the thumbnail occupies, reserved permanently. Long titles truncate
            // earlier than they used to, and that is the trade. It must not be released when a
            // track has no artwork — the thumbnail is there either way, and a conditional inset
            // would reflow the title every time the playlist crossed an art-less track.
            .padding(.trailing, CoverThumbnail.side + CoverThumbnail.gap)
            // Attached to the padded block rather than laid out beside it: at 55 pt the tile is
            // taller than the two lines of type, and in flow it would push the transport row down.
            // Nothing below the now-playing block is allowed to move. The overlay's bottom edge
            // lands on the subtitle's — the alignment is the spec, not the resulting number — and
            // it overflows upward into the titlebar band, which is empty anyway.
            .overlay(alignment: .bottomTrailing) {
                CoverThumbnail(manager: manager)
            }

            TransportControls(manager: manager, focus: $focus)

            WaveformProgress(manager: manager)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(isDropTargeted ? 0.1 : 0))
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        DropLoader.loadURLs(from: providers) { urls in
            manager.replacePlaylist(urls: urls)
        }
    }
}

/// The way into cover mode: the current track's artwork, sitting in the one part of the window
/// that was already empty.
///
/// Always present, showing `ArtworkPlaceholder` for tracks with no embedded cover. That is what
/// stops cover mode from having to snap back to the queue partway through a playlist, and it is
/// what lets the inset beside it be unconditional.
///
/// It punches a hole in the window's drag region. Known and accepted: it is the corner furthest
/// from where people grab a window.
struct CoverThumbnail: View {
    @ObservedObject var manager: PlaylistManager

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    /// Inset by the window's own 12 pt gutter on the top and the side alike, so the corner reads
    /// as square.
    static let side: CGFloat = 55
    /// The gap between the tile and the now-playing text it displaces.
    static let gap: CGFloat = 22

    private let cornerRadius: CGFloat = 4

    /// Hover *and* keyboard focus, so the door is there for whichever one you are using.
    private var isRevealed: Bool { isHovering || isFocused }

    var body: some View {
        Button {
            CoverWindowController.shared.enterCoverMode()
        } label: {
            TrackArtwork(image: manager.currentArtwork)
                .frame(width: Self.side, height: Self.side)
                .clipped()
                .overlay {
                    // A veil with a glyph in it, rather than a glyph alone, so it reads as a door
                    // rather than as decoration.
                    ZStack {
                        Color(red: 6 / 255, green: 8 / 255, blue: 7 / 255).opacity(0.5)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                    }
                    .opacity(isRevealed ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.13), value: isRevealed)
        .accessibilityLabel("Show album cover")
        .help("Show album cover")
    }
}
