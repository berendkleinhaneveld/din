import SwiftUI
import UniformTypeIdentifiers

/// The now-playing block: title, transport, waveform. One view, both window shapes.
///
/// `overArtwork` restyles it rather than replacing it — padding, colours and the scrim behind it
/// all vary, but every modifier stays on the chain in both modes. Swapping modifiers in and out
/// with an `if` would change the view's identity and cost it its state, which is the whole thing
/// this sharing exists to protect: `WaveformProgress` and `WaveformView` below it hold the
/// waveform's bar-transition state, and losing it drops the bars to zero and grows them back on
/// every collapse.
struct ControlsView: View {
    @ObservedObject var manager: PlaylistManager

    /// Drawn over a cover rather than over the window chrome.
    var overArtwork = false
    /// Whether the block is showing. Always true in the queue window; over a cover it follows the
    /// pointer and the keyboard focus.
    var isRevealed = true
    @FocusState.Binding var focus: PlayerControl?

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            nowPlaying

            TransportControls(manager: manager, overArtwork: overArtwork, focus: $focus)

            WaveformProgress(manager: manager, overArtwork: overArtwork)
        }
        .padding(.horizontal, 12)
        // The cover's generous top padding is load-bearing — see `CoverScrim.bottom`.
        .padding(.top, overArtwork ? 84 : 8)
        .padding(.bottom, overArtwork ? 10 : 8)
        .background(background)
        .opacity(isRevealed ? 1 : 0)
        .allowsHitTesting(isRevealed)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(manager.currentTrack?.title ?? "Din")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(overArtwork ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
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
            .foregroundStyle(
                overArtwork ? AnyShapeStyle(Color.white.opacity(0.68)) : AnyShapeStyle(.secondary)
            )
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Insurance for covers brighter than the scrim: every mark carries its own shadow, so the
        // overlay never depends on the gradient alone.
        .shadow(color: .black.opacity(overArtwork ? 0.65 : 0), radius: 1.5, y: 1)
        // The column the thumbnail occupies, reserved permanently while the queue is showing. Long
        // titles truncate earlier than they used to, and that is the trade. It must not be released
        // when a track has no artwork — the thumbnail is there either way, and a conditional inset
        // would reflow the title every time the playlist crossed an art-less track.
        .padding(.trailing, overArtwork ? 0 : CoverThumbnail.side + CoverThumbnail.gap)
        // Attached to the padded block rather than laid out beside it: at 55 pt the tile is taller
        // than the two lines of type, and in flow it would push the transport row down. Nothing
        // below the now-playing block is allowed to move. The overlay's bottom edge lands on the
        // subtitle's — the alignment is the spec, not the resulting number — and it overflows
        // upward into the titlebar band, which is empty anyway.
        .overlay(alignment: .bottomTrailing) {
            CoverThumbnail(manager: manager)
                .opacity(overArtwork ? 0 : 1)
                .disabled(overArtwork)
        }
    }

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(isDropTargeted ? 0.1 : 0))

            CoverScrim.bottom
                .opacity(overArtwork ? 1 : 0)
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
