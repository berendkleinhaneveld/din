import SwiftUI

/// Which of the player's controls holds keyboard focus.
///
/// The queue window has no use for this, but the cover does: its overlay is invisible at rest, so
/// without knowing that something inside it is focused, the overlay would be unreachable by
/// keyboard — you would be tabbing through controls you cannot see.
enum PlayerControl: Hashable {
    case previous
    case play
    case next
    case volume
    case close
}

/// Previous / play / next, with the volume button pinned to the right.
///
/// Shared by the queue window and the cover overlay so the two cannot drift apart. `overArtwork`
/// is the only difference between them: over a cover the glyphs go white and pick up a shadow,
/// because a sleeve can be any brightness and the scrim alone is not enough to guarantee contrast.
struct TransportControls: View {
    @ObservedObject var manager: PlaylistManager
    var overArtwork = false
    @FocusState.Binding var focus: PlayerControl?

    @State private var showVolumePopover = false

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                Button(action: manager.previous) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .focused($focus, equals: .previous)
                .disabled(!manager.hasContent)

                Button(action: manager.togglePlayPause) {
                    Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .focused($focus, equals: .play)
                .disabled(!manager.hasContent)

                Button(action: manager.next) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .focused($focus, equals: .next)
                .disabled(!manager.hasContent)
            }

            HStack {
                Spacer()
                Button {
                    showVolumePopover.toggle()
                } label: {
                    Image(systemName: volumeIconName)
                        .font(.system(size: 12))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .focused($focus, equals: .volume)
                .popover(isPresented: $showVolumePopover, arrowEdge: .bottom) {
                    Slider(
                        value: Binding(
                            get: { manager.volume },
                            set: { manager.setVolume($0) }
                        ), in: Float(0)...Float(1)
                    )
                    .frame(width: 100)
                    .padding(8)
                }
            }
        }
        .foregroundStyle(overArtwork ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .shadow(color: .black.opacity(overArtwork ? 0.6 : 0), radius: 1, y: 1)
    }

    private var volumeIconName: String {
        if manager.volume <= 0 { return "speaker.slash.fill" }
        if manager.volume < 0.33 { return "speaker.wave.1.fill" }
        if manager.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
