import SwiftUI

/// What cover mode adds behind and above the now-playing block: the artwork itself, and the top
/// gradient carrying the close button.
///
/// The block in front of it is `ControlsView`, the same one the queue window uses — see
/// `ContentView`. Only the pieces that exist in one mode and not the other live here.
struct CoverBackdrop: View {
    @ObservedObject var manager: PlaylistManager
    var isRevealed: Bool
    @FocusState.Binding var focus: PlayerControl?

    var body: some View {
        ZStack(alignment: .top) {
            TrackArtwork(image: manager.currentArtwork)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            topBand
                .opacity(isRevealed ? 1 : 0)
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
        .background(CoverScrim.top)
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
}

/// The two gradients the cover's overlay sits on.
///
/// Near-black rather than black, so they sit on artwork rather than punching a hole in it.
enum CoverScrim {
    private static let colour = Color(red: 6 / 255, green: 8 / 255, blue: 7 / 255)

    static let top = LinearGradient(
        stops: [
            .init(color: colour.opacity(0.72), location: 0),
            .init(color: colour.opacity(0.36), location: 0.45),
            .init(color: colour.opacity(0), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Paired with the 84 pt of top padding on the block in front of it, which is load-bearing: it
    /// pushes this ramp's soft end well above the text, so the title sits on the opaque part rather
    /// than on a bleached patch of sleeve.
    static let bottom = LinearGradient(
        stops: [
            .init(color: colour.opacity(0.96), location: 0),
            .init(color: colour.opacity(0.92), location: 0.30),
            .init(color: colour.opacity(0.74), location: 0.55),
            .init(color: colour.opacity(0.40), location: 0.76),
            .init(color: colour.opacity(0.12), location: 0.90),
            .init(color: colour.opacity(0), location: 1),
        ],
        startPoint: .bottom,
        endPoint: .top
    )
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
            ContentView(manager: manager, pose: .coverAtRest)
                .frame(width: 335, height: 335)
            ContentView(manager: manager, pose: .cover)
                .frame(width: 335, height: 335)
        }
        .padding(24)
    }
#endif
