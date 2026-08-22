import SwiftUI

/// The window's other shape: the current track's cover, edge to edge.
///
/// At rest there is nothing else — no chrome, no text, no traffic lights. Everything fades in on
/// pointer-over, and on focus-within so the overlay is reachable by keyboard rather than only by
/// mouse.
///
/// The bottom half is the top of `ControlsView` with a gradient behind it; the pieces they share
/// are `TransportControls` and `WaveformProgress`, so the two cannot drift apart.
struct CoverView: View {
    @ObservedObject var manager: PlaylistManager

    @State private var isHovering = false
    @FocusState private var focus: PlayerControl?

    #if DEBUG
        /// Holds the overlay open for anything looking at this view without a pointer to hover
        /// with — the previews below, and offscreen captures. Mirrors
        /// `PlaylistManager.poseForScreenshot`: it exists only so the view can be seen.
        var revealedForCapture = false
    #endif

    /// The scrims' colour, near-black but not black, so it sits on artwork rather than punching a
    /// hole in it.
    private static let scrim = Color(red: 6 / 255, green: 8 / 255, blue: 7 / 255)

    private var isRevealed: Bool {
        #if DEBUG
            if revealedForCapture { return true }
        #endif
        return isHovering || focus != nil
    }

    var body: some View {
        TrackArtwork(image: manager.currentArtwork, tiled: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay {
                overlay
                    .opacity(isRevealed ? 1 : 0)
            }
            .background(.ultraThinMaterial)
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.17), value: isRevealed)
    }

    private var overlay: some View {
        ZStack {
            VStack(spacing: 0) {
                topBand
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                bottomBand
            }
        }
    }

    private var topBand: some View {
        HStack(spacing: 0) {
            closeButton
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.top, 11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 72, alignment: .top)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Self.scrim.opacity(0.72), location: 0),
                    .init(color: Self.scrim.opacity(0.36), location: 0.45),
                    .init(color: Self.scrim.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// Corner arrows pointing inward rather than a ✕.
    ///
    /// A ✕ here sits exactly where the red traffic light sits, so it would read as *close the
    /// window* when what it does is *go back to the queue*. This is less familiar, but it says what
    /// actually happens — and it leaves a real close button free to be a real close button.
    private var closeButton: some View {
        Button {
            CoverWindowController.shared.exitCoverMode()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 20 / 255, green: 22 / 255, blue: 21 / 255).opacity(0.55))
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .focused($focus, equals: .close)
        .accessibilityLabel("Back to the queue")
        .help("Back to the queue")
    }

    private var bottomBand: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(manager.currentTrack?.title ?? "Din")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(manager.currentTrack?.subtitle ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Insurance for covers brighter than the scrim: every mark carries its own shadow, so
            // the overlay never depends on the gradient alone.
            .shadow(color: .black.opacity(0.65), radius: 1.5, y: 1)

            TransportControls(manager: manager, overArtwork: true, focus: $focus)

            WaveformProgress(manager: manager, overArtwork: true)
        }
        // The large top padding is load-bearing: it pushes the gradient's soft end well above the
        // text, so the title sits on the opaque part of the ramp rather than on a bleached patch
        // of sleeve.
        .padding(.top, 84)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Self.scrim.opacity(0.96), location: 0),
                    .init(color: Self.scrim.opacity(0.92), location: 0.30),
                    .init(color: Self.scrim.opacity(0.74), location: 0.55),
                    .init(color: Self.scrim.opacity(0.40), location: 0.76),
                    .init(color: Self.scrim.opacity(0.12), location: 0.90),
                    .init(color: Self.scrim.opacity(0), location: 1),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }
}

#if DEBUG
    #Preview("Cover window") {
        let manager = PlaylistManager()
        manager.poseForScreenshot(
            tracks: [
                Track(
                    url: URL(fileURLWithPath: "/fixtures/La fleur gravité.flac"),
                    title: "La fleur gravité", artist: "Syl Kougaï", album: "La fille verte",
                    duration: 281)
            ],
            playing: 0, at: 107,
            peaks: (0..<220).map { Float(abs(sin(Double($0) * 0.21)) * 0.7 + 0.12) })

        return HStack(spacing: 24) {
            CoverView(manager: manager)
                .frame(width: 335, height: 335)
            CoverView(manager: manager, revealedForCapture: true)
                .frame(width: 335, height: 335)
        }
        .padding(24)
    }
#endif
